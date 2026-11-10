# Host checks for the staged module (no aarch64 code is executed). Runs inside the builder.
#   python3 -I /src/ndk/scripts/check.py
import sys, os, subprocess, re, itertools

sys.path.insert(0, '/src/ndk/scripts')
import common
from common import MODID, ALTDIR

SJ = common.load(os.path.join(common.STAGE, 'stage.json'))
ST = SJ['stage']
# runtime tree: module system/etc/<MODID>/ = ALTDIR on the device; every ELF must be in its libexec/
RT = os.path.join(ST, ALTDIR.lstrip('/'))
LIBEXEC = os.path.join(RT, 'libexec')
SHARE = os.path.join(RT, 'share', MODID)
BIONIC_INTERP = '/system/bin/linker64'
BIONIC_LIBS = {'libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libz.so'}
FORBID = set('iptables ip6tables ip tc ss ethtool nsenter unshare chroot lsof nc file vmstat getfattr setfattr'.split())
# build paths that must not appear in a program; ALT_HOST_HOME = home directory of the user running build-ndk.sh
HOSTPATHS = [b'/work/build', b'/work/out', b'/opt/ndk', b'/.work/']
if os.environ.get('ALT_HOST_HOME', '').startswith('/'):
    HOSTPATHS.append(os.environ['ALT_HOST_HOME'].encode())
API = int(os.environ.get('API', '29'))

res = {'errors': [], 'libexec': {}, 'wrappers': {}, 'scripts': {}, 'version_audit': {}}
err = res['errors'].append


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True)


def elf(p):
    d = sh('readelf', '-h', '-d', '-l', '-n', '-W', p).stdout
    return {
        'machine': (re.search(r'Machine:\s+(.*)', d) or [None, None])[1],
        'type': (re.search(r'Type:\s+(\S+)', d) or [None, None])[1],
        'needed': re.findall(r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]', d),
        'runpath': re.findall(r'\((?:RUNPATH|RPATH)\)\s+Library (?:runpath|rpath): \[([^\]]+)\]', d),
        'interp': re.findall(r'Requesting program interpreter: ([^\]]+)\]', d),
    }


def android_api(p):
    # .note.android.ident: owner "Android", descriptor starts with the API level as little-endian u32
    d = sh('readelf', '-n', '-W', p).stdout
    i = d.find('.note.android.ident')
    m = re.search(r'Android\s+0x[0-9a-f]+\s+.*?description data: ((?:[0-9a-f]{2} ){4})', d[i:], re.S) if i >= 0 else None
    if not m:
        return None
    b = m.group(1).split()
    return int(b[3] + b[2] + b[1] + b[0], 16)


def syntax(path):
    out = {}
    for name, cmd in (('sh -n', ['sh', '-n', path]), ('bash --posix -n', ['bash', '--posix', '-n', path])):
        r = sh(*cmd)
        out[name] = r.returncode == 0
        if r.returncode:
            err('syntax (%s) %s: %s' % (name, os.path.relpath(path, ST), r.stderr.strip()))
    return out


origin = SJ['origin']
for f in sorted(os.listdir(LIBEXEC)):
    p = os.path.join(LIBEXEC, f)
    o = origin.get('libexec/' + f, '?')
    e = elf(p)
    fo = sh('file', '-b', p).stdout.strip()
    entry = dict(e, file=fo, origin=o)
    if e['machine'] != 'AArch64' or 'ARM aarch64' not in fo:
        err('not aarch64: ' + f)
    if not os.access(p, os.X_OK):
        err('not executable: ' + f)
    data = open(p, 'rb').read()
    hp = [h.decode() for h in HOSTPATHS if h in data]
    if hp:
        err('%s contains host paths %s' % (f, hp))
    # compiled-in runtime paths (terminfo, CA bundle, openssldir) must be under ALTDIR, not /data/adb (0700 root)
    if o.startswith('ndk:') and b'/data/adb' in data:
        err('%s contains a /data/adb path (unreadable for non-root users)' % f)
    if o.startswith('ndk:'):
        entry['android_api_note'] = android_api(p)
        if entry['android_api_note'] is None:
            err('no Android ELF note: ' + f)
        if e['interp']:
            entry['linkage'] = 'dynamic'
            if e['interp'] != [BIONIC_INTERP] or ('interpreter ' + BIONIC_INTERP) not in fo:
                err('ndk dynamic interp wrong: ' + f)
            if e['type'] != 'DYN':
                err('ndk dynamic not PIE: ' + f)
            bad = [n for n in e['needed'] if n not in BIONIC_LIBS]
            if bad:
                err('%s needs non-system libs %s' % (f, bad))
            if e['runpath']:
                err('ndk dynamic has RUNPATH: ' + f)
            if entry['android_api_note'] != API:
                err('%s Android note API %s != %d' % (f, entry['android_api_note'], API))
        else:
            entry['linkage'] = 'static'
            if 'statically linked' not in fo or e['needed']:
                err('ndk static wrong: ' + f)
    else:
        err('unknown origin for libexec/' + f)
    res['libexec'][f] = entry

