import sys, os, json, shutil, subprocess, re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import MODID, MODDIR, LDSO

ROOT, FLAVOUR = sys.argv[1], sys.argv[2]
if FLAVOUR not in common.FLAVOURS:
    raise SystemExit('flavour must be lite or full')
P = common.Paths(ROOT)
CONF = common.read_conf(ROOT)
LOCK = common.load(P.lock)
BRANCH = LOCK['alpine_branch']
VERSION, VCODE = common.version_of(BRANCH, CONF['MODULE_RELEASE'])
TOOLS = common.tools_for(common.read_tools(ROOT), FLAVOUR)
ST = P.stage(FLAVOUR)
SHARE = os.path.join(ST, 'share', MODID)

EXTRA_ENV = {
    'curl': ['export CURL_CA_BUNDLE="$MODDIR/etc/ssl/cert.pem"'],
    'mtr': ['export MTR_PACKET="$MODDIR/libexec/mtr-packet"'],
    'tmux': ['[ -n "$TMUX_TMPDIR" ] || export TMUX_TMPDIR=/data/local/tmp',
             '[ -n "$SHELL" ] || export SHELL=/system/bin/sh'],
}
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


libindex = {}
for pkg in sorted(os.listdir(P.unp)):
    for d in ('lib', 'usr/lib'):
        base = os.path.join(P.unp, pkg, d)
        if os.path.isdir(base):
            for f in sorted(os.listdir(base)):
                fp = os.path.join(base, f)
                if os.path.isfile(fp) and '.so' in f:
                    libindex.setdefault(f, (pkg, os.path.realpath(fp)))

if os.path.exists(os.path.dirname(ST)):
    shutil.rmtree(os.path.dirname(ST))
for d in ('system/bin', 'libexec', 'lib', 'share/terminfo', 'etc/ssl', 'share/' + MODID, 'share/licenses'):
    os.makedirs(os.path.join(ST, d))

origin = {}
for t in TOOLS:
    if t['src'] is None:
        continue
    dst = os.path.join(ST, 'libexec', t['target'])
    if not os.path.exists(dst):
        copyfile(os.path.realpath(os.path.join(P.unp, t['package'], t['src'])), dst, 0o755)
        origin['libexec/' + t['target']] = t['package']

copyfile(os.path.realpath(os.path.join(P.unp, 'musl', 'lib', LDSO)), os.path.join(ST, 'lib', LDSO), 0o755)
origin['lib/' + LDSO] = 'musl'
os.symlink(LDSO, os.path.join(ST, 'lib', 'libc.musl-aarch64.so.1'))

queue = sorted(os.path.join(ST, 'libexec', t) for t in os.listdir(os.path.join(ST, 'libexec')))
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
        origin['lib/' + n] = libindex[n][0]
        queue.append(dst)
if missing:
    raise SystemExit('missing libs: %r' % missing)

for t in sorted(os.listdir(os.path.join(ST, 'libexec'))):
    p = os.path.join(ST, 'libexec', t)
    run('patchelf', '--set-interpreter', MODDIR + '/lib/' + LDSO, '--set-rpath', MODDIR + '/lib', p)
for l in sorted(os.listdir(os.path.join(ST, 'lib'))):
    p = os.path.join(ST, 'lib', l)
    if os.path.islink(p) or l == LDSO:
        continue
    if [n for n in needed(p) if n != 'libc.musl-aarch64.so.1']:
        run('patchelf', '--set-rpath', MODDIR + '/lib', p)

tsrc = os.path.join(P.unp, 'ncurses-terminfo', 'usr', 'share', 'terminfo')
for t in TERMS:
    cands = [os.path.join(P.unp, 'ncurses-terminfo-base', 'etc', 'terminfo', t[0], t), os.path.join(tsrc, t[0], t)]
    cands = [c for c in cands if os.path.isfile(c)]
    if cands:
        copyfile(os.path.realpath(cands[0]), os.path.join(ST, 'share', 'terminfo', t[0], t), 0o644)
copyfile(os.path.realpath(os.path.join(P.unp, 'ca-certificates-bundle', 'etc', 'ssl', 'cert.pem')),
         os.path.join(ST, 'etc', 'ssl', 'cert.pem'), 0o644)
for p in ('ncurses-terminfo-base', 'ncurses-terminfo', 'ca-certificates-bundle'):
    origin['data:' + p] = p

wrappers = []
for t in TOOLS:
    if t['name'] is None:
        continue
    lines = ['#!/system/bin/sh', 'MODDIR=' + MODDIR, 'export TERMINFO="$MODDIR/share/terminfo"',
             'export SSL_CERT_FILE="$MODDIR/etc/ssl/cert.pem"', '[ -n "$TMPDIR" ] || export TMPDIR=/data/local/tmp']
    lines += EXTRA_ENV.get(t['name'], [])
    if 'dns' in t['flags']:
        lines.append('[ "${USER_ID:-$(id -u)}" = 0 ] && /system/bin/sh "$MODDIR/share/%s/resolv-refresh" >/dev/null 2>&1' % MODID)
    lines.append('exec "$MODDIR/libexec/%s" %s"$@"' % (t['target'], t['args'] + ' ' if t['args'] else ''))
    write(os.path.join(ST, 'system', 'bin', t['name']), '\n'.join(lines) + '\n', 0o755)
    wrappers.append(t['name'])
