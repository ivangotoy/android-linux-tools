# ndk/build.sh (real script, in bwrap) with small fake recipes and local source tarballs.
. "$ALT_TESTS/lib.sh"

# new_tree: scratch dir with the build scripts of ALT_TREE under src/ndk; prints its path
new_tree() {
  local h; h=$(alt_scratch)
  mkdir -p "$h/src/ndk/lib" "$h/src/ndk/recipes" "$h/src/fx" "$h/work"
  cp "$ALT_TREE/ndk/build.sh" "$ALT_TREE/ndk/Dockerfile" "$ALT_TREE/ndk/build.conf" "$h/src/ndk/"
  cp "$ALT_TREE/ndk/lib/env.sh" "$ALT_TREE/ndk/lib/api-site.py" "$h/src/ndk/lib/"
  echo "$h"
}
# tarball H NAME: src/fx/NAME-1.tar.gz with one file; prints its sha256
tarball() {
  mkdir -p "$1/fx-src/$2-1"
  echo "$2" > "$1/fx-src/$2-1/hello.txt"
  tar -C "$1/fx-src" --sort=name --mtime=@0 --owner=0 --group=0 -czf "$1/src/fx/$2-1.tar.gz" "$2-1"
  sha256sum "$1/src/fx/$2-1.tar.gz" | cut -d' ' -f1
}
# recipe H NAME URL SHA BODY: write src/ndk/recipes/NAME.sh with build() { BODY; }
recipe() {
  printf 'VERSION=1\nURL=%s\nSHA256=%s\nLICENSE=MIT\nbuild() { %s; }\n' "$3" "$4" "$5" > "$1/src/ndk/recipes/$2.sh"
}
build() {
  local h=$1; shift
  alt_bwrap "$h/root" "$h/src" "$h/work" bash /src/ndk/build.sh "$@"
}

# a recipe input under ndk/module/<recipe>/ (git's gitconfig) is part of the recipe's identity
case_module_input() {
  local h sha; h=$(new_tree)
  sha=$(tarball "$h" altmod)
  recipe "$h" altmod file:///src/fx/altmod-1.tar.gz "$sha" \
    'mkdir -p "$OUT/data/rt/altmod/etc"; cp "$SRCROOT/ndk/module/altmod/conf" "$OUT/data/rt/altmod/etc/conf"'
  mkdir -p "$h/src/ndk/module/altmod"
  echo v1 > "$h/src/ndk/module/altmod/conf"
  build "$h" altmod > "$h/run1.txt" 2>&1 || { bad "module input: first build failed"; return; }
  echo v2 > "$h/src/ndk/module/altmod/conf"
  build "$h" altmod > "$h/run2.txt" 2>&1 || { bad "module input: second build failed"; return; }
  if [ "$(cat "$h/work/out/data/rt/altmod/etc/conf")" = v2 ]; then
    ok "module input: edited ndk/module/altmod/conf rebuilds the recipe"
  else
    bad "module input: edited ndk/module/altmod/conf, the cached build still has $(cat "$h/work/out/data/rt/altmod/etc/conf")"
  fi
  rm -rf "$h"
}

# a failed rebuild must not leave the previous stamp: build.sh has already removed the recipe's package
# (pkg/<recipe>) at that point, so reverting the recipe would otherwise reuse a stamp whose output is gone
case_failed_rebuild() {
  local h sha; h=$(new_tree)
  sha=$(tarball "$h" altlib)
  recipe "$h" altlib file:///src/fx/altlib-1.tar.gz "$sha" 'mkdir -p "$PKGDIR/lib"; echo lib > "$PKGDIR/lib/libalt.a"'
  cp "$h/src/ndk/recipes/altlib.sh" "$h/altlib.sh.good"
  build "$h" altlib > "$h/run1.txt" 2>&1 || { bad "failed rebuild: first build failed"; return; }
  echo 'build() { false; }' >> "$h/src/ndk/recipes/altlib.sh"
  if build "$h" altlib > "$h/run2.txt" 2>&1; then bad "failed rebuild: the broken recipe built"; return; fi
  cp "$h/altlib.sh.good" "$h/src/ndk/recipes/altlib.sh"
  build "$h" altlib > "$h/run3.txt" 2>&1 || { bad "failed rebuild: build after the revert failed"; return; }
  if [ -f "$h/work/build/pkg/altlib/lib/libalt.a" ]; then
    ok "failed rebuild: the reverted recipe is built again, its package is present"
  else
    bad "failed rebuild: reverted recipe reused its old stamp, pkg/altlib is missing ($(grep -c ' build altlib' "$h/run3.txt") build lines in run 3)"
  fi
  rm -rf "$h"
}