# every ELF of the module must be a program in ALTDIR/libexec (no stray binaries or libraries elsewhere)
stray = []
for dirpath, dirs, files in os.walk(ST):
    dirs.sort()
    for f in sorted(files):
        fp = os.path.join(dirpath, f)
        if os.path.islink(fp) or os.path.dirname(fp) == LIBEXEC:
            continue
        with open(fp, 'rb') as fh:
            if fh.read(4) == b'\x7fELF':
                stray.append(os.path.relpath(fp, ST))
res['elf_outside_libexec'] = stray
if stray:
    err('ELF files outside %s/libexec: %s' % (ALTDIR, ' '.join(stray)))
# v2.1 layout leftovers: runtime files directly in the module directory (/data/adb, root-only)
for old in ('libexec', 'share/terminfo', 'share/' + MODID, 'etc/ssl', 'etc/alt-tools.map'):
    if os.path.lexists(os.path.join(ST, old)):
        err('runtime path %s is in the module directory (root-only on the device), not under %s' % (old, ALTDIR))
# every program is an NDK build: no musl loader or libraries (lib/), no resolv.conf overlay
if os.path.lexists(os.path.join(ST, 'lib')):
    err('lib/ exists in the module directory')
if os.path.exists(os.path.join(SHARE, 'resolv-refresh')):
    err('the v1 resolv.conf overlay (resolv-refresh) is shipped')
if re.search(r'ld-musl|system/etc/resolv\.conf', open(os.path.join(ST, 'customize.sh')).read()):
    err('customize.sh handles musl/resolv.conf')

has_bpftool = os.path.exists(os.path.join(LIBEXEC, 'bpftool'))
res['bpftool'] = {'present': has_bpftool, 'origin': origin.get('libexec/bpftool', '')}
if not has_bpftool:
    err('module lacks bpftool')

for w in sorted(os.listdir(os.path.join(ST, 'system', 'bin'))):
    p = os.path.join(ST, 'system', 'bin', w)
    txt = open(p).read()
    syn = syntax(p)
    if w == 'alt-list':
        target_ok = True
    else:
        m = re.search(r'exec "\$ALTDIR/libexec/([^"]+)"', txt)
        target_ok = bool(m) and os.path.isfile(os.path.join(LIBEXEC, m.group(1)))
        if ('ALTDIR=' + ALTDIR + '\n') not in txt:
            err('wrapper ALTDIR wrong: ' + w)
    # customize.sh and phone-test.sh recognise this module's wrappers by the ALTDIR line in the
    # first 400 bytes (head -c 400); without it an upgrade renames the new wrapper to <name>-ng
    if ('ALTDIR=' + ALTDIR) not in txt[:400]:
        err('wrapper %s: ALTDIR marker not within the first 400 bytes' % w)
    # runtime files must be reachable by every uid: no $MODDIR and no /data/adb path in any wrapper
    if 'MODDIR' in txt or '/data/adb' in txt:
        err('wrapper %s references $MODDIR or /data/adb (root-only) for runtime files' % w)
    shadow = w in FORBID
    res['wrappers'][w] = {'syntax': syn, 'target_ok': target_ok, 'static_forbidden_name': shadow}
    if not target_ok or shadow:
        err('wrapper bad: ' + w)
    if not os.access(p, os.X_OK):
        err('wrapper not executable: ' + w)

RTREL = os.path.relpath(SHARE, ST)
scripts = ['customize.sh', 'META-INF/com/google/android/update-binary', RTREL + '/phone-test.sh']
if os.path.exists(os.path.join(SHARE, 'dns-servers')):
    scripts.append(RTREL + '/dns-servers')
