# Write dist/MANIFEST-v2.json and the .sha256 file of the module ZIP (inside the builder).
import sys, os, hashlib
sys.path.insert(0, '/src/ndk/scripts')
import common
from common import MODID

sj = common.load(os.path.join(common.STAGE, 'stage.json'))
hc = common.load(os.path.join(common.STAGE, 'host_checks.json'))
zipn = '%s-%s.zip' % (MODID, sj['version'])
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
man = {'module': MODID, 'version': sj['version'], 'versionCode': sj['versionCode'], 'arch': 'aarch64',
       'ndk': os.environ.get('NDK_RELEASE'), 'api': int(os.environ.get('API', '29')),
       'zip': zipn, 'zip_sha256': sha, 'zip_bytes': len(data), 'unpacked_bytes': total,
       'unpacked_mb': round(total / 1048576, 1), 'host_check_errors': len(hc['errors']),
       'host_check_summary': hc['summary'], 'tools': sj['tools']}
common.dump(man, '/work/dist/MANIFEST-v2.json')
print(zipn, sha, man['unpacked_mb'], 'MB')
