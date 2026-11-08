import sys, os, hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common
from common import MODID

ROOT = sys.argv[1]
P = common.Paths(ROOT)
LOCK = common.load(P.lock)
flv = []
pk_used = set()
for fl in common.FLAVOURS:
    sj = common.load(os.path.join(P.json, 'stage-%s.json' % fl))
    hc = common.load(os.path.join(P.json, 'host_checks-%s.json' % fl))
    zipn = '%s-%s.zip' % (MODID if fl == 'lite' else MODID + '-full', sj['version'])
    zp = os.path.join(P.dist, zipn)
    data = open(zp, 'rb').read()
    sha = hashlib.sha256(data).hexdigest()
    with open(zp + '.sha256', 'w') as f:
        f.write('%s  %s\n' % (sha, zipn))
    total = 0
    for r, ds, fs in os.walk(sj['stage']):
        for f in fs:
            p = os.path.join(r, f)
            if not os.path.islink(p):
                total += os.path.getsize(p)
    pk_used |= set(sj['packages_used'])
    flv.append({'flavour': fl, 'zip': zipn, 'zip_sha256': sha, 'zip_bytes': len(data), 'unpacked_bytes': total,
                'unpacked_mb': round(total / 1048576, 1), 'tools': [t['tool'] for t in sj['tools']] + ['alt-list'],
                'host_check_errors': len(hc['errors'])})
    version, vcode = sj['version'], sj['versionCode']
pk = LOCK['packages']
man = {'module': MODID, 'version': version, 'versionCode': vcode, 'alpine_branch': LOCK['alpine_branch'],
       'arch': 'aarch64', 'flavours': flv,
       'tools': common.load(os.path.join(P.json, 'stage-full.json'))['tools'],
       'packages_used': {n: {k: pk[n][k] for k in ('version', 'repo', 'sha256', 'license', 'origin', 'aports_commit')}
                         for n in sorted(pk_used)},
       'packages_locked': len(pk),
       'source_offer': 'Sources: Alpine aports branch %s-stable, https://gitlab.alpinelinux.org/alpine/aports/-/tree/%s-stable (per-package aports_commit above)'
                       % (LOCK['alpine_branch'].lstrip('v'), LOCK['alpine_branch'].lstrip('v'))}
common.dump(man, os.path.join(P.dist, 'MANIFEST.json'))
for f in flv:
    print(f['zip'], f['zip_sha256'], f['unpacked_mb'], 'MB')
