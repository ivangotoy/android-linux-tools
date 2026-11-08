import os
import re
import json

MODID = 'android-linux-tools'
MODDIR = '/data/adb/modules/' + MODID
# v2.2+: runtime files (programs, terminfo, CA bundle, helper scripts and data) live in the module's
# system/etc/<MODID>/ tree, which the root manager mounts at /system/etc/<MODID> (readable by every uid);
# /data/adb is root-only (0700)
ALTDIR = '/system/etc/' + MODID
LDSO = 'ld-musl-aarch64.so.1'
FLAVOURS = ('lite', 'full')


class Paths:
    def __init__(self, root):
        self.root = os.path.abspath(root)
        self.work = os.path.join(self.root, '.work')
        self.idx = os.path.join(self.work, 'index')
        self.dl = os.path.join(self.work, 'dl')
        self.unp = os.path.join(self.work, 'unpack')
        self.stage_base = os.path.join(self.work, 'stage')
        self.json = os.path.join(self.work, 'json')
        self.dist = os.path.join(self.root, 'dist')
        self.lock = os.path.join(self.root, 'alpine.lock.json')
        for d in (self.work, self.json):
            os.makedirs(d, exist_ok=True)

    def stage(self, flavour):
        return os.path.join(self.stage_base, flavour, MODID)


def read_conf(root):
    conf = {}
    with open(os.path.join(root, 'config', 'build.conf'), encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            k, v = line.split('=', 1)
            conf[k.strip()] = v.strip()
    return conf


def read_tools(root):
    tools = []
    with open(os.path.join(root, 'config', 'tools.tsv'), encoding='utf-8') as f:
        for line in f:
            if not line.strip() or line.lstrip().startswith('#'):
                continue
            name, pkg, src, target, args, flags = line.split()
            tools.append({'name': None if name == '-' else name, 'package': pkg,
                          'src': None if src == '-' else src, 'target': target,
                          'args': '' if args == '-' else args,
                          'flags': [] if flags == '-' else flags.split(',')})
    return tools


def tools_for(tools, flavour):
    return [t for t in tools if flavour == 'full' or 'full' not in t['flags']]


def roots(root):
    conf = read_conf(root)
    r = {t['package'] for t in read_tools(root)}
    r |= {p for p in conf.get('EXTRA_PACKAGES', '').split(',') if p}
    return sorted(r)


def version_of(branch, release):
    m = re.fullmatch(r'v(\d+)\.(\d+)', branch)
    if not m:
        raise SystemExit('unexpected branch name ' + branch)
    release = int(release)
    if not 1 <= release <= 99:
        raise SystemExit('MODULE_RELEASE must be 1..99')
    return '%s-r%d' % (branch, release), int(m.group(1)) * 10000 + int(m.group(2)) * 100 + release


def dump(obj, path):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=1, sort_keys=True)
        f.write('\n')


def load(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)
