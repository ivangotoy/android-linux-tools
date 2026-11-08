import sys, os, json, base64, hashlib, zlib, tarfile, io, urllib.request, re, shutil

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common

ROOT = sys.argv[1]
UPDATE = '--update-lock' in sys.argv[2:]
P = common.Paths(ROOT)
CONF = common.read_conf(ROOT)
ROOTS = common.roots(ROOT)
MIRROR = CONF.get('ALPINE_MIRROR', 'https://dl-cdn.alpinelinux.org/alpine').rstrip('/')
REPOS = CONF.get('ALPINE_REPOS', 'main,community').split(',')
ARCH = 'aarch64'
SKIP = {'busybox', 'busybox-binsh', 'alpine-baselayout', 'alpine-baselayout-data', 'apk-tools', 'musl-utils',
        'scanelf', 'ca-certificates', 'openrc', 'ifupdown-ng', 'libc-utils', 'alpine-keys', 'ncurses-terminfo-base-noop'}
UA = {'User-Agent': 'android-linux-tools-build/1'}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def resolve_branch(spec):
    if spec != 'latest-stable':
        if not re.fullmatch(r'v\d+\.\d+', spec):
            raise SystemExit('ALPINE_BRANCH must be latest-stable or vX.Y')
        return spec
    y = get('%s/latest-stable/releases/%s/latest-releases.yaml' % (MIRROR, ARCH)).decode()
    m = re.search(r'^\s*branch:\s*(v\d+\.\d+)\s*$', y, re.M)
    if not m:
        raise SystemExit('cannot parse branch from latest-releases.yaml')
    return m.group(1)


def parse_index(text, repo):
    pk = {}
    rec = {}
    for line in text.split('\n') + ['']:
        if not line:
            if 'P' in rec:
                rec['repo'] = repo
                pk.setdefault(rec['P'], rec)
            rec = {}
            continue
        rec[line[0]] = line[2:]
    return pk


def depname(d):
    return re.split(r'[=<>~]', d, maxsplit=1)[0]


def resolve(branch):
    pkgs = {}
    for repo in REPOS:
        d = os.path.join(P.idx, branch, repo)
        os.makedirs(d, exist_ok=True)
        body = get('%s/%s/%s/%s/APKINDEX.tar.gz' % (MIRROR, branch, repo, ARCH))
        open(os.path.join(d, 'APKINDEX.tar.gz'), 'wb').write(body)
        with tarfile.open(fileobj=io.BytesIO(body), mode='r:gz') as t:
            text = t.extractfile('APKINDEX').read().decode('utf-8')
        for n, r in parse_index(text, repo).items():
            pkgs.setdefault(n, r)
    prov = {}
    for name in sorted(pkgs):
        prov.setdefault(name, name)
    for name in sorted(pkgs):
        for p in pkgs[name].get('p', '').split():
            prov.setdefault(depname(p), name)
    need = {}
    order = list(ROOTS)
    unresolved = []
    while order:
        n = order.pop(0)
        if n in need:
            continue
        if n not in pkgs:
            unresolved.append(n)
            continue
        need[n] = []
        for d in pkgs[n].get('D', '').split():
            if d.startswith('!'):
                continue
            dn = depname(d)
            if dn.startswith('cmd:') or dn.startswith('pc:') or dn == '/bin/sh':
                continue
            if dn not in prov:
                unresolved.append(n + '->' + dn)
                continue
            target = prov[dn]
            if target in SKIP:
                continue
            need[n].append(target)
            order.append(target)
    if unresolved:
        raise SystemExit('UNRESOLVED %r' % unresolved)
    out = {}
    for n in sorted(need):
        r = pkgs[n]
        out[n] = {'version': r['V'], 'repo': r['repo'], 'arch': r.get('A'), 'file': '%s-%s.apk' % (n, r['V']),
                  'size': int(r['S']), 'apkindex_C': r['C'], 'license': r.get('L', ''), 'origin': r.get('o', n),
                  'aports_commit': r.get('c', ''), 'url': r.get('U', ''), 'deps': sorted(set(need[n]))}
    return out


