import sys, os, json, subprocess, re, shlex

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import MODID, MODDIR, LDSO

ROOT, FLAVOUR = sys.argv[1], sys.argv[2]
P = common.Paths(ROOT)
ST = P.stage(FLAVOUR)
SJ = common.load(os.path.join(P.json, 'stage-%s.json' % FLAVOUR))
INTERP = MODDIR + '/lib/' + LDSO
FORBID = set('iptables ip6tables ip tc ss ethtool nsenter unshare chroot lsof nc file vmstat getfattr setfattr'.split())

res = {'flavour': FLAVOUR, 'errors': [], 'libexec': {}, 'libs': {}, 'wrappers': {}, 'scripts': {}, 'version_audit': {}}
err = res['errors'].append


def sh(*a):
    return subprocess.run(a, capture_output=True, text=True)


def elf_info(p):
    d = sh('readelf', '-d', '-l', '-W', p).stdout
    needed = re.findall(r'\(NEEDED\)\s+Shared library: \[([^\]]+)\]', d)
    rp = re.findall(r'\((?:RUNPATH|RPATH)\)\s+Library (?:runpath|rpath): \[([^\]]+)\]', d)
    it = re.findall(r'Requesting program interpreter: ([^\]]+)\]', d)
    mach = re.search(r'Machine:\s+(.*)', sh('readelf', '-h', p).stdout)
    return needed, rp, it, mach.group(1).strip() if mach else None


def syntax(path):
    out = {}
    for name, cmd in (('sh -n', ['sh', '-n', path]), ('bash --posix -n', ['bash', '--posix', '-n', path])):
        r = sh(*cmd)
        out[name] = r.returncode == 0
        if r.returncode:
            err('syntax (%s) %s: %s' % (name, os.path.relpath(path, ST), r.stderr.strip()))
    return out


libdir = os.path.join(ST, 'lib')
present = set(os.listdir(libdir))
for sub in ('libexec', 'lib'):
    for f in sorted(os.listdir(os.path.join(ST, sub))):
        p = os.path.join(ST, sub, f)
        if os.path.islink(p):
            tgt = os.readlink(p)
            ok = '/' not in tgt and os.path.isfile(os.path.join(libdir, tgt))
            res['libs'][f] = {'symlink': tgt, 'ok': ok}
            if not ok:
                err('bad symlink ' + f)
            continue
        needed, rp, it, mach = elf_info(p)
        miss = [n for n in needed if n not in present]
        entry = {'machine': mach, 'needed': needed, 'missing': miss, 'runpath': rp}
        if mach != 'AArch64':
            err('not aarch64: ' + f)
        if miss:
            err('%s missing %s' % (f, miss))
        if sub == 'libexec':
            fo = sh('file', '-b', p).stdout.strip()
            entry['file'] = fo
            entry['interp'] = it
            if 'ARM aarch64' not in fo or ('interpreter ' + INTERP) not in fo or it != [INTERP]:
                err('libexec interp/arch wrong: ' + f)
            if rp != [MODDIR + '/lib']:
                err('libexec rpath wrong: ' + f)
            if not os.access(p, os.X_OK):
                err('not executable: ' + f)
            res['libexec'][f] = entry
        else:
            if f != LDSO and [n for n in needed if n != 'libc.musl-aarch64.so.1'] and rp != [MODDIR + '/lib']:
                err('lib needs rpath: ' + f)
            res['libs'][f] = entry

has_llvm = any(n.startswith('libLLVM') for n in present)
has_bpftool = os.path.exists(os.path.join(ST, 'libexec', 'bpftool'))
res['bpftool'] = has_bpftool
res['libLLVM'] = has_llvm
if FLAVOUR == 'lite' and (has_llvm or has_bpftool):
    err('lite flavour contains bpftool/libLLVM')
if FLAVOUR == 'full' and not (has_llvm and has_bpftool):
    err('full flavour lacks bpftool/libLLVM')

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
                          'dns_refresh': 'resolv-refresh' in txt}
    if not target_ok or shadow:
        err('wrapper bad: ' + w)
    if not os.access(p, os.X_OK):
        err('wrapper not executable: ' + w)

scripts = ['customize.sh', 'META-INF/com/google/android/update-binary', 'share/%s/resolv-refresh' % MODID,
           'share/%s/phone-test.sh' % MODID]
for s in scripts:
    res['scripts'][s] = syntax(os.path.join(ST, s))
