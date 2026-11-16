# Stage the module from the NDK builds in /work/out. Runs inside the builder.
#   python3 -I /src/ndk/scripts/stage.py
import sys, os, shutil, subprocess, re

sys.path.insert(0, '/src/ndk/scripts')
import common
from common import MODID, MODDIR, ALTDIR

SRC = '/src'
OUT = '/work/out'
ST = os.path.join(common.STAGE, 'module', MODID)
# runtime tree: module system/etc/<MODID>/ = /system/etc/<MODID> on the device (ALTDIR)
RT = os.path.join(ST, ALTDIR.lstrip('/'))
LIBEXEC = os.path.join(RT, 'libexec')
SHARE = os.path.join(RT, 'share', MODID)
CONF = common.read_conf(SRC)
m = re.fullmatch(r'(\d+)\.(\d+)', CONF['V2_VERSION'])
REL = int(CONF['MODULE_RELEASE'])
if not m or not 1 <= REL <= 99:
    raise SystemExit('bad V2_VERSION/MODULE_RELEASE in ndk/build.conf')
VERSION = 'v%s-r%d' % (CONF['V2_VERSION'], REL)
VCODE = int(m.group(1)) * 100000 + int(m.group(2)) * 1000 + REL
API = int(os.environ.get('API', '29'))
NDK_RELEASE = os.environ.get('NDK_RELEASE', '')
REPO_URL = 'https://git.digtvbg.com/ivangotoy/android-linux-tools'

# Root-only directory of the module under /data/local (root root 0751 in AOSP rootdir/init.rc, so no other uid can
# create, rename or replace entries in it), unlike /data/local/tmp (shell shell 0771). Each level is made with
# mkdir -m 700 (mkdir -p would set the mode on the last level only) and is used only if it is a directory, not a
# symlink, owned by the running uid and writable; the checks are shell tests, no extra process (wrappers run often).
ROOTDIR = '/data/local/' + MODID
ROOTTMP = ROOTDIR + '/tmp'


def rootdir_ok(*dirs):
    """shell condition: every dir exists or is made 0700, and is a real directory of the running uid, writable"""
    made = ' && '.join('{ [ -d %s ] || mkdir -m 700 %s 2>/dev/null; }' % (d, d) for d in dirs)
    checks = ' && '.join('[ ! -L %s ] && [ -O %s ]' % (d, d) for d in dirs)
    return '%s && %s && [ -w %s ]' % (made, checks, dirs[-1])


# TMPDIR in every wrapper: a TMPDIR the caller set is kept, except the module's root-only ROOTTMP when the caller
# cannot write it (a non-root process that inherited it from a root session): that caller gets /data/local/tmp.
# Unset TMPDIR: /data/local/tmp, except for the tools in ROOT_TMPDIR_TOOLS run as root.
TMPDIR_GUARD = ('if [ "$TMPDIR" = %s ] && [ ! -w "$TMPDIR" ]; then export TMPDIR=/data/local/tmp; fi' % ROOTTMP)
TMPDIR_LINES = [TMPDIR_GUARD, '[ -n "$TMPDIR" ] || export TMPDIR=/data/local/tmp']
# Opt-in: with TMPDIR unset, root gets ROOTTMP (only root can write /data/local; if ROOTTMP cannot be made or fails
# the checks, /data/local/tmp as before, silently). Only leaf tools: they create temporary files under $TMPDIR
# (source, pinned tarball) and start no other program that could run as another uid with the inherited TMPDIR.
#   mkfs.erofs  erofs-utils 1.9.4 lib/diskbuf.c:69-79 erofs_tmpfile(): getenv("TMPDIR") + mkstemp (mkfs/main.c:1878);
#               exec/fork only in mount/main.c (mount.erofs, not shipped)
#   iperf3      iperf 3.22 src/iperf_api.c:4973-5011 getenv("TMPDIR") + mkstemp; fork only in daemon(3) for -D
#               (src/iperf_util.c:502-545)
#   eu-readelf  elfutils 0.197 src/readelf.c:928-934 getenv("TMPDIR") + mkstemp; built without debuginfod
ROOT_TMPDIR_TOOLS = {'mkfs.erofs', 'iperf3', 'eu-readelf'}
ROOT_TMPDIR_LINES = [TMPDIR_GUARD,
                     'if [ -z "$TMPDIR" ]; then',
                     '  if [ -w /data/local ] && %s; then' % rootdir_ok(ROOTDIR, ROOTTMP),
                     '    export TMPDIR=%s' % ROOTTMP,
                     '  else',
                     '    export TMPDIR=/data/local/tmp',
                     '  fi',
                     'fi']

