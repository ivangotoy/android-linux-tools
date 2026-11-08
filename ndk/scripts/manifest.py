# Write dist/MANIFEST-v2.json and the .sha256 files for both ZIPs (inside the builder).
import sys, os, hashlib
sys.path.insert(0, '/src/ndk/scripts')
import common
from common import MODID

flv = []
for fl in common.FLAVOURS:
    sj = common.load('/work/stage/stage-%s.json' % fl)
    hc = common.load('/work/stage/host_checks-%s.json' % fl)
    zipn = '%s-%s.zip' % (MODID if fl == 'lite' else MODID + '-full', sj['version'])
    zp = os.path.join('/work/dist', zipn)
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
    flv.append({'flavour': fl, 'zip': zipn, 'zip_sha256': sha, 'zip_bytes': len(data), 'unpacked_bytes': total,
                'unpacked_mb': round(total / 1048576, 1), 'tools': [t['tool'] for t in sj['tools'] if t['tool']] + ['alt-list'],
                'host_check_errors': len(hc['errors']), 'host_check_summary': hc['summary']})
    version, vcode = sj['version'], sj['versionCode']
full = common.load('/work/stage/stage-full.json')
man = {'module': MODID, 'version': version, 'versionCode': vcode, 'arch': 'aarch64',
       'ndk': os.environ.get('NDK_RELEASE'), 'api': int(os.environ.get('API', '29')), 'flavours': flv,
       'tools': full['tools']}
common.dump(man, '/work/dist/MANIFEST-v2.json')
for f in flv:
    print(f['zip'], f['zip_sha256'], f['unpacked_mb'], 'MB')
