# Host-side install/layout simulation for one v2 module ZIP (no aarch64 code is executed).
#   python3 -I ndk/scripts/layout_test.py MODULE.zip WORKDIR
# Unzips the module into WORKDIR/data/adb/modules/<MODID>, runs its customize.sh with set_perm/set_perm_recursive
# stubs that behave like Magisk/KernelSU/APatch util_functions (chmod; owner and SELinux context recorded),
# then checks the device view a non-root user (uid 2000, not owner, not group root) gets after the root manager
# mounts the module's system/ tree over /system:
#   - no wrapper or runtime script refers to /data/adb (0700 root) or $MODDIR;
#   - every $ALTDIR path a wrapper uses exists in the module's system/ tree and is readable (programs:
#     executable) by "other", including every directory on the way;
#   - every ELF is in system/etc/<MODID>/libexec and contains no /data/adb path;
#   - every file and directory under system/ is root:root with u:object_r:system_file:s0, dirs/programs/scripts
#     0755, data 0644.
# WORKDIR must be a new or empty directory (never /tmp); it is left in place for inspection.
import sys, os, re, stat, subprocess, json

MODID = 'android-linux-tools'
ALTDIR = '/system/etc/' + MODID
CTX = 'u:object_r:system_file:s0'
SCRIPTS = {'dns-servers', 'resolv-refresh', 'phone-test.sh'}

if len(sys.argv) != 3:
    raise SystemExit('usage: layout_test.py MODULE.zip WORKDIR')
zipf, work = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
if work == '/tmp' or work.startswith('/tmp/'):
    raise SystemExit('WORKDIR must not be under /tmp')
if os.path.exists(work) and os.listdir(work):
    raise SystemExit('WORKDIR %s is not empty' % work)
mod = os.path.join(work, 'data', 'adb', 'modules', MODID)
os.makedirs(mod)
os.chmod(os.path.join(work, 'data', 'adb'), 0o700)
errors = []
err = errors.append

subprocess.run(['unzip', '-q', zipf, '-d', mod], check=True)
permlog = os.path.join(work, 'set_perm.log')
stubs = os.path.join(work, 'stubs.sh')
with open(stubs, 'w') as f:
    f.write('''ui_print() { echo "$1"; }
set_perm() {
  [ -L "$1" ] || chmod "$4" "$1" || return 1
  echo "$1|$2|$3|$4|${5:-u:object_r:system_file:s0}" >> "$ALT_PERMLOG"
}
set_perm_recursive() {
  find "$1" -type d 2>/dev/null | while read -r d; do set_perm "$d" "$2" "$3" "$4" "$6"; done
  find "$1" \\( -type f -o -type l \\) 2>/dev/null | while read -r f; do set_perm "$f" "$2" "$3" "$5" "$6"; done
}
''')
r = subprocess.run(['sh', '-c', '. "$1"; MODPATH="$2"; . "$2/customize.sh"', 'sh', stubs, mod],
                   env={'PATH': os.environ.get('PATH', '/usr/bin:/bin'), 'ALT_PERMLOG': permlog},
                   capture_output=True, text=True)
if r.returncode:
    err('customize.sh exit %d: %s' % (r.returncode, (r.stdout + r.stderr).strip()[-400:]))
perms = {}
for line in open(permlog) if os.path.exists(permlog) else []:
    p, o, g, m, c = line.rstrip('\n').split('|')
    perms[os.path.normpath(p)] = (o, g, m, c)

sysdir = os.path.join(mod, 'system')
rt = os.path.join(mod, ALTDIR.lstrip('/'))
libexec = os.path.join(rt, 'libexec')


def dev(path):
    """device path -> file in the simulated module tree (only /system/... is provided by the module)"""
    return os.path.join(mod, path.lstrip('/')) if path.startswith('/system/') else None


def other_can(path, bits):
    st = os.stat(path)
    return (st.st_mode & bits) == bits


def reachable(path):
    # every directory from system/ down to the file must be searchable by other
    d = os.path.dirname(path)
    while len(d) >= len(sysdir):
        if not other_can(d, stat.S_IXOTH):
            return 'directory %s not searchable by other' % os.path.relpath(d, mod)
        d = os.path.dirname(d)
    return None


def is_elf(p):
    with open(p, 'rb') as f:
        return f.read(4) == b'\x7fELF'


# ---- wrappers
binp = os.path.join(sysdir, 'bin')
wrappers = sorted(os.listdir(binp)) if os.path.isdir(binp) else []
if not wrappers:
    err('no wrappers in system/bin')