for s in scripts:
    res['scripts'][s] = syntax(os.path.join(ST, s))
cz = open(os.path.join(ST, 'customize.sh')).read()
for bad in (r'\bksud\b', r'\bmagisk\b\s+--', r'\bapd\b', r'\bbusybox\b'):
    if re.search(bad, cz):
        err('customize.sh uses manager-specific command ' + bad)
if os.path.exists(os.path.join(SHARE, 'dns-servers')) and '/data/adb' in open(os.path.join(SHARE, 'dns-servers')).read():
    err('dns-servers references /data/adb')
if not re.search(r'set_perm_recursive "\$ALT_RT/libexec" 0 0 0755 0755 "\$ALT_CTX"', cz) or 'ALT_CTX=u:object_r:system_file:s0' not in cz:
    err('customize.sh does not set root:root 0755 system_file on the runtime libexec')
pt = open(os.path.join(SHARE, 'phone-test.sh')).read()
if re.search(r'^\s*(function\s+)?hash\s*\(\)', pt, re.M):
    err('phone-test.sh defines a function named hash')
for bad in ('post-fs-data.sh', 'service.sh', 'post-mount.sh', 'boot-completed.sh', 'system.prop', 'sepolicy.rule'):
    if os.path.exists(os.path.join(ST, bad)):
        err('module boot script present: ' + bad)
prop = dict(l.split('=', 1) for l in open(os.path.join(ST, 'module.prop')).read().splitlines() if '=' in l)
for k in ('id', 'name', 'version', 'versionCode', 'author', 'description'):
    if not prop.get(k):
        err('module.prop lacks ' + k)
if prop.get('id') != MODID:
    err('module.prop id invalid')
if not prop.get('versionCode', '').isdigit() or int(prop['versionCode']) <= 32401:
    err('versionCode not numeric or not above v1 (32401)')
res['module_prop'] = prop
for t in ('xterm', 'xterm-256color', 'screen', 'tmux', 'linux', 'vt100'):
    if not os.path.isfile(os.path.join(RT, 'share', 'terminfo', t[0], t)):
        err('terminfo missing ' + t)
if os.path.getsize(os.path.join(RT, 'etc', 'ssl', 'cert.pem')) < 100000:
    err('CA bundle too small')


# ---- version banner audit (patterns of phone-test.sh vchk lines against ELF strings), as in v1
def strings(p, cache={}):
    if p not in cache:
        data = open(p, 'rb').read()
        cache[p] = [m.decode('latin-1') for m in re.findall(rb'[\x20-\x7e\t]{3,}', data)]
    return cache[p]


RUNTIME = {'getpcaps': 'output is "<pid>: <caps>" built at run time from argv'}
FMT = re.compile(r'%[-+ #0-9.]*(?:l|ll|h|z)?[sdiu]')


def numeric(st, m):
    before = st[m.start() - 1:m.start()]
    after = st[m.end():m.end() + 1]
    return '0' if before in ('v', '.') or after == '.' else 'N'


def renders(strs, cands):
    out = []
    for i, st in enumerate(strs):
        convs = FMT.findall(st)
        ns = sum(1 for c in convs if c.endswith('s'))
        if not convs or ns > 4 or len(st) > 200:
            continue
        near = [x for x in strs[max(0, i - 4):i + 5] if x != st and len(x) < 40 and '%' not in x]
        pool = list(dict.fromkeys(cands + near))
        for combo in itertools.product(pool, repeat=ns):
            it = iter(combo)
            out.append(FMT.sub(lambda m: next(it) if m.group(0).endswith('s') else numeric(st, m), st))
    return out


