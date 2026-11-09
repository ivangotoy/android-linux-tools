# Stage the module for one flavour from the NDK builds in /work/out. Runs inside the builder.
#   python3 -I /src/ndk/scripts/stage.py FLAVOUR
import sys, os, shutil, subprocess, re

sys.path.insert(0, '/src/ndk/scripts')
import common
from common import MODID, MODDIR, ALTDIR

SRC = '/src'
OUT = '/work/out'
FLAVOUR = sys.argv[1]
if FLAVOUR not in common.FLAVOURS:
    raise SystemExit('flavour must be lite or full')
ST = os.path.join('/work/stage', FLAVOUR, MODID)
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

EXTRA_ENV = {
    'mtr': ['export MTR_PACKET="$ALTDIR/libexec/mtr-packet"'],
    'tmux': ['[ -n "$TMUX_TMPDIR" ] || export TMUX_TMPDIR=/data/local/tmp',
             '[ -n "$SHELL" ] || export SHELL=/system/bin/sh'],
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
if FLAVOUR == 'lite':
    # the lite tool list ends with bpftool (lite had no bpftool before v2.1); keeps origins.txt and
    # MANIFEST.json in the order of earlier releases
    entries = [e for e in entries if e['name'] != 'bpftool'] + [e for e in entries if e['name'] == 'bpftool']

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

# ---- wrappers
need_dnsservers = any('dns' in e['flags'] or 'dnsenv' in e['flags'] for e in entries if e['name'])
wrappers = []
for e in entries:
    if e['name'] is None:
        continue
    # every path is under ALTDIR (/system/etc/<MODID>, mounted by the root manager), never /data/adb (root-only)
    lines = ['#!/system/bin/sh', 'ALTDIR=' + ALTDIR, 'export TERMINFO="$ALTDIR/share/terminfo"']
    lines.append('[ -n "$TMPDIR" ] || export TMPDIR=/data/local/tmp')
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
    elif 'dnsenv' in e['flags']:
        lines += ['# BIND dig/host: no resolv.conf on Android. Without @server (dig) or a server argument (host) they use',
                  '# ALT_DNS_SERVERS (patched dighost.c): the DNS servers of the active default network.',
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
write(os.path.join(ST, 'share', 'licenses', 'NOTICE.txt'), '\n'.join(notice) + '\n', 0o644)

# ---- module.prop
ndk_n = sum(1 for e in entries if e['name'])
main = 'nft, ipset, conntrack, wg/awg (+wg-quick/awg-quick), ip-ng/tc-ng/ss-ng, bridge, ethtool-ng, bpftool, bpftrace, tcpdump, strace, curl, dig, drill, mtr, socat, iperf3, htop, tmux, bash, rsync, sqlite3, jq and more'
write(os.path.join(ST, 'module.prop'),
      'id=%s\nname=Android Linux tools\nversion=%s\nversionCode=%d\nauthor=Ivan Angelov\n'
      'description=[%s flavour: bpftool without LLVM disassembler] %d tools built with the Android NDK (bionic): %s. '
      'Names that exist on the device get an -ng suffix (alt-list).\nflavour=%s\n'
      % (MODID, VERSION, VCODE, FLAVOUR, ndk_n, main, FLAVOUR), 0o644)

manifest = {'module': MODID, 'version': VERSION, 'versionCode': VCODE, 'flavour': FLAVOUR, 'arch': 'aarch64',
            'ndk': NDK_RELEASE, 'api': API, 'moddir': MODDIR, 'altdir': ALTDIR,
            'tools': tools_out, 'files': dict(sorted(origin.items())), 'licenses': lic_rows}
common.dump(manifest, os.path.join(SHARE, 'MANIFEST.json'))
common.dump({'flavour': FLAVOUR, 'version': VERSION, 'versionCode': VCODE, 'stage': ST, 'altdir': ALTDIR, 'tools': tools_out,
             'wrappers': sorted(wrappers), 'origin': origin},
            os.path.join('/work/stage', 'stage-%s.json' % FLAVOUR))
print('staged %s %s: %d wrappers (%d ndk)' % (FLAVOUR, VERSION, len(wrappers), ndk_n))