# a download that stalls (connection open, no data) must time out and be retried, not hang the build
case_fetch_stall() {
  local h sha port spid rc i; h=$(new_tree)
  sha=$(tarball "$h" altnet)
  cat > "$h/server.py" <<'PY'
import socket, sys
# first connection: accepted and never answered; later ones get the tarball
data = open(sys.argv[1], 'rb').read()
s = socket.socket()
s.bind(('127.0.0.1', 0))
s.listen(8)
open(sys.argv[2], 'w').write(str(s.getsockname()[1]))
held = [s.accept()[0]]
while True:
    c, _ = s.accept()
    c.recv(65536)
    c.sendall(b'HTTP/1.0 200 OK\r\nContent-Length: %d\r\n\r\n' % len(data) + data)
    c.close()
PY
  python3 -I "$h/server.py" "$h/src/fx/altnet-1.tar.gz" "$h/port" & spid=$!
  for i in $(seq 50); do [ -s "$h/port" ] && break; sleep 0.1; done
  port=$(cat "$h/port")
  recipe "$h" altnet "http://127.0.0.1:$port/altnet-1.tar.gz" "$sha" 'cat hello.txt'
  ALT_TOOLS=$ALT_TOOLS timeout 150 bash -c "$(declare -f alt_bwrap build); build \"\$1\" altnet" _ "$h" > "$h/run.txt" 2>&1
  rc=$?
  kill "$spid" 2>/dev/null; wait "$spid" 2>/dev/null
  if [ "$rc" -eq 0 ] && ls "$h/work/build/stamps/altnet."* >/dev/null 2>&1; then
    ok "fetch stall: the stalled download timed out and the retry fetched the source"
  elif [ "$rc" -eq 124 ]; then
    bad "fetch stall: build.sh still waiting on the stalled download after 150 s"
  else
    bad "fetch stall: rc=$rc $(tail -n 3 "$h/run.txt" | tr '\n' ' ')"
  fi
  rm -rf "$h"
}

# SOURCE_DATE_EPOCH (ndk/build.conf) is exported into every build: a new value must rebuild the recipe
case_source_date_epoch() {
  local h sha; h=$(new_tree)
  sha=$(tarball "$h" altsde)
  recipe "$h" altsde file:///src/fx/altsde-1.tar.gz "$sha" \
    'mkdir -p "$OUT/data"; echo "$SOURCE_DATE_EPOCH" > "$OUT/data/altsde"'
  build "$h" altsde > "$h/run1.txt" 2>&1 || { bad "SOURCE_DATE_EPOCH: first build failed"; return; }
  sed -i 's/^SOURCE_DATE_EPOCH=.*/SOURCE_DATE_EPOCH=1700000000/' "$h/src/ndk/build.conf"
  build "$h" altsde > "$h/run2.txt" 2>&1 || { bad "SOURCE_DATE_EPOCH: second build failed"; return; }
  if [ "$(cat "$h/work/out/data/altsde")" = 1700000000 ]; then
    ok "SOURCE_DATE_EPOCH: a new value rebuilds the recipe"
  else
    bad "SOURCE_DATE_EPOCH: new value in build.conf, the cached build still has $(cat "$h/work/out/data/altsde")"
  fi
  rm -rf "$h"
}

# the real cacert recipe (offline: its downloads are placed in dl/ and the recipe's pins are set to them) must
# leave the MPL-2.0 text of the CA bundle in out/licenses/cacert/ for stage.py's licence rows
case_cacert_licence() {
  local h v; h=$(new_tree)
  mkdir -p "$h/work/dl"
  v=$(sed -n 's/^VERSION=//p' "$ALT_TREE/ndk/recipes/cacert.sh")
  printf '## example CA bundle\n-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n' > "$h/work/dl/cacert-$v.pem"
  printf 'Mozilla Public License Version 2.0\n==================================\n(example text)\n' > "$h/work/dl/MPL-2.0.txt"
  python3 -I - "$ALT_TREE/ndk/recipes/cacert.sh" "$h/src/ndk/recipes/cacert.sh" "$h/work/dl/cacert-$v.pem" "$h/work/dl/MPL-2.0.txt" <<'PY'
import hashlib, re, sys
src, dst, pem, mpl = sys.argv[1:5]
sha = lambda p: hashlib.sha256(open(p, 'rb').read()).hexdigest()
out = []
for line in open(src):
    if line.startswith('SHA256='):
        line = 'SHA256=%s\n' % sha(pem)
    elif 'MPL-2.0.txt' in line:
        line = re.sub(r'[0-9a-f]{64}', sha(mpl), line)
    out.append(line)
open(dst, 'w').write(''.join(out))
PY
  build "$h" cacert > "$h/run.txt" 2>&1 || { bad "cacert: build failed: $(tail -n 3 "$h/run.txt" | tr '\n' ' ')"; rm -rf "$h"; return; }
  if grep -l -s 'Mozilla Public License Version 2.0' "$h/work/out/licenses/cacert/"* > /dev/null; then
    ok "cacert: MPL-2.0 text in out/licenses/cacert ($(ls "$h/work/out/licenses/cacert" | tr '\n' ' '))"
  else
    bad "cacert: no MPL-2.0 text in out/licenses/cacert ($(ls "$h/work/out/licenses/cacert" 2>/dev/null | tr '\n' ' '))"
  fi
  rm -rf "$h"
}

case_module_input
case_failed_rebuild
case_source_date_epoch
case_fetch_stall
case_cacert_licence
[ "$FAILS" -eq 0 ]
