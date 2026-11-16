# ndk/package.sh (real script, in bwrap) with stub stage/check/layout/manifest scripts: the checks it runs on
# the module must fail the build when the module contains a build-host path or unwanted entries, and a rejected
# module must leave no ZIP in dist/.
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
elif case == 'pycache':
    put('META-INF/__pycache__/x.cpython.pyc', 'pyc\n')
PY
  printf 'import sys\nsys.exit(0)\n' > "$h/src/ndk/scripts/check.py"
  printf 'print("{}")\n' > "$h/src/ndk/scripts/layout_test.py"
  printf 'print("manifest")\n' > "$h/src/ndk/scripts/manifest.py"
  alt_bwrap "$h/root" "$h/src" "$h/work" --setenv ALT_CASE "$1" bash /src/ndk/package.sh > "$h/out.txt" 2>&1
  echo "rc=$?"
  grep -E 'host path|unexpected entries' "$h/out.txt"
  echo "dist:$(for f in "$h"/work/dist/*.zip; do [ -e "$f" ] && printf '%s ' "${f##*/}"; done)"
  rm -rf "$h"
}

r=$(run_case clean)
case "$r" in rc=0$'\n'*) ok "clean module packages (rc=0)" ;; *) bad "clean module: $r" ;; esac
r=$(run_case hostpath)
case "$r" in rc=0*) bad "build-host path in a deflated file not detected: $r" ;; *"host path"*) ok "host path detected" ;; *) bad "hostpath: $r" ;; esac
r=$(run_case pycache)
case "$r" in rc=0*) bad "__pycache__ entry early in a long listing not detected: $r" ;; *"unexpected entries"*) ok "__pycache__ entry detected" ;; *) bad "pycache: $r" ;; esac
# a module that failed a check must not leave its ZIP in dist/ (where release assets are taken from)
case "$(run_case clean)" in *"dist:android-linux-tools-v0.0-r1.zip "*) ok "clean module: ZIP in dist/" ;; *) bad "clean module: no ZIP in dist/" ;; esac
for c in hostpath pycache; do
  r=$(run_case "$c")
  case "$r" in rc=0*) bad "$c: packaged" ;; *"dist:") ok "$c: no ZIP left in dist/" ;; *) bad "$c: rejected ZIP left in dist/: $(echo "$r" | grep dist:)" ;; esac
done
[ "$FAILS" -eq 0 ]