copyfile(os.path.join(ROOT, 'module', 'share', 'alt-list'), os.path.join(ST, 'system', 'bin', 'alt-list'), 0o755)
wrappers.append('alt-list')
copyfile(os.path.join(ROOT, 'module', 'share', 'resolv-refresh'), os.path.join(SHARE, 'resolv-refresh'), 0o755)
copyfile(os.path.join(ROOT, 'phone-test.sh'), os.path.join(SHARE, 'phone-test.sh'), 0o755)
copyfile(os.path.join(ROOT, 'module', 'customize.sh'), os.path.join(ST, 'customize.sh'), 0o644)
for f in ('update-binary', 'updater-script'):
    copyfile(os.path.join(ROOT, 'module', 'META-INF', 'com', 'google', 'android', f),
             os.path.join(ST, 'META-INF', 'com', 'google', 'android', f), 0o644)
write(os.path.join(ST, 'etc', 'alt-tools.map'), ''.join('%s %s -\n' % (w, w) for w in sorted(wrappers)), 0o644)

main = 'nft, ipset, conntrack, wg, ip-ng/tc-ng/ss-ng, bridge, %stcpdump, strace, curl, dig, mtr, socat, iperf3, htop, tmux, bash, rsync, sqlite3, jq and more' % (
    'bpftool, ' if FLAVOUR == 'full' else '')
fdesc = ('full flavour: includes bpftool + libLLVM' if FLAVOUR == 'full'
         else 'lite flavour: no bpftool/libLLVM, use the -full zip for bpftool')
write(os.path.join(ST, 'module.prop'),
      'id=%s\nname=Android Linux tools\nversion=%s\nversionCode=%d\nauthor=Ivan Angelov\n'
      'description=[%s] Alpine %s aarch64 userspace tools: %s. Names that exist on the device get an -ng suffix (alt-list).\n'
      'flavour=%s\n' % (MODID, VERSION, VCODE, fdesc, BRANCH, main, FLAVOUR), 0o644)

pk = LOCK['packages']
used = sorted(set(origin.values()))
lic_rows = []
for n in used:
    lsrc = os.path.join(P.unp, n, 'usr', 'share', 'licenses')
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
    lic_rows.append({'package': n, 'version': pk[n]['version'], 'license': pk[n]['license'],
                     'origin': pk[n]['origin'], 'aports_commit': pk[n]['aports_commit'], 'license_files': copied})
aports_branch = BRANCH.lstrip('v') + '-stable'
notice = ['Android Linux tools %s (%s flavour) - third-party licences' % (VERSION, FLAVOUR), '',
          'All programs and libraries in libexec/ and lib/ are unmodified Alpine Linux %s aarch64 binaries' % BRANCH,
          '(only the ELF interpreter and RUNPATH were changed with patchelf). Licences per package (SPDX, from APKINDEX):', '']
for r in lic_rows:
    notice.append('%-28s %-22s %s' % (r['package'], r['version'], r['license']))
notice += ['', 'Source code : the complete corresponding source for every package above',
           'is the Alpine aports tree at branch %s, directory main/<origin> or community/<origin>' % aports_branch,
           '(https://gitlab.alpinelinux.org/alpine/aports/-/tree/%s), at the aports commit listed per package' % aports_branch,
           'in share/%s/MANIFEST.json; upstream source tarballs and Alpine patches are referenced by each APKBUILD.' % MODID,
           'Licence texts shipped by the packages themselves are in share/licenses/alpine/.', '']
write(os.path.join(ST, 'share', 'licenses', 'NOTICE.txt'), '\n'.join(notice), 0o644)

pkgs_used = {n: {k: pk[n][k] for k in ('version', 'repo', 'sha256', 'apkindex_C', 'license', 'origin', 'aports_commit')}
             for n in used}
tools_out = [{'tool': t['name'], 'package': t['package'], 'version': pk[t['package']]['version'],
              'libexec': t['target'], 'args': t['args'], 'dns_refresh': 'dns' in t['flags'],
              'license': pk[t['package']]['license']} for t in TOOLS if t['name']]
manifest = {'module': MODID, 'version': VERSION, 'versionCode': VCODE, 'flavour': FLAVOUR, 'alpine_branch': BRANCH,
            'arch': 'aarch64', 'moddir': MODDIR, 'tools': tools_out, 'files': dict(sorted(origin.items())),
            'packages': pkgs_used, 'licenses': lic_rows,
            'build_tools': {'patchelf': run('patchelf', '--version').strip()}}
common.dump(manifest, os.path.join(SHARE, 'MANIFEST.json'))
common.dump({'flavour': FLAVOUR, 'version': VERSION, 'versionCode': VCODE, 'stage': ST, 'tools': tools_out,
             'wrappers': sorted(wrappers), 'origin': origin, 'packages_used': used},
            os.path.join(P.json, 'stage-%s.json' % FLAVOUR))
print('staged %s: %d wrappers, %d files from %d packages' % (FLAVOUR, len(wrappers), len(origin), len(used)))