def members(data):
    out = []
    pos = 0
    while pos < len(data):
        d = zlib.decompressobj(31)
        raw = d.decompress(data[pos:])
        consumed = len(data) - pos - len(d.unused_data)
        if not d.eof:
            raise ValueError('truncated gzip member')
        out.append((data[pos:pos + consumed], raw))
        pos += consumed
    return out


def verify(n, r, data, locked_sha):
    fn = r['file']
    if len(data) != r['size']:
        raise SystemExit('size mismatch ' + fn)
    if r.get('arch') not in ('aarch64', 'noarch'):
        raise SystemExit('arch mismatch ' + fn)
    sha = hashlib.sha256(data).hexdigest()
    if locked_sha and sha != locked_sha:
        raise SystemExit('sha256 mismatch vs lockfile ' + fn)
    ms = members(data)
    if len(ms) != 3:
        raise SystemExit('unexpected segment count %d in %s' % (len(ms), fn))
    q1 = 'Q1' + base64.b64encode(hashlib.sha1(ms[1][0]).digest()).decode()
    if q1 != r['apkindex_C']:
        raise SystemExit('control checksum mismatch ' + fn)
    with tarfile.open(fileobj=io.BytesIO(ms[1][1]), mode='r:') as t:
        info = t.extractfile('.PKGINFO').read().decode()
    dh = re.search(r'^datahash = ([0-9a-f]{64})$', info, re.M)
    if not dh or hashlib.sha256(ms[2][0]).hexdigest() != dh.group(1):
        raise SystemExit('datahash mismatch ' + fn)
    return sha, ms[2][1]


def unpack(n, payload):
    dest = os.path.join(P.unp, n)
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    with tarfile.open(fileobj=io.BytesIO(payload), mode='r:') as t:
        for m in t.getmembers():
            if m.issym() and m.linkname.startswith('/'):
                m.linkname = os.path.relpath(m.linkname.lstrip('/'), os.path.dirname(m.name) or '.')
        t.extractall(dest, filter='data')


if os.path.exists(P.lock) and not UPDATE:
    lock = common.load(P.lock)
    if lock['roots'] != ROOTS:
        raise SystemExit('config roots differ from alpine.lock.json; run ./build.sh --update-lock')
    branch = lock['alpine_branch']
    pk = lock['packages']
    mode = 'locked'
else:
    branch = resolve_branch(CONF.get('ALPINE_BRANCH', 'latest-stable'))
    pk = resolve(branch)
    lock = None
    mode = 'resolved'

dl = os.path.join(P.dl, branch)
os.makedirs(dl, exist_ok=True)
for n in sorted(pk):
    r = pk[n]
    path = os.path.join(dl, r['file'])
    locked_sha = r.get('sha256') if lock else None
    if os.path.exists(path):
        data = open(path, 'rb').read()
        if locked_sha and hashlib.sha256(data).hexdigest() != locked_sha:
            os.remove(path)
    if not os.path.exists(path):
        body = get('%s/%s/%s/%s/%s' % (MIRROR, branch, r['repo'], ARCH, r['file']))
        with open(path + '.part', 'wb') as f:
            f.write(body)
        os.rename(path + '.part', path)
    sha, payload = verify(n, r, open(path, 'rb').read(), locked_sha)
    r['sha256'] = sha
    unpack(n, payload)

for stale in sorted(set(os.listdir(P.unp)) - set(pk)):
    shutil.rmtree(os.path.join(P.unp, stale))

if lock is None:
    common.dump({'alpine_branch': branch, 'branch_spec': CONF.get('ALPINE_BRANCH', 'latest-stable'),
                 'mirror': MIRROR, 'arch': ARCH, 'repos': REPOS, 'roots': ROOTS, 'packages': pk}, P.lock)
common.dump({'mode': mode, 'alpine_branch': branch, 'count': len(pk),
             'verification': 'size==S, sha256==lock (locked mode), Q1 sha1(control gz)==APKINDEX C, '
                             'sha256(data gz)==.PKGINFO datahash, tar extract with data filter'},
            os.path.join(P.json, 'fetch.json'))
print('fetch %s branch=%s packages=%d' % (mode, branch, len(pk)))