EXTRA_ENV = {
    'mtr': ['export MTR_PACKET="$ALTDIR/libexec/mtr-packet"'],
    # history files: upstream's default is /tmp/.nstat.u<uid> (iproute2 7.3.0 misc/nstat.c:656-660) and
    # P_tmpdir/.ifstat.u<uid> (misc/ifstat.c:948-958; "/tmp/" in the NDK stdio.h); Android has no /tmp, so without
    # NSTAT_HISTORY/IFSTAT_HISTORY both stop with "open history file" unless run with -s -n (no history read or
    # written; nstat.c:665-671, ifstat.c:965-971). When unset: root gets the file in the
    # root-only ROOTTMP, never in /data/local/tmp (if ROOTTMP cannot be made or fails the checks, the variable stays
    # unset, as before); other uids get the upstream name under $TMPDIR. ifstat -x/--extended keeps one history
    # file per stats type upstream, which a single IFSTAT_HISTORY would merge: then the variable is not set.
    'nstat': ['if [ -z "$NSTAT_HISTORY" ]; then',
              '  if [ "$(id -u)" = 0 ]; then',
              '    if %s; then export NSTAT_HISTORY=%s/.nstat.u0; fi' % (rootdir_ok(ROOTDIR, ROOTTMP), ROOTTMP),
              '  else',
              '    export NSTAT_HISTORY="$TMPDIR/.nstat.u$(id -u)"',
              '  fi',
              'fi'],
    'ifstat': ['if [ -z "$IFSTAT_HISTORY" ]; then',
               '  alt_x=0',
               '  for alt_a in "$@"; do',
               '    case "$alt_a" in --) break ;; --ex*|-x*|-[!-]*x*) alt_x=1 ;; esac',
               '  done',
               '  if [ "$alt_x" = 1 ]; then',
               '    :',
               '  elif [ "$(id -u)" = 0 ]; then',
               '    if %s; then export IFSTAT_HISTORY=%s/.ifstat.u0; fi' % (rootdir_ok(ROOTDIR, ROOTTMP), ROOTTMP),
               '  else',
               '    export IFSTAT_HISTORY="$TMPDIR/.ifstat.u$(id -u)"',
               '  fi',
               'fi'],
    # socket directory: the caller's TMPDIR (apps such as Termux cannot write /data/local/tmp)
    'tmux': ['if [ "$TMUX_TMPDIR" = %s ] && [ ! -w "$TMUX_TMPDIR" ]; then unset TMUX_TMPDIR; fi' % ROOTTMP,
             '[ -n "$TMUX_TMPDIR" ] || export TMUX_TMPDIR="${TMPDIR:-/data/local/tmp}"',
             '[ -n "$SHELL" ] || export SHELL=/system/bin/sh'],
    # adb keeps its key pair in $HOME/.android; root's home directory on Android is / (read-only). Root gets
    # ROOTDIR (see above). Other uids keep /data/local/tmp. If ROOTDIR cannot be made or fails the checks, root
    # falls back to /data/local/tmp with a warning.
    'adb': ['if [ ! -w "${HOME:-/}" ]; then',
            '  if [ "$(id -u)" != 0 ]; then',
            '    export HOME=/data/local/tmp',
            '  elif %s; then' % rootdir_ok(ROOTDIR),
            '    export HOME=%s' % ROOTDIR,
            '  else',
            '    echo "adb: cannot use /data/local/android-linux-tools for the key pair, using HOME=/data/local/tmp" >&2',
            '    export HOME=/data/local/tmp',
            '  fi',
            'fi'],
}
TERMS = ['xterm', 'xterm-256color', 'xterm-color', 'screen', 'screen-256color', 'tmux', 'tmux-256color',
         'linux', 'vt100', 'vt220', 'dumb', 'ansi', 'rxvt', 'rxvt-unicode', 'rxvt-unicode-256color']


