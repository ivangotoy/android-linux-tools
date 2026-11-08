# Host checks for one staged v2 flavour (no aarch64 code is executed). Runs inside the builder.
#   python3 -I /src/ndk/scripts/check.py FLAVOUR
import sys, os, subprocess, re, itertools

sys.path.insert(0, '/src/scripts')
import common
from common import MODID, MODDIR, LDSO

FLAVOUR = sys.argv[1]
SJ = common.load('/work/stage/stage-%s.json' % FLAVOUR)
ST = SJ['stage']
MUSL_INTERP = MODDIR + '/lib/' + LDSO
BIONIC_INTERP = '/system/bin/linker64'
BIONIC_LIBS = {'libc.so', 'libm.so', 'libdl.so', 'liblog.so', 'libz.so'}
FORBID = set('iptables ip6tables ip tc ss ethtool nsenter unshare chroot lsof nc file vmstat getfattr setfattr'.split())
HOSTPATHS = [b'/home/ivan', b'/work/build', b'/work/out', b'/opt/ndk', b'/.work/']
API = int(os.environ.get('API', '29'))

res = {'flavour': FLAVOUR, 'errors': [], 'libexec': {}, 'libs': {}, 'wrappers': {}, 'scripts': {}, 'version_audit': {}}
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
libdir = os.path.join(ST, 'lib')
present = set(os.listdir(libdir)) if os.path.isdir(libdir) else set()
for f in sorted(os.listdir(os.path.join(ST, 'libexec'))):
    p = os.path.join(ST, 'libexec', f)
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
    elif o.startswith('alpine:'):
        entry['linkage'] = 'musl'
        miss = [n for n in e['needed'] if n not in present]
        if miss:
            err('%s missing %s' % (f, miss))
        if e['interp'] != [MUSL_INTERP] or ('interpreter ' + MUSL_INTERP) not in fo:
            err('alpine interp wrong: ' + f)
        if e['runpath'] != [MODDIR + '/lib']:
            err('alpine rpath wrong: ' + f)
    else:
        err('unknown origin for libexec/' + f)
    res['libexec'][f] = entry

for f in sorted(present):
    p = os.path.join(libdir, f)
    if os.path.islink(p):
        tgt = os.readlink(p)
        ok = '/' not in tgt and os.path.isfile(os.path.join(libdir, tgt))
        res['libs'][f] = {'symlink': tgt, 'ok': ok}
        if not ok:
            err('bad symlink ' + f)
        continue
    e = elf(p)
    miss = [n for n in e['needed'] if n not in present]
    if e['machine'] != 'AArch64':
        err('lib not aarch64: ' + f)
    if miss:
        err('lib %s missing %s' % (f, miss))
    if f != LDSO and [n for n in e['needed'] if n != 'libc.musl-aarch64.so.1'] and e['runpath'] != [MODDIR + '/lib']:
        err('lib needs rpath: ' + f)
    res['libs'][f] = e

has_bpftool = os.path.exists(os.path.join(ST, 'libexec', 'bpftool'))
has_llvm = any(n.startswith('libLLVM') for n in present)
bpf_origin = origin.get('libexec/bpftool', '')
res['bpftool'] = {'present': has_bpftool, 'origin': bpf_origin, 'libLLVM': has_llvm}
if FLAVOUR == 'lite' and (has_llvm or (has_bpftool and bpf_origin.startswith('alpine:'))):
    err('lite flavour contains Alpine bpftool/libLLVM')
if FLAVOUR == 'full' and not has_bpftool:
    err('full flavour lacks bpftool')

for w in sorted(os.listdir(os.path.join(ST, 'system', 'bin'))):
    p = os.path.join(ST, 'system', 'bin', w)
    txt = open(p).read()
    syn = syntax(p)
    if w == 'alt-list':
        target_ok = True
    else:
        m = re.search(r'exec "\$MODDIR/libexec/([^"]+)"', txt)
        target_ok = bool(m) and os.path.isfile(os.path.join(ST, 'libexec', m.group(1)))
        if ('MODDIR=' + MODDIR + '\n') not in txt:
            err('wrapper MODDIR wrong: ' + w)
    shadow = w in FORBID
    res['wrappers'][w] = {'syntax': syn, 'target_ok': target_ok, 'static_forbidden_name': shadow,
                          'resolv_refresh': 'resolv-refresh' in txt}
    if not target_ok or shadow:
        err('wrapper bad: ' + w)
    if not os.access(p, os.X_OK):
        err('wrapper not executable: ' + w)
    if 'resolv-refresh' in txt:
        t = re.search(r'exec "\$MODDIR/libexec/([^"]+)"', txt).group(1)
        if not origin.get('libexec/' + t, '').startswith('alpine:'):
            err('resolv-refresh used by NDK tool wrapper ' + w)

