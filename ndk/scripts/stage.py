# Stage the v2 module (NDK tools + remaining v1 Alpine tools) for one flavour. Runs inside the builder.
#   python3 -I /src/ndk/scripts/stage.py FLAVOUR
import sys, os, json, shutil, subprocess, re, hashlib

sys.path.insert(0, '/src/scripts')
import common
from common import MODID, MODDIR, ALTDIR, LDSO

SRC = '/src'
OUT = '/work/out'
V1 = '/work/stage/v1root'
FLAVOUR = sys.argv[1]
NEEDS_ALPINE_ONLY = sys.argv[2:] == ['--needs-alpine']
if FLAVOUR not in common.FLAVOURS:
    raise SystemExit('flavour must be lite or full')
ST = os.path.join('/work/stage', FLAVOUR, MODID)
# runtime tree: module system/etc/<MODID>/ = /system/etc/<MODID> on the device (ALTDIR)
RT = os.path.join(ST, ALTDIR.lstrip('/'))
LIBEXEC = os.path.join(RT, 'libexec')
SHARE = os.path.join(RT, 'share', MODID)
P1 = common.Paths(V1)
LOCK = common.load(os.path.join(SRC, 'alpine.lock.json'))
PK = LOCK['packages']
CONF2 = {}
for line in open(os.path.join(SRC, 'ndk', 'build.conf')):
    line = line.strip()
    if line and not line.startswith('#'):
        k, v = line.split('=', 1)
        CONF2[k] = v
m = re.fullmatch(r'(\d+)\.(\d+)', CONF2['V2_VERSION'])
REL = int(CONF2['MODULE_RELEASE'])
if not m or not 1 <= REL <= 99:
    raise SystemExit('bad V2_VERSION/MODULE_RELEASE in ndk/build.conf')
VERSION = 'v%s-r%d' % (CONF2['V2_VERSION'], REL)
VCODE = int(m.group(1)) * 100000 + int(m.group(2)) * 1000 + REL
API = int(os.environ.get('API', '29'))
NDK_RELEASE = os.environ.get('NDK_RELEASE', '')
REPO_URL = 'https://git.digtvbg.com/ivangotoy/android-linux-tools'

EXTRA_ENV = {
    'mtr': ['export MTR_PACKET="$ALTDIR/libexec/mtr-packet"'],
    'tmux': ['[ -n "$TMUX_TMPDIR" ] || export TMUX_TMPDIR=/data/local/tmp',
             '[ -n "$SHELL" ] || export SHELL=/system/bin/sh'],
}
ALPINE_ENV = {'curl': ['export CURL_CA_BUNDLE="$ALTDIR/etc/ssl/cert.pem"']}
TERMS = ['xterm', 'xterm-256color', 'xterm-color', 'screen', 'screen-256color', 'tmux', 'tmux-256color',
         'linux', 'vt100', 'vt220', 'dumb', 'ansi', 'rxvt', 'rxvt-unicode', 'rxvt-unicode-256color']


def run(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True).stdout


def needed(p):
    return re.findall(r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]', run('readelf', '-d', p))


def write(path, text, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    os.chmod(path, mode)


def copyfile(src, dst, mode):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, mode)