target_of = {t['tool']: t for t in SJ['tools'] if t['tool']}
# version/usage banners of tools that have no vchk line in phone-test.sh (real banner text of each program)
VERSION_PATTERNS = {
    'nmap': 'Nmap version [0-9]', 'nping': 'Nping version [0-9]', 'openssl': '^OpenSSL [0-9]',
    'dropbear': 'Dropbear v[0-9]', 'dbclient': 'Dropbear v[0-9]', 'ssh': 'Dropbear v[0-9]',
    'scp': 'usage: scp ', 'dropbearkey': 'Usage: dropbearkey -t', 'dropbearconvert': 'Usage: dropbearconvert <inputtype>',
    'iw': 'iw version [0-9]', 'gdbserver': 'GNU gdbserver ', 'ltrace': '^ltrace [0-9]', 'fio': '^fio-[0-9]',
    'eu-stack': r'^eu-stack \(elfutils\) [0-9]', 'eu-readelf': r'^eu-readelf \(elfutils\) [0-9]',
    'eu-nm': r'^eu-nm \(elfutils\) [0-9]', 'eu-unstrip': r'^eu-unstrip \(elfutils\) [0-9]',
    'eu-addr2line': r'^eu-addr2line \(elfutils\) [0-9]',
    'objdump': r'\(GNU Binutils\) [0-9]', 'nm': r'\(GNU Binutils\) [0-9]', 'addr2line': r'\(GNU Binutils\) [0-9]',
    'readelf': r'\(GNU Binutils\) [0-9]', 'strings': r'\(GNU Binutils\) [0-9]', 'patchelf': '^patchelf [0-9]',
    'dtc': '^DTC [0-9]', 'fdtdump': '^DTC [0-9]', 'fdtget': '^DTC [0-9]', 'fdtput': '^DTC [0-9]', 'fdtoverlay': '^DTC [0-9]',
    'mkfs.erofs': r'^mkfs\.erofs \(erofs-utils\) [0-9]', 'fsck.erofs': r'^fsck\.erofs \(erofs-utils\) [0-9]',
    'dump.erofs': r'^dump\.erofs \(erofs-utils\) [0-9]', 'mksquashfs': 'version 4\\.[0-9]', 'unsquashfs': 'version 4\\.[0-9]',
    'fatrace': '^Usage: fatrace ', 'ecapture': 'ecap_android_arm64:v[0-9]',
    'nsenter-ng': 'nsenter from util-linux', 'unshare-ng': 'unshare from util-linux', 'lsns': 'lsns from util-linux',
    'losetup': 'losetup from util-linux', 'dmesg': 'dmesg from util-linux', 'wipefs': 'wipefs from util-linux',
    'fallocate': 'fallocate from util-linux', 'zramctl': 'zramctl from util-linux',
    'taskset': 'taskset from util-linux', 'chrt': 'chrt from util-linux', 'ionice': 'ionice from util-linux',
    'prlimit': 'prlimit from util-linux', 'rfkill': 'rfkill from util-linux', 'hexdump': 'hexdump from util-linux',
    'script': 'script from util-linux', 'getcap': 'usage: getcap ', 'setcap': 'usage: setcap ',
    'pscap': 'usage: pscap', 'netcap': 'usage: netcap', 'filecap': 'usage: filecap', 'debugfs': 'debugfs [0-9]',
    'dumpe2fs': 'dumpe2fs [0-9]', 'e2image': 'e2image [0-9]', 'filefrag': 'filefrag [0-9]',
    'mkfs.f2fs': r'mkfs\.f2fs Ver: ', 'resize.f2fs': r'Usage: resize\.f2fs ', 'sload.f2fs': r'Usage: sload\.f2fs ',
    'f2fs_io': '^f2fs_io [a-z]', 'nstat': 'nstat utility, iproute2-', 'ifstat': 'ifstat utility, iproute2-',
    'genl': 'genl utility, iproute2-', 'devlink': 'devlink utility, iproute2-', 'rtmon': 'rtmon utility, iproute2-',
    'lnstat': 'lnstat Version ', 'nslookup': 'nslookup [0-9]', 'delv': 'delv [0-9]', 'nsupdate': 'nsupdate [0-9]',
    'objcopy': r'\(GNU Binutils\) [0-9]', 'strip': r'\(GNU Binutils\) [0-9]', 'size': r'\(GNU Binutils\) [0-9]',
    'ar': r'\(GNU Binutils\) [0-9]', 'c++filt': r'\(GNU Binutils\) [0-9]', 'elfedit': r'\(GNU Binutils\) [0-9]',
    'eu-strip': r'^eu-strip \(elfutils\) [0-9]', 'eu-elflint': r'^eu-elflint \(elfutils\) [0-9]',
    'eu-elfcmp': r'^eu-elfcmp \(elfutils\) [0-9]', 'eu-size': r'^eu-size \(elfutils\) [0-9]',
    'eu-elfclassify': r'^eu-elfclassify \(elfutils\) [0-9]', 'sqldiff': r'sqlite\.org/sqldiff\.html',
    'sqlite3_rsync': 'sqlite3_rsync ORIGIN REPLICA', 'sar': 'sysstat version [0-9]', 'sqfstar': 'version 4\\.[0-9]',
    'sqfscat': 'version 4\\.[0-9]', 'procan': 'procan by Gerhard Rieger', 'filan': 'filan by Gerhard Rieger',
    'bashreadline': '^bashreadline [0-9]+\\.[0-9]', 'bindsnoop': '^bindsnoop [0-9]+\\.[0-9]',
    'biolatency': '^biolatency [0-9]+\\.[0-9]', 'biopattern': '^biopattern [0-9]+\\.[0-9]',
    'biosnoop': '^biosnoop [0-9]+\\.[0-9]', 'biostacks': '^biostacks [0-9]+\\.[0-9]',
    'biotop': '^biotop [0-9]+\\.[0-9]', 'bitesize': '^bitesize [0-9]+\\.[0-9]',
    'cachestat': '^cachestat [0-9]+\\.[0-9]', 'capable': '^capable [0-9]+\\.[0-9]',
    'cpudist': '^cpudist [0-9]+\\.[0-9]', 'cpufreq': '^cpufreq [0-9]+\\.[0-9]', 'drsnoop': '^drsnoop [0-9]+\\.[0-9]',
    'execsnoop': '^execsnoop [0-9]+\\.[0-9]', 'exitsnoop': '^exitsnoop [0-9]+\\.[0-9]',
    'filelife': '^filelife [0-9]+\\.[0-9]', 'filetop': '^filetop [0-9]+\\.[0-9]', 'fsdist': '^fsdist [0-9]+\\.[0-9]',
    'fsslower': '^fsslower [0-9]+\\.[0-9]', 'funclatency': '^funclatency [0-9]+\\.[0-9]',
    'futexctn': '^futexctn [0-9]+\\.[0-9]', 'gethostlatency': '^gethostlatency [0-9]+\\.[0-9]',
    'hardirqs': '^hardirqs [0-9]+\\.[0-9]', 'javagc': '^javagc [0-9]+\\.[0-9]',
    'klockstat': '^klockstat [0-9]+\\.[0-9]', 'llcstat': '^llcstat [0-9]+\\.[0-9]',
    'mdflush': '^mdflush [0-9]+\\.[0-9]', 'memleak': '^memleak [0-9]+\\.[0-9]',
    'mountsnoop': '^mountsnoop [0-9]+\\.[0-9]', 'numamove': '^numamove [0-9]+\\.[0-9]',
    'offcputime': '^offcputime [0-9]+\\.[0-9]', 'oomkill': '^oomkill [0-9]+\\.[0-9]',
    'opensnoop': '^opensnoop [0-9]+\\.[0-9]', 'profile': '^profile [0-9]+\\.[0-9]',
    'readahead': '^readahead [0-9]+\\.[0-9]', 'runqlat': '^runqlat [0-9]+\\.[0-9]',
    'runqlen': '^runqlen [0-9]+\\.[0-9]', 'runqslower': '^runqslower [0-9]+\\.[0-9]',
    'sigsnoop': '^sigsnoop [0-9]+\\.[0-9]', 'slabratetop': '^slabratetop [0-9]+\\.[0-9]',
    'softirqs': '^softirqs [0-9]+\\.[0-9]', 'solisten': '^solisten [0-9]+\\.[0-9]',
    'statsnoop': '^statsnoop [0-9]+\\.[0-9]', 'syncsnoop': '^syncsnoop [0-9]+\\.[0-9]',
    'syscount': '^syscount [0-9]+\\.[0-9]', 'tcpconnect': '^tcpconnect [0-9]+\\.[0-9]',
    'tcpconnlat': '^tcpconnlat [0-9]+\\.[0-9]', 'tcplife': '^tcplife [0-9]+\\.[0-9]',
    'tcppktlat': '^tcppktlat [0-9]+\\.[0-9]', 'tcprtt': '^tcprtt [0-9]+\\.[0-9]',
    'tcpstates': '^tcpstates [0-9]+\\.[0-9]', 'tcpsynbl': '^tcpsynbl [0-9]+\\.[0-9]',
    'tcptop': '^tcptop [0-9]+\\.[0-9]', 'tcptracer': '^tcptracer [0-9]+\\.[0-9]',
    'vfsstat': '^vfsstat [0-9]+\\.[0-9]', 'wakeuptime': '^wakeuptime [0-9]+\\.[0-9]', 'ksnoop': r'\[COMMAND \| help\] FUNC',
    'lldb-server': 'lldb version [0-9]', 'rg': '^ripgrep ', 'fd': 'A program to find entries in your filesystem',
    'fzf': r'Usage: fzf \[options\]', 'ncdu': 'ncdu [0-9]', 'picocom': 'picocom v[0-9]',
    'rizin': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm', 'rz-bin': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm',
    'rz-asm': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm', 'rz-hash': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm',
    'rz-diff': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm', 'rz-find': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm',
    'rz-gg': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm', 'rz-ax': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm',
    'rz-run': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm', 'rz-sign': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm',
    'rz-ar': '[0-9]+\\.[0-9]+\\.[0-9]+ @ linux-arm', 'mount.nfs': 'linux nfs-utils [0-9]',
    'mount.nfs4': 'linux nfs-utils [0-9]', 'umount.nfs': 'linux nfs-utils [0-9]',
    'umount.nfs4': 'linux nfs-utils [0-9]', 'git': 'git version [0-9]', 'git-upload-pack': 'git version [0-9]',
    'git-receive-pack': 'git version [0-9]', 'git-upload-archive': 'git version [0-9]',
    'adb': 'Android Debug Bridge version ', 'fastboot': 'fastboot version ', 'simg2img': 'Usage: simg2img ',
    'img2simg': 'Usage: img2simg ', 'lpunpack': 'tool for extracting partition images from super',
    'lpmake': 'tool for creating Android Logical Partition images',
}
checks = []
for line in pt.splitlines():
    m = re.match(r"\s*vchk\s+(\S+)\s+'([^']*)'", line)
    if m:
        checks.append((m.group(1), m.group(2)))