scripts = ['customize.sh', 'META-INF/com/google/android/update-binary', 'share/%s/phone-test.sh' % MODID]
for s in ('resolv-refresh', 'dns-servers'):
    if os.path.exists(os.path.join(ST, 'share', MODID, s)):
        scripts.append('share/%s/%s' % (MODID, s))
for s in scripts:
    res['scripts'][s] = syntax(os.path.join(ST, s))
if SJ['need_resolv'] != os.path.exists(os.path.join(ST, 'share', MODID, 'resolv-refresh')):
    err('resolv-refresh presence does not match need_resolv')
cz = open(os.path.join(ST, 'customize.sh')).read()
for bad in (r'\bksud\b', r'\bmagisk\b\s+--', r'\bapd\b', r'\bbusybox\b'):
    if re.search(bad, cz):
        err('customize.sh uses manager-specific command ' + bad)
pt = open(os.path.join(ST, 'share', MODID, 'phone-test.sh')).read()
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
    if not os.path.isfile(os.path.join(ST, 'share', 'terminfo', t[0], t)):
        err('terminfo missing ' + t)
if os.path.getsize(os.path.join(ST, 'etc', 'ssl', 'cert.pem')) < 100000:
    err('CA bundle too small')


# ---- version banner audit (patterns of phone-test.sh vchk lines against ELF strings), as in v1
def strings(p, cache={}):
    if p not in cache:
        data = open(p, 'rb').read()
        cache[p] = [m.decode('latin-1') for m in re.findall(rb'[\x20-\x7e\t]{3,}', data)]
    return cache[p]


def closure(p):
    out = [p]
    seen = set()
    queue = [p]
    while queue:
        q = queue.pop(0)
        for n in elf(q)['needed']:
            lp = os.path.realpath(os.path.join(libdir, n))
            if n not in seen and os.path.isfile(lp):
                seen.add(n)
                out.append(lp)
                queue.append(lp)
    return out


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
for line in pt.splitlines():
    m = re.match(r"\s*vchk\s+(\S+)\s+'([^']*)'", line)
    if not m:
        continue
    tool, pat = m.group(1), m.group(2)
    if tool not in target_of:
        res['version_audit'][tool] = {'pattern': pat, 'status': 'not in flavour'}
        continue
    t = target_of[tool]
    binp = os.path.join(ST, 'libexec', t['libexec'])
    rx = re.compile(pat, re.I)
    files = closure(binp)
    allstr = [x for f in files for x in strings(f)]
    pver = re.sub(r'-r\d+$', '', t['version'])
    vers = sorted({x for x in allstr if re.fullmatch(r'\d+(\.\d+)*[a-z]?', x) and pver.startswith(x[:2])})
    cands = [t['libexec'], t.get('recipe') or t.get('package'), pver] + [x for x in vers if x != pver][:4] + [x for x in allstr if pver in x and len(x) < 40][:4]
    entry = {'pattern': pat, 'binary': t['libexec'], 'origin': t['origin']}
    own = [x for x in strings(binp) if rx.search(x)]
    rend = [] if own else [x for x in renders(strings(binp), cands) if rx.search(x)]
    libs = [] if own or rend else [x for f in files[1:] for x in strings(f) if rx.search(x)]
    if tool in RUNTIME:
        entry.update(status='runtime', evidence=RUNTIME[tool])
    elif own:
        entry.update(status='ok', evidence='literal in %s: %s' % (t['libexec'], own[0][:100]))
    elif rend:
        entry.update(status='ok', evidence='printf-rendered from %s: %s' % (t['libexec'], rend[0][:100]))
    elif libs:
        entry.update(status='ok', evidence='literal in linked library: ' + libs[0][:100])
    else:
        entry.update(status='NO MATCH', evidence=None)
        err('version pattern %r for %s not found in ELF strings' % (pat, tool))
    res['version_audit'][tool] = entry
for t in target_of:
    if t not in res['version_audit']:
        err('no version check in phone-test.sh for ' + t)

res['summary'] = {'flavour': FLAVOUR, 'libexec_elfs': len(res['libexec']), 'libs': len(res['libs']),
                  'wrappers': len(res['wrappers']), 'errors': len(res['errors']),
                  'ndk_static': sum(1 for v in res['libexec'].values() if v.get('linkage') == 'static'),
                  'ndk_dynamic': sum(1 for v in res['libexec'].values() if v.get('linkage') == 'dynamic'),
                  'alpine_musl': sum(1 for v in res['libexec'].values() if v.get('linkage') == 'musl'),
                  'version_checks_ok': sum(1 for v in res['version_audit'].values() if v['status'] == 'ok')}
common.dump(res, '/work/stage/host_checks-%s.json' % FLAVOUR)
print(__import__('json').dumps(res['summary'], sort_keys=True))
for e in res['errors']:
    print('ERR', e)
sys.exit(1 if res['errors'] else 0)
