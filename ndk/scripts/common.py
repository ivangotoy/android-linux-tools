# Shared constants and helpers of the ndk/scripts/*.py staging, check and manifest scripts.
import os
import json

MODID = 'android-linux-tools'
MODDIR = '/data/adb/modules/' + MODID
# v2.2+: runtime files (programs, terminfo, CA bundle, helper scripts and data) live in the module's
# system/etc/<MODID>/ tree, which the root manager mounts at /system/etc/<MODID> (readable by every uid);
# /data/adb is root-only (0700)
ALTDIR = '/system/etc/' + MODID
FLAVOURS = ('lite', 'full')


def read_conf(root):
    conf = {}
    with open(os.path.join(root, 'ndk', 'build.conf'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            k, v = line.split('=', 1)
            conf[k.strip()] = v.strip()
    return conf


def dump(obj, path):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=1, sort_keys=True)
        f.write('\n')


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)