cz = open(os.path.join(ST, 'customize.sh')).read()
for bad in (r'\bksud\b', r'\bmagisk\b\s+--', r'\bapd\b', r'\bbusybox\b'):
    if re.search(bad, cz):
        err('customize.sh uses manager-specific command ' + bad)
pt = open(os.path.join(ST, 'share', MODID, 'phone-test.sh')).read()
if re.search(r'^\s*(function\s+)?hash\s*\(\)', pt, re.M) or re.search(r'^\s*function\s+hash\b', pt, re.M):
    err('phone-test.sh defines a function named hash')

for bad in ('post-fs-data.sh', 'service.sh', 'post-mount.sh', 'boot-completed.sh', 'system.prop', 'sepolicy.rule'):
    if os.path.exists(os.path.join(ST, bad)):
        err('module boot script present: ' + bad)
prop = dict(l.split('=', 1) for l in open(os.path.join(ST, 'module.prop')).read().splitlines() if '=' in l)
for k in ('id', 'name', 'version', 'versionCode', 'author', 'description'):
    if not prop.get(k):
        err('module.prop lacks ' + k)
if prop.get('id') != MODID or not re.fullmatch(r'[a-zA-Z][a-zA-Z0-9._-]+', prop.get('id', '')):
    err('module.prop id invalid')
if not prop.get('versionCode', '').isdigit():
    err('versionCode not numeric')
res['module_prop'] = prop
for t in ('xterm', 'xterm-256color', 'screen', 'tmux', 'linux', 'vt100'):
    if not os.path.isfile(os.path.join(ST, 'share', 'terminfo', t[0], t)):
        err('terminfo missing ' + t)
if os.path.getsize(os.path.join(ST, 'etc', 'ssl', 'cert.pem')) < 100000:
    err('CA bundle too small')


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
        for n in elf_info(q)[0]:
            lp = os.path.realpath(os.path.join(libdir, n))
            if n not in seen and os.path.isfile(lp):
                seen.add(n)
                out.append(lp)
                queue.append(lp)
    return out


RUNTIME = {'getpcaps': 'output is "<pid>: <caps>" built at run time from argv',
           }
LOCKP = common.load(P.lock)['packages']
target_of = {t['tool']: (t['libexec'], t['args'], t['package']) for t in SJ['tools']}
FMT = re.compile(r'%[-+ #0-9.]*(?:l|ll|h|z)?[sdiu]')


def numeric(st, m):
    before = st[m.start() - 1:m.start()]
    after = st[m.end():m.end() + 1]
    return '0' if before in ('v', '.') or after == '.' else 'N'


def renders(strs, cands):
    import itertools
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


for line in pt.splitlines():
    m = re.match(r"\s*vchk\s+(\S+)\s+'([^']*)'", line)
    if not m:
        continue
    tool, pat = m.group(1), m.group(2)
    if tool not in target_of:
        res['version_audit'][tool] = {'pattern': pat, 'status': 'not in flavour'}
        continue
    target, args, pkg = target_of[tool]
    binp = os.path.join(ST, 'libexec', target)
    rx = re.compile(pat, re.I)
    files = closure(binp)
    allstr = [x for f in files for x in strings(f)]
    pver = LOCKP[pkg]['version'].rsplit('-r', 1)[0]
    vers = sorted({x for x in allstr if re.fullmatch(r'\d+(\.\d+)*[a-z]?', x) and pver.startswith(x[:2])})
    cands = [target, pver] + [x for x in vers if x != pver][:4] + [x for x in allstr if pver in x and len(x) < 40][:4]
    entry = {'pattern': pat, 'binary': target}
    own = [x for x in strings(binp) if rx.search(x)]
    rend = [] if own else [x for x in renders(strings(binp), cands) if rx.search(x)]
    libs = [] if own or rend else [x for f in files[1:] for x in strings(f) if rx.search(x)]
    if tool in RUNTIME:
        entry.update(status='runtime', evidence=RUNTIME[tool])
    elif own:
        entry.update(status='ok', evidence='literal in %s: %s' % (target, own[0][:100]))
    elif rend:
        entry.update(status='ok', evidence='printf-rendered from %s: %s' % (target, rend[0][:100]))
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
                  'version_checks_ok': sum(1 for v in res['version_audit'].values() if v['status'] == 'ok')}
common.dump(res, os.path.join(P.json, 'host_checks-%s.json' % FLAVOUR))
print(json.dumps(res['summary'], sort_keys=True))
for e in res['errors']:
    print('ERR', e)
sys.exit(1 if res['errors'] else 0)