checks += [(t, p) for t, p in sorted(VERSION_PATTERNS.items()) if t not in {c[0] for c in checks}]
for tool, pat in checks:
    if tool not in target_of:
        res['version_audit'][tool] = {'pattern': pat, 'status': 'not in module'}
        continue
    t = target_of[tool]
    binp = os.path.join(LIBEXEC, t['libexec'])
    rx = re.compile(pat, re.I)
    allstr = strings(binp)
    pver = re.sub(r'-r\d+$', '', t['version'])
    vers = sorted({x for x in allstr if re.fullmatch(r'\d+(\.\d+)*[a-z]?', x) and pver.startswith(x[:2])})
    cands = [t['libexec'], t['recipe'], pver] + [x for x in vers if x != pver][:4] + [x for x in allstr if pver in x and len(x) < 40][:4]
    entry = {'pattern': pat, 'binary': t['libexec'], 'origin': t['origin']}
    own = [x for x in strings(binp) if rx.search(x)]
    rend = [] if own else [x for x in renders(strings(binp), cands) if rx.search(x)]
    if tool in RUNTIME:
        entry.update(status='runtime', evidence=RUNTIME[tool])
    elif own:
        entry.update(status='ok', evidence='literal in %s: %s' % (t['libexec'], own[0][:100]))
    elif rend:
        entry.update(status='ok', evidence='printf-rendered from %s: %s' % (t['libexec'], rend[0][:100]))
    else:
        entry.update(status='NO MATCH', evidence=None)
        err('version pattern %r for %s not found in ELF strings' % (pat, tool))
    res['version_audit'][tool] = entry
for t in target_of:
    if t not in res['version_audit']:
        err('no version check (phone-test.sh vchk or VERSION_PATTERNS) for ' + t)

res['summary'] = {'libexec_elfs': len(res['libexec']),
                  'wrappers': len(res['wrappers']), 'errors': len(res['errors']),
                  'ndk_static': sum(1 for v in res['libexec'].values() if v.get('linkage') == 'static'),
                  'ndk_dynamic': sum(1 for v in res['libexec'].values() if v.get('linkage') == 'dynamic'),
                  'elf_outside_libexec': len(stray),
                  'version_checks_ok': sum(1 for v in res['version_audit'].values() if v['status'] == 'ok')}
common.dump(res, os.path.join(common.STAGE, 'host_checks.json'))
print(__import__('json').dumps(res['summary'], sort_keys=True))
for e in res['errors']:
    print('ERR', e)
sys.exit(1 if res['errors'] else 0)