def sha256(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


# ---- tool tables
v1tools = common.tools_for(common.read_tools(SRC), FLAVOUR)
ndkrows = []
for line in open(os.path.join(SRC, 'ndk', 'tools.tsv')):
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    name, recipe, binary, args, flags = line.split()
    ndkrows.append({'name': None if name == '-' else name, 'recipe': recipe, 'target': binary,
                    'args': '' if args == '-' else args, 'flags': [] if flags == '-' else flags.split(',')})
meta = {}
for f in sorted(os.listdir(os.path.join(OUT, 'meta'))):
    if f.endswith('.json'):
        meta[f[:-5]] = common.load(os.path.join(OUT, 'meta', f))
ndk_ok = {r['target']: r for r in ndkrows
          if r['recipe'] in meta and os.path.isfile(os.path.join(OUT, 'bin', r['target']))}
ndk_by_name = {r['name']: r for r in ndkrows if r['name'] and r['target'] in ndk_ok}

entries = []   # {name, target, args, origin, flags, recipe|package}
seen_targets = set()
for t in v1tools:
    # since v2.1 both flavours use the NDK bpftool (no LLVM); an Alpine binary is only a fallback for a
    # tool without an NDK build (ALLOW_ALPINE=1 in ndk/build.conf)
    if t['name'] and t['name'] in ndk_by_name:
        r = ndk_by_name[t['name']]
        entries.append(dict(r, origin='ndk'))
    elif t['name'] is None and t['target'] in ndk_ok:
        entries.append(dict(ndk_ok[t['target']], origin='ndk'))
    else:
        entries.append({'name': t['name'], 'target': t['target'], 'args': t['args'], 'flags': t['flags'],
                        'package': t['package'], 'src': t['src'], 'origin': 'alpine'})
v1names = {t['name'] for t in v1tools}
v1targets = {t['target'] for t in v1tools if t['name'] is None}
for r in ndkrows:
    if r['target'] in ndk_ok and r['name'] not in v1names and not (r['name'] is None and r['target'] in v1targets):
        entries.append(dict(r, origin='ndk'))
# a libexec target is either NDK or Alpine, never both
tgt_origin = {}
for e in entries:
    if tgt_origin.setdefault(e['target'], e['origin']) != e['origin']:
        raise SystemExit('libexec %s needed from both ndk and alpine' % e['target'])
if NEEDS_ALPINE_ONLY:
    # package.sh: fetch the v1 Alpine packages only if some tool still needs them
    for e in entries:
        if e['origin'] == 'alpine':
            print(e['package'])
    sys.exit(0)
if CONF2.get('ALLOW_ALPINE', '1') != '1' and any(e['origin'] == 'alpine' for e in entries):
    raise SystemExit('ALLOW_ALPINE=0 but no NDK build for: %s' % ' '.join(
        sorted({e['name'] or e['target'] for e in entries if e['origin'] == 'alpine'})))

# ---- fresh stage
if os.path.exists(os.path.dirname(ST)):
    shutil.rmtree(os.path.dirname(ST))
os.makedirs(os.path.join(ST, 'system', 'bin'))
os.makedirs(os.path.join(ST, 'share', 'licenses'))
for d in ('libexec', 'share/terminfo', 'etc/ssl', 'share/' + MODID):
    os.makedirs(os.path.join(RT, d))

origin = {}
for e in entries:
    dst = os.path.join(LIBEXEC, e['target'])
    if os.path.exists(dst):
        continue
    if e['origin'] == 'ndk':
        copyfile(os.path.join(OUT, 'bin', e['target']), dst, 0o755)
        origin['libexec/' + e['target']] = 'ndk:' + e['recipe']
    else:
        copyfile(os.path.realpath(os.path.join(P1.unp, e['package'], e['src'])), dst, 0o755)
        origin['libexec/' + e['target']] = 'alpine:' + e['package']

alpine_targets = sorted({e['target'] for e in entries if e['origin'] == 'alpine'})
if alpine_targets:
    libindex = {}
    for pkg in sorted(os.listdir(P1.unp)):
        for d in ('lib', 'usr/lib'):
            base = os.path.join(P1.unp, pkg, d)
            if os.path.isdir(base):
                for f in sorted(os.listdir(base)):
                    fp = os.path.join(base, f)
                    if os.path.isfile(fp) and '.so' in f:
                        libindex.setdefault(f, (pkg, os.path.realpath(fp)))
    os.makedirs(os.path.join(ST, 'lib'))
    copyfile(os.path.realpath(os.path.join(P1.unp, 'musl', 'lib', LDSO)), os.path.join(ST, 'lib', LDSO), 0o755)
    origin['lib/' + LDSO] = 'alpine:musl'
    os.symlink(LDSO, os.path.join(ST, 'lib', 'libc.musl-aarch64.so.1'))
    queue = [os.path.join(LIBEXEC, t) for t in alpine_targets]
    missing = []
    while queue:
        p = queue.pop(0)
        for n in needed(p):
            if n in ('libc.musl-aarch64.so.1', LDSO):
                continue
            dst = os.path.join(ST, 'lib', n)
            if os.path.exists(dst):
                continue
            if n not in libindex:
                missing.append((os.path.basename(p), n))
                continue
            copyfile(libindex[n][1], dst, 0o644)
            origin['lib/' + n] = 'alpine:' + libindex[n][0]
            queue.append(dst)
    if missing:
        raise SystemExit('missing libs: %r' % missing)
    for t in alpine_targets:
        run('patchelf', '--set-interpreter', MODDIR + '/lib/' + LDSO, '--set-rpath', MODDIR + '/lib',
            os.path.join(LIBEXEC, t))
    for l in sorted(os.listdir(os.path.join(ST, 'lib'))):
        p = os.path.join(ST, 'lib', l)
        if os.path.islink(p) or l == LDSO:
            continue
        if [n for n in needed(p) if n != 'libc.musl-aarch64.so.1']:
            run('patchelf', '--set-rpath', MODDIR + '/lib', p)

# ---- data: terminfo (built by the ncurses recipe) and the CA bundle (cacert recipe)
tsrc = os.path.join(OUT, 'data', 'terminfo')
for t in TERMS:
    s = os.path.join(tsrc, t[0], t)
    if not os.path.isfile(s):
        continue  # e.g. rxvt-unicode is no longer in ncurses' terminfo.src; check.py requires the core set
    copyfile(s, os.path.join(RT, 'share', 'terminfo', t[0], t), 0o644)
origin['data:terminfo'] = 'ndk:ncurses'
copyfile(os.path.join(OUT, 'data', 'cacert.pem'), os.path.join(RT, 'etc', 'ssl', 'cert.pem'), 0o644)
origin['data:etc/ssl/cert.pem'] = 'ndk:cacert'

# ---- wrappers
need_resolv = any(e['origin'] == 'alpine' and 'dns' in e['flags'] for e in entries if e['name'])
need_dnsservers = any(e['origin'] == 'ndk' and ('dns' in e['flags'] or 'dnsenv' in e['flags']) for e in entries if e['name'])
wrappers = []
for e in entries:
    if e['name'] is None:
        continue
    # every path is under ALTDIR (/system/etc/<MODID>, mounted by the root manager), never /data/adb (root-only)
    lines = ['#!/system/bin/sh', 'ALTDIR=' + ALTDIR, 'export TERMINFO="$ALTDIR/share/terminfo"']
    if e['origin'] == 'alpine':
        lines.append('export SSL_CERT_FILE="$ALTDIR/etc/ssl/cert.pem"')
    lines.append('[ -n "$TMPDIR" ] || export TMPDIR=/data/local/tmp')
    lines += EXTRA_ENV.get(e['name'], [])
    if e['origin'] == 'alpine':
        lines += ALPINE_ENV.get(e['name'], [])
        if 'dns' in e['flags']:
            lines.append('[ "${USER_ID:-$(id -u)}" = 0 ] && /system/bin/sh "$ALTDIR/share/%s/resolv-refresh" >/dev/null 2>&1' % MODID)
    exe = '"$ALTDIR/libexec/%s" %s' % (e['target'], e['args'] + ' ' if e['args'] else '')
    if e['origin'] == 'ndk' and e['name'] == 'curl':
        lines += ['# CA certificates: bundled Mozilla bundle plus the Android system store (mbedTLS loads every file in --capath)',
                  'ALT_CA="--cacert $ALTDIR/etc/ssl/cert.pem"',
                  'if [ -d /system/etc/security/cacerts ]; then',
                  '  ALT_CA="$ALT_CA --capath /system/etc/security/cacerts"',
                  'elif [ -d /apex/com.android.conscrypt/cacerts ]; then',
                  '  ALT_CA="$ALT_CA --capath /apex/com.android.conscrypt/cacerts"',
                  'fi',
                  '# curl requires -q/--disable to be the first argument',
                  'case "$1" in',
                  '  -q|--disable) shift; exec %s-q $ALT_CA "$@" ;;' % exe,
                  'esac',
                  'exec %s$ALT_CA "$@"' % exe]
    elif e['origin'] == 'ndk' and 'dnsenv' in e['flags']:
        lines += ['# BIND dig/host: no resolv.conf on Android. Without @server (dig) or a server argument (host) they use',
                  '# ALT_DNS_SERVERS (patched dighost.c): the DNS servers of the active default network.',
                  'if [ -z "$ALT_DNS_SERVERS" ]; then',
                  '  ALT_DNS_SERVERS=$(/system/bin/sh "$ALTDIR/share/%s/dns-servers" 2>/dev/null | tr \'\\n\' \' \')' % MODID,
                  '  export ALT_DNS_SERVERS',
                  'fi',
                  'exec %s"$@"' % exe]
    elif e['origin'] == 'ndk' and 'dns' in e['flags']:
        lines += ['# DNS query tool: talks to a DNS server directly (not via getaddrinfo). Without @server, use the',
                  '# first DNS server of the active default network; no resolv.conf is read or written.',
                  '# @server goes last: drill stops option parsing at the first operand.',
                  'case " $* " in',
                  '  *" @"*) exec %s"$@" ;;' % exe,
                  'esac',
                  'ALT_NS=$(/system/bin/sh "$ALTDIR/share/%s/dns-servers" 2>/dev/null | head -n 1)' % MODID,
                  'if [ -n "$ALT_NS" ]; then',
                  '  exec %s"$@" "@$ALT_NS"' % exe,
                  'fi',
                  'exec %s"$@"' % exe]
    else:
        lines.append('exec %s"$@"' % exe)
    write(os.path.join(ST, 'system', 'bin', e['name']), '\n'.join(lines) + '\n', 0o755)
    wrappers.append(e['name'])
copyfile(os.path.join(SRC, 'ndk', 'module', 'alt-list'), os.path.join(ST, 'system', 'bin', 'alt-list'), 0o755)
wrappers.append('alt-list')
if need_resolv:
    copyfile(os.path.join(SRC, 'module', 'share', 'resolv-refresh'), os.path.join(SHARE, 'resolv-refresh'), 0o755)
if need_dnsservers:
    copyfile(os.path.join(SRC, 'module', 'share', 'dns-servers'), os.path.join(SHARE, 'dns-servers'), 0o755)
copyfile(os.path.join(SRC, 'phone-test.sh'), os.path.join(SHARE, 'phone-test.sh'), 0o755)
# v2 without Alpine binaries: ndk/module/customize.sh has no musl loader or resolv.conf overlay handling;
# the v1 module/customize.sh is used unchanged while Alpine binaries are shipped
copyfile(os.path.join(SRC, 'module', 'customize.sh') if alpine_targets else
         os.path.join(SRC, 'ndk', 'module', 'customize.sh'), os.path.join(ST, 'customize.sh'), 0o644)
for f in ('update-binary', 'updater-script'):
    copyfile(os.path.join(SRC, 'module', 'META-INF', 'com', 'google', 'android', f),
             os.path.join(ST, 'META-INF', 'com', 'google', 'android', f), 0o644)
write(os.path.join(RT, 'etc', 'alt-tools.map'), ''.join('%s %s -\n' % (w, w) for w in sorted(wrappers)), 0o644)

# ---- per-tool records
def linkage_of(path):
    d = run('readelf', '-d', '-l', '-W', path)
    return 'dynamic' if 'Requesting program interpreter' in d else 'static'


tools_out = []
for e in entries:
    rec = {'tool': e['name'], 'origin': e['origin'], 'libexec': e['target'], 'args': e['args']}
    p = os.path.join(LIBEXEC, e['target'])
    if e['origin'] == 'ndk':
        mt = meta[e['recipe']]
        rec.update(recipe=e['recipe'], version=mt['version'], source_url=mt['url'], source_sha256=mt['sha256'],
                   checksum_source=mt['checksum_source'], license=mt['license'], patches=mt['patches'],
                   deps={d: {'version': meta[d]['version'], 'sha256': meta[d]['sha256'], 'patches': meta[d]['patches']}
                         for d in mt['deps']},
                   linkage=linkage_of(p), dns='dns-servers -> ALT_DNS_SERVERS (+ netd getaddrinfo for @name)'
                   if 'dnsenv' in e['flags'] else 'netd getaddrinfo' if linkage_of(p) == 'dynamic' else
                   ('dns-servers -> @server' if 'dns' in e['flags'] else 'none'))
    else:
        pk = PK[e['package']]
        rec.update(package=e['package'], version=pk['version'], source_sha256=pk['sha256'], license=pk['license'],
                   aports_commit=pk['aports_commit'], patches='alpine aports (see APKBUILD)',
                   linkage='dynamic-musl', dns='resolv-refresh' if 'dns' in e['flags'] else 'none')
    tools_out.append(rec)

origins = ['# tool origin version linkage (written at build time; names before -ng renames)']
for r in tools_out:
    if r['tool']:
        origins.append('%s %s %s %s' % (r['tool'], r['origin'], r['version'], r['linkage'].split()[0]))
write(os.path.join(SHARE, 'origins.txt'), '\n'.join(origins) + '\n', 0o644)

# ---- licences: this repository's own files (MIT) and every bundled upstream package
copyfile(os.path.join(SRC, 'LICENSE'), os.path.join(ST, 'share', 'licenses', MODID, 'LICENSE'), 0o644)
lic_rows = [{'source': 'module', 'name': MODID, 'version': VERSION, 'license': 'MIT', 'url': REPO_URL,
             'license_files': ['share/licenses/%s/LICENSE' % MODID]}]
for rname in sorted({e['recipe'] for e in entries if e['origin'] == 'ndk'} |
                    {d for e in entries if e['origin'] == 'ndk' for d in meta[e['recipe']]['deps']} | {'ncurses', 'cacert'}):
    mt = meta[rname]
    ldir = os.path.join(OUT, 'licenses', rname)
    files = []
    if os.path.isdir(ldir):
        for f in sorted(os.listdir(ldir)):
            copyfile(os.path.join(ldir, f), os.path.join(ST, 'share', 'licenses', 'ndk', rname, f), 0o644)
            files.append('share/licenses/ndk/%s/%s' % (rname, f))
    lic_rows.append({'source': 'ndk', 'name': rname, 'version': mt['version'], 'license': mt['license'],
                     'url': mt['url'], 'sha256': mt['sha256'], 'patches': mt['patches'], 'license_files': files})
used_pk = sorted({v.split(':', 1)[1] for v in origin.values() if v.startswith('alpine:')})
for n in used_pk:
    lsrc = os.path.join(P1.unp, n, 'usr', 'share', 'licenses')
    copied = []
    if os.path.isdir(lsrc):
        for dirpath, dirs, files in os.walk(lsrc):
            dirs.sort()
            for f in sorted(files):
                s = os.path.join(dirpath, f)
                rel = os.path.relpath(s, lsrc)
                if os.path.isfile(s):
                    copyfile(os.path.realpath(s), os.path.join(ST, 'share', 'licenses', 'alpine', rel), 0o644)
                    copied.append('share/licenses/alpine/' + rel)
    lic_rows.append({'source': 'alpine', 'name': n, 'version': PK[n]['version'], 'license': PK[n]['license'],
                     'origin': PK[n]['origin'], 'aports_commit': PK[n]['aports_commit'], 'license_files': copied})
aports_branch = LOCK['alpine_branch'].lstrip('v') + '-stable'
notice = ['Android Linux tools %s (%s flavour) - third-party licences' % (VERSION, FLAVOUR), '',
          'The module\'s own files (wrappers, alt-list, customize.sh, dns-servers, phone-test.sh) and the build',
          'scripts in %s are MIT licensed:' % REPO_URL,
          'share/licenses/%s/LICENSE. Each bundled package below keeps its own upstream licence; the' % MODID,
          'patches in share/licenses/ndk/<package>/ keep the terms of their upstream authors.', '',
          'NDK builds (origin ndk): compiled from the upstream source tarballs below with Android NDK %s for' % NDK_RELEASE,
          'aarch64-linux-android API %d. Patches applied are listed per package and shipped next to its licence' % API,
          'files in share/licenses/ndk/<package>/; recipes are in the android-linux-tools repository, ndk/recipes/.', '']
for r in lic_rows:
    if r['source'] == 'ndk':
        notice.append('%-24s %-16s %-36s %s' % (r['name'], r['version'], r['license'], r['url']))
if used_pk:
    notice += ['', 'Alpine Linux %s aarch64 binaries (origin alpine; unmodified except ELF interpreter and RUNPATH' % LOCK['alpine_branch'],
               'set with patchelf). Complete corresponding source: Alpine aports %s, ' % aports_branch +
               'https://gitlab.alpinelinux.org/alpine/aports/-/tree/%s at the aports commit per package in MANIFEST.json.' % aports_branch, '']
    for r in lic_rows:
        if r['source'] == 'alpine':
            notice.append('%-28s %-22s %s' % (r['name'], r['version'], r['license']))
write(os.path.join(ST, 'share', 'licenses', 'NOTICE.txt'), '\n'.join(notice) + '\n', 0o644)

# ---- module.prop
ndk_n = sum(1 for e in entries if e['name'] and e['origin'] == 'ndk')
alp_n = sum(1 for e in entries if e['name'] and e['origin'] == 'alpine')
main = 'nft, ipset, conntrack, wg/awg (+wg-quick/awg-quick), ip-ng/tc-ng/ss-ng, bridge, ethtool-ng, bpftool, tcpdump, strace, curl, dig, drill, mtr, socat, iperf3, htop, tmux, bash, rsync, sqlite3, jq and more'
fdesc = ('%s flavour: bpftool without LLVM disassembler' % FLAVOUR if not alpine_targets else
         'full flavour: bpftool with libLLVM (JIT disassembly, Alpine)' if FLAVOUR == 'full' and
         origin.get('libexec/bpftool', '').startswith('alpine:') else
         '%s flavour: bpftool without LLVM disassembler' % FLAVOUR)
alp_desc = (', %d from Alpine %s' % (alp_n, LOCK['alpine_branch'])) if alp_n else ''
write(os.path.join(ST, 'module.prop'),
      'id=%s\nname=Android Linux tools\nversion=%s\nversionCode=%d\nauthor=Ivan Angelov\n'
      'description=[%s] %d tools built with the Android NDK (bionic)%s: %s. '
      'Names that exist on the device get an -ng suffix (alt-list).\nflavour=%s\n'
      % (MODID, VERSION, VCODE, fdesc, ndk_n, alp_desc, main, FLAVOUR), 0o644)

manifest = {'module': MODID, 'version': VERSION, 'versionCode': VCODE, 'flavour': FLAVOUR, 'arch': 'aarch64',
            'ndk': NDK_RELEASE, 'api': API, 'alpine_branch': LOCK['alpine_branch'], 'moddir': MODDIR, 'altdir': ALTDIR,
            'tools': tools_out, 'files': dict(sorted(origin.items())), 'licenses': lic_rows,
            'resolv_conf_overlay': need_resolv}
common.dump(manifest, os.path.join(SHARE, 'MANIFEST.json'))
common.dump({'flavour': FLAVOUR, 'version': VERSION, 'versionCode': VCODE, 'stage': ST, 'altdir': ALTDIR, 'tools': tools_out,
             'wrappers': sorted(wrappers), 'origin': origin, 'need_resolv': need_resolv},
            os.path.join('/work/stage', 'stage-%s.json' % FLAVOUR))
print('staged %s %s: %d wrappers (%d ndk, %d alpine), resolv overlay %s' % (
    FLAVOUR, VERSION, len(wrappers), ndk_n, alp_n, need_resolv))