refs = {}
for w in wrappers:
    p = os.path.join(binp, w)
    txt = open(p, encoding='utf-8', errors='replace').read()
    if '/data/adb' in txt or 'MODDIR' in txt:
        err('wrapper %s refers to /data/adb or $MODDIR' % w)
    m = re.search(r'^ALTDIR=(\S+)$', txt, re.M)
    if not m or m.group(1) != ALTDIR:
        err('wrapper %s: ALTDIR is not %s' % (w, ALTDIR))
        continue
    if not other_can(p, stat.S_IROTH | stat.S_IXOTH):
        err('wrapper %s not readable/executable by other' % w)
    exp = txt.replace('${ALTDIR}', ALTDIR).replace('$ALTDIR', ALTDIR)
    paths = sorted(set(re.findall(r'(?<![\w$])(/(?:system|data|apex|vendor|product|odm|sdcard|storage)/[\w.+@-]+(?:/[\w.+@-]+)*)', exp)))
    refs[w] = paths
    tgt = re.search(r'exec "' + re.escape(ALTDIR) + r'/libexec/([^"]+)"', exp)
    if w != 'alt-list' and not tgt:
        err('wrapper %s does not exec a program in %s/libexec' % (w, ALTDIR))
    for q in paths:
        if q.startswith('/data/adb'):
            err('wrapper %s uses %s (root-only)' % (w, q))
        if not q.startswith(ALTDIR + '/'):
            continue
        f = dev(q)
        if not os.path.lexists(f):
            err('wrapper %s uses %s, missing from the module system/ tree' % (w, q))
            continue
        why = reachable(f)
        if why:
            err('wrapper %s: %s: %s' % (w, q, why))
        need = stat.S_IROTH | (stat.S_IXOTH if os.path.isdir(f) or '/libexec/' in q or q.endswith(tuple(SCRIPTS)) else 0)
        if not other_can(f, need):
            err('wrapper %s: %s mode %o lacks other %s' % (w, q, stat.S_IMODE(os.stat(f).st_mode), 'r-x' if need & 1 else 'r'))

# ---- runtime scripts and data
for s in sorted(SCRIPTS):
    f = os.path.join(rt, 'share', MODID, s)
    if os.path.exists(f) and s != 'resolv-refresh' and s != 'phone-test.sh' and '/data/adb' in open(f).read():
        err('%s refers to /data/adb' % os.path.relpath(f, mod))
mapf = os.path.join(rt, 'etc', 'alt-tools.map')
if not os.path.isfile(mapf) or not other_can(mapf, stat.S_IROTH):
    err('alt-tools.map missing or not readable by other')
else:
    names = sorted(l.split()[1] for l in open(mapf) if l.strip())
    if names != wrappers:
        err('alt-tools.map does not list exactly the wrappers in system/bin')

# ---- ELFs, owners, labels, modes
elfs = []
for dirpath, dirs, files in os.walk(mod):
    dirs.sort()
    for name in [None] + sorted(files):
        p = dirpath if name is None else os.path.join(dirpath, name)
        rel = os.path.relpath(p, mod)
        if name is not None and not os.path.islink(p) and is_elf(p):
            elfs.append(rel)
            if os.path.dirname(p) != libexec:
                err('ELF outside %s/libexec: %s' % (ALTDIR, rel))
            if b'/data/adb' in open(p, 'rb').read():
                err('ELF %s contains a /data/adb path' % rel)
        if not (p == sysdir or p.startswith(sysdir + '/')):
            continue
        if os.path.islink(p):
            continue
        rec = perms.get(os.path.normpath(p))
        if not rec:
            err('no set_perm for %s' % rel)
            continue
        o, g, m, c = rec
        if (o, g) != ('0', '0'):
            err('%s owner %s:%s, not root:root' % (rel, o, g))
        if c != CTX:
            err('%s context %s, not %s' % (rel, c, CTX))
        want = '0755' if (os.path.isdir(p) or p.startswith(binp + '/') or os.path.dirname(p) == libexec
                          or os.path.basename(p) in SCRIPTS) else '0644'
        if m != want or '%04o' % stat.S_IMODE(os.stat(p).st_mode) != want:
            err('%s mode %s (set_perm %s), want %s' % (rel, '%04o' % stat.S_IMODE(os.stat(p).st_mode), m, want))
if not elfs:
    err('no ELF programs found')

res = {'zip': os.path.basename(zipf), 'wrappers': len(wrappers), 'elfs': len(elfs), 'altdir': ALTDIR,
       'paths_outside_altdir': sorted({q for v in refs.values() for q in v if not q.startswith(ALTDIR + '/')}),
       'errors': len(errors)}
print(json.dumps(res, sort_keys=True))
for e in errors[:200]:
    print('ERR', e)
sys.exit(1 if errors else 0)