def run(*a):
    return subprocess.run(a, check=True, capture_output=True, text=True).stdout


def write(path, text, mode):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)
    os.chmod(path, mode)


def copyfile(src, dst, mode):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    os.chmod(dst, mode)


# ---- tool table (ndk/tools.tsv, in module order) and the recipe records of ndk/build.sh
meta = {}
for f in sorted(os.listdir(os.path.join(OUT, 'meta'))):
    if f.endswith('.json'):
        meta[f[:-5]] = common.load(os.path.join(OUT, 'meta', f))
entries = []   # {name, recipe, target, args, flags}
missing = []
for line in open(os.path.join(SRC, 'ndk', 'tools.tsv')):
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    name, recipe, binary, args, flags = line.split()
    e = {'name': None if name == '-' else name, 'recipe': recipe, 'target': binary,
         'args': '' if args == '-' else args, 'flags': [] if flags == '-' else flags.split(','), 'origin': 'ndk'}
    if recipe not in meta or not os.path.isfile(os.path.join(OUT, 'bin', binary)):
        missing.append(name if name != '-' else binary)
    entries.append(e)
if missing:
    raise SystemExit('no NDK build for: %s' % ' '.join(missing))

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
    copyfile(os.path.join(OUT, 'bin', e['target']), dst, 0o755)
    origin['libexec/' + e['target']] = 'ndk:' + e['recipe']

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
# default config of the openssl CLI (OPENSSLDIR/openssl.cnf; OPENSSLDIR = $ALTDIR/etc/ssl)
copyfile(os.path.join(SRC, 'ndk', 'module', 'openssl.cnf'), os.path.join(RT, 'etc', 'ssl', 'openssl.cnf'), 0o644)
origin['data:etc/ssl/openssl.cnf'] = 'module'
# runtime data a recipe installs for its programs: /work/out/data/rt/<recipe>/<path under ALTDIR>
# (e.g. nmap's share/nmap, ltrace's share/ltrace), merged into the runtime tree
RTDATA = os.path.join(OUT, 'data', 'rt')
for rname in sorted(os.listdir(RTDATA)) if os.path.isdir(RTDATA) else []:
    if rname not in {e['recipe'] for e in entries}:
        continue
    top = os.path.join(RTDATA, rname)
    for dirpath, dirs, files in os.walk(top):
        dirs.sort()
        for f in sorted(files):
            sp = os.path.join(dirpath, f)
            rel = os.path.relpath(sp, top)
            if os.path.islink(sp) or not os.path.isfile(sp):
                raise SystemExit('runtime data of %s is not a regular file: %s' % (rname, rel))
            dp = os.path.join(RT, rel)
            if os.path.exists(dp):
                raise SystemExit('runtime data of %s overwrites %s' % (rname, rel))
            copyfile(sp, dp, 0o644)
    for d in sorted(os.listdir(top)):
        for sd in sorted(os.listdir(os.path.join(top, d))):
            origin['data:%s/%s' % (d, sd)] = 'ndk:' + rname

