# ndk/package.sh (real script, in bwrap) with stub stage/check/layout/manifest scripts: the checks it runs on
# the module must fail the build when the module contains a build-host path or unwanted entries.
. "$ALT_TESTS/lib.sh"

# run_case NAME: stage a module as the stub stage.py does for ALT_CASE=NAME, run package.sh; prints rc and stderr
run_case() {
  local h; h=$(alt_scratch)
  mkdir -p "$h/src/ndk/lib" "$h/src/ndk/scripts" "$h/work/build/logs" "$h/work/build/tmp" "$h/work/stage" "$h/work/dist"
  cp "$ALT_TREE/ndk/package.sh" "$h/src/ndk/"
  cp "$ALT_TREE/ndk/lib/env.sh" "$h/src/ndk/lib/"
  cp "$ALT_TREE/ndk/build.conf" "$h/src/ndk/"
  cp "$ALT_TREE/phone-test.sh" "$h/src/"
  cat > "$h/src/ndk/scripts/stage.py" <<'PY'
import os
case = os.environ['ALT_CASE']
st = '/work/stage/module/android-linux-tools'
def put(rel, text):
    p = os.path.join(st, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w') as f:
        f.write(text)
put('module.prop', 'id=android-linux-tools\nversion=v0.0-r1\n')
# a long listing: thousands of entries after the one that matters
for i in range(3000):
    put('system/etc/android-linux-tools/share/data/f%04d.txt' % i, 'data %d\n' % i)
if case == 'hostpath':
    # compressible text, so zip stores it deflated
    put('system/etc/android-linux-tools/share/nmap/scripts.db', 'Entry { filename = "x.nse" }\n' * 200 +
        'built in /work/build/src/nmap-1\n' + 'Entry { filename = "y.nse" }\n' * 200)
PY
  printf 'import sys\nsys.exit(0)\n' > "$h/src/ndk/scripts/check.py"
  printf 'print("{}")\n' > "$h/src/ndk/scripts/layout_test.py"
  printf 'print("manifest")\n' > "$h/src/ndk/scripts/manifest.py"
  alt_bwrap "$h/root" "$h/src" "$h/work" --setenv ALT_CASE "$1" bash /src/ndk/package.sh > "$h/out.txt" 2>&1
  echo "rc=$?"
  grep -E 'host path|unexpected entries' "$h/out.txt"
  rm -rf "$h"
}

r=$(run_case clean)
case "$r" in rc=0) ok "clean module packages (rc=0)" ;; *) bad "clean module: $r" ;; esac
r=$(run_case hostpath)
case "$r" in rc=0*) bad "build-host path in a deflated file not detected: $r" ;; *"host path"*) ok "host path detected" ;; *) bad "hostpath: $r" ;; esac
[ "$FAILS" -eq 0 ]