# ---- wrappers
need_dnsservers = any('dns' in e['flags'] or 'dnsenv' in e['flags'] for e in entries if e['name'])
wrappers = []
for e in entries:
    if e['name'] is None:
        continue
    # every path is under ALTDIR (/system/etc/<MODID>, mounted by the root manager), never /data/adb (root-only)
    lines = ['#!/system/bin/sh', 'ALTDIR=' + ALTDIR, 'export TERMINFO="$ALTDIR/share/terminfo"']
    lines += ROOT_TMPDIR_LINES if e['name'] in ROOT_TMPDIR_TOOLS else TMPDIR_LINES
    lines += EXTRA_ENV.get(e['name'], [])
    exe = '"$ALTDIR/libexec/%s" %s' % (e['target'], e['args'] + ' ' if e['args'] else '')
    if e['name'] == 'curl':
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
    elif e['name'] == 'dropbear':
        lines += ['# dropbear is never started by the module. As root without -r: host keys in /data/local/dropbear,',
                  '# generated on the first connection (-R); authorized_keys: /data/local/dropbear/authorized_keys',
                  'if [ "$(id -u)" = 0 ]; then',
                  '  case " $* " in',
                  '    *" -r"*) ;;',
                  '    *) mkdir -p -m 700 /data/local/dropbear',
                  '       exec %s-R "$@" ;;' % exe,
                  '  esac',
                  'fi',
                  'exec %s"$@"' % exe]
    elif 'dnsenv' in e['flags']:
        lines += ['# no resolv.conf on Android. Without @server (dig) or a server argument (host), BIND\'s dig/host use',
                  '# ALT_DNS_SERVERS (patched dighost.c), and nmap\'s reverse DNS uses it (patched mass_dns): the DNS',
                  '# servers of the active default network.',
                  'if [ -z "$ALT_DNS_SERVERS" ]; then',
                  '  ALT_DNS_SERVERS=$(/system/bin/sh "$ALTDIR/share/%s/dns-servers" 2>/dev/null | tr \'\\n\' \' \')' % MODID,
                  '  export ALT_DNS_SERVERS',
                  'fi',
                  'exec %s"$@"' % exe]
    elif 'dns' in e['flags']:
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
MOD = os.path.join(SRC, 'ndk', 'module')
copyfile(os.path.join(MOD, 'alt-list'), os.path.join(ST, 'system', 'bin', 'alt-list'), 0o755)
wrappers.append('alt-list')
if need_dnsservers:
    copyfile(os.path.join(MOD, 'dns-servers'), os.path.join(SHARE, 'dns-servers'), 0o755)
copyfile(os.path.join(SRC, 'phone-test.sh'), os.path.join(SHARE, 'phone-test.sh'), 0o755)
copyfile(os.path.join(MOD, 'customize.sh'), os.path.join(ST, 'customize.sh'), 0o644)
# run by the root manager on module removal only: removes the root-only /data/local/android-linux-tools
copyfile(os.path.join(MOD, 'uninstall.sh'), os.path.join(ST, 'uninstall.sh'), 0o644)
for f in ('update-binary', 'updater-script'):
    copyfile(os.path.join(MOD, 'META-INF', 'com', 'google', 'android', f),
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
    mt = meta[e['recipe']]
    rec.update(recipe=e['recipe'], version=mt['version'], source_url=mt['url'], source_sha256=mt['sha256'],
               checksum_source=mt['checksum_source'], license=mt['license'], patches=mt['patches'],
               deps={d: {'version': meta[d]['version'], 'sha256': meta[d]['sha256'], 'patches': meta[d]['patches']}
                     for d in mt['deps']},
               linkage=linkage_of(p), dns='dns-servers -> ALT_DNS_SERVERS (+ netd getaddrinfo for @name)'
               if 'dnsenv' in e['flags'] else 'netd getaddrinfo' if linkage_of(p) == 'dynamic' else
               ('dns-servers -> @server' if 'dns' in e['flags'] else 'none'))
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
for rname in sorted({e['recipe'] for e in entries} | {d for e in entries for d in meta[e['recipe']]['deps']} |
                    {'ncurses', 'cacert'}):
    mt = meta[rname]
    ldir = os.path.join(OUT, 'licenses', rname)
    files = []
    if os.path.isdir(ldir):
        for f in sorted(os.listdir(ldir)):
            copyfile(os.path.join(ldir, f), os.path.join(ST, 'share', 'licenses', 'ndk', rname, f), 0o644)
            files.append('share/licenses/ndk/%s/%s' % (rname, f))
    lic_rows.append({'source': 'ndk', 'name': rname, 'version': mt['version'], 'license': mt['license'],
                     'url': mt['url'], 'sha256': mt['sha256'], 'patches': mt['patches'], 'license_files': files})
# bionic (the NDK's libc.a/libm.a/libdl.a and start files) is linked into every program and its sysroot headers
# are compiled in: the notices of the NDK sysroot, with the NDK archive the builder image verified (ndk/Dockerfile)
ndk_sha = re.search(r'^ARG NDK_SHA256=([0-9a-f]{64})$', open(os.path.join(SRC, 'ndk', 'Dockerfile')).read(), re.M)
if not NDK_RELEASE or not ndk_sha:
    raise SystemExit('NDK_RELEASE (builder image) or ARG NDK_SHA256 (ndk/Dockerfile) not set')
copyfile(os.path.join(os.environ['SYSROOT'], 'NOTICE'),
         os.path.join(ST, 'share', 'licenses', 'ndk', 'android-ndk-sysroot', 'NOTICE'), 0o644)
lic_rows.append({'source': 'ndk', 'name': 'android-ndk-sysroot', 'version': NDK_RELEASE,
                 'license': 'LicenseRef-NDK-sysroot-NOTICE',
                 'url': 'https://dl.google.com/android/repository/android-ndk-%s-linux.zip' % NDK_RELEASE,
                 'sha256': ndk_sha.group(1), 'patches': [],
                 'license_files': ['share/licenses/ndk/android-ndk-sysroot/NOTICE']})
notice = ['Android Linux tools %s - third-party licences' % VERSION, '',
          'The module\'s own files (wrappers, alt-list, customize.sh, uninstall.sh, dns-servers, openssl.cnf, phone-test.sh) and the build',
          'scripts in %s are MIT licensed:' % REPO_URL,
          'share/licenses/%s/LICENSE. Each bundled package below keeps its own upstream licence; the' % MODID,
          'patches in share/licenses/ndk/<package>/ keep the terms of their upstream authors.', '',
          'NDK builds (origin ndk): compiled from the upstream source tarballs below with Android NDK %s for' % NDK_RELEASE,
          'aarch64-linux-android API %d. Patches applied are listed per package and shipped next to its licence' % API,
          'files in share/licenses/ndk/<package>/; recipes are in the android-linux-tools repository, ndk/recipes/.', '']
for r in lic_rows:
    if r['source'] == 'ndk':
        notice.append('%-24s %-16s %-36s %s' % (r['name'], r['version'], r['license'], r['url']))
write(os.path.join(ST, 'share', 'licenses', 'NOTICE.txt'), '\n'.join(notice) + '\n', 0o644)

# ---- module.prop
ndk_n = sum(1 for e in entries if e['name'])
main = 'nft, ipset, conntrack, wg/awg (+wg-quick/awg-quick), ip-ng/tc-ng/ss-ng, bridge, ethtool-ng, iw, bpftool, bpftrace, bcc libbpf-tools (execsnoop, opensnoop, ...), ecapture, tcpdump, strace, ltrace, fatrace, gdbserver, lldb-server, rizin, eu-stack, objdump/readelf, patchelf, dtc, mkfs.erofs, mksquashfs, adb, fastboot, lpunpack, git, rg, fd, fzf, ncdu, picocom, mount.nfs, nmap, curl, openssl, dropbear/ssh, dig, drill, mtr, socat, iperf3, fio, htop, tmux, bash, rsync, sqlite3, jq and more'
write(os.path.join(ST, 'module.prop'),
      'id=%s\nname=Android Linux tools\nversion=%s\nversionCode=%d\nauthor=Ivan Angelov\n'
      'description=%d tools built with the Android NDK (bionic): %s. '
      'Names that exist on the device get an -ng suffix (alt-list).\n'
      % (MODID, VERSION, VCODE, ndk_n, main), 0o644)

manifest = {'module': MODID, 'version': VERSION, 'versionCode': VCODE, 'arch': 'aarch64',
            'ndk': NDK_RELEASE, 'api': API, 'moddir': MODDIR, 'altdir': ALTDIR,
            'tools': tools_out, 'files': dict(sorted(origin.items())), 'licenses': lic_rows}
common.dump(manifest, os.path.join(SHARE, 'MANIFEST.json'))
common.dump({'version': VERSION, 'versionCode': VCODE, 'stage': ST, 'altdir': ALTDIR, 'tools': tools_out,
             'wrappers': sorted(wrappers), 'origin': origin},
            os.path.join(common.STAGE, 'stage.json'))
print('staged %s: %d wrappers (%d ndk)' % (VERSION, len(wrappers), ndk_n))
