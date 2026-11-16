# ndk/module/customize.sh (real script) as root under busybox ash (alpine:3.22, no network) with a simulated device
# binary /system/bin/ip: the wrapper "ip" must become "ip-ng"; when that rename fails (system/bin of the module is
# read-only) the install must stop with abort naming the tool, never keep a wrapper that shadows the device binary.
. "$ALT_TESTS/lib.sh"
command -v docker >/dev/null || { echo "tests: missing host tool docker" >&2; exit 2; }
docker image inspect alpine:3.22 >/dev/null 2>&1 || { echo "tests: docker image alpine:3.22 missing" >&2; exit 2; }
h=$(alt_scratch)
# mod_tree: module tree with customize.sh, module.prop and the wrappers ip and jq
mod_tree() {
  mkdir -p "$1/system/bin" "$1/system/etc/android-linux-tools/libexec"
  cp "$ALT_TREE/ndk/module/customize.sh" "$1/"
  echo version=v0.0-r1 > "$1/module.prop"
  for w in ip jq; do printf '#!/system/bin/sh\nALTDIR=/system/etc/android-linux-tools\nexec "$ALTDIR/libexec/%s" "$@"\n' "$w" > "$1/system/bin/$w"; done
}
# run.sh [manager]: "manager" defines ui_print and abort like the root managers do (abort removes MODPATH)
cat > "$h/run.sh" <<'SH'
# hand the module tree back to the calling user (customize.sh chowns to 0:0 like on a device)
trap 'chown -R "$ALT_OWNER" /mod 2>/dev/null' EXIT
mkdir -p /system/bin && printf '#!/bin/sh\n' > /system/bin/ip && chmod 755 /system/bin/ip
if [ "$1" = manager ]; then
  ui_print() { echo "$1"; }
  abort() { ui_print "$1"; rm -rf "$MODPATH" 2>/dev/null; echo "ABORTED"; exit 1; }
fi
MODPATH=/mod
. /mod/customize.sh
echo "END bin:$(ls /mod/system/bin | tr '\n' ' ')"
SH
mod_tree "$h/ok"
out=$(timeout 120 docker run --rm --network none -e ALT_OWNER="$(id -u):$(id -g)" -v "$h/run.sh:/run.sh:ro" -v "$h/ok:/mod" alpine:3.22 sh /run.sh manager 2>&1)
case "$out" in
  *"END bin:ip-ng jq "*) ok "customize.sh renames ip to ip-ng when the device has ip" ;;
  *) bad "customize.sh rename: $(echo "$out" | tr '\n' ' ')" ;;
esac
for mode in manager fallback; do
  mod_tree "$h/ro-$mode"
  out=$(timeout 120 docker run --rm --network none -e ALT_OWNER="$(id -u):$(id -g)" -v "$h/run.sh:/run.sh:ro" -v "$h/ro-$mode:/mod" \
    -v "$h/ro-$mode/system/bin:/mod/system/bin:ro" alpine:3.22 sh /run.sh "$mode" 2>&1; echo "rc=$?")
  case "$out" in
    *END*) bad "customize.sh ($mode abort) went on after a failed rename: $(echo "$out" | tr '\n' ' ')" ;;
    *"cannot rename ip to ip-ng (device has /system/bin/ip)"*"rc=1") ok "customize.sh ($mode abort) stops the install when the rename of ip fails" ;;
    *) bad "customize.sh ($mode abort) failed rename: $(echo "$out" | tr '\n' ' ')" ;;
  esac
done

# the fallback abort (installer without abort) removes MODPATH like the managers' abort, but only a real directory
# holding this module's module.prop: "", "/", a trailing-slash path, a symlink, a dir without module.prop and a
# dir with another module's id are left alone. The fallback is taken from customize.sh (everything before the
# MODPATH check) and called directly, each call in its own subshell.
sed '/^\[ -n "\$MODPATH" \]/,$d' "$ALT_TREE/ndk/module/customize.sh" > "$h/fallback.sh"
cat > "$h/abort.sh" <<'SH'
. /w/fallback.sh
p='id=android-linux-tools'
mkdir -p /m1 /m2 /m3 /m4 /m5 && echo "$p" > /m1/module.prop && echo id=other-module > /m3/module.prop
echo "$p" > /m4/module.prop && echo "$p" > /m5/module.prop && ln -s /m4 /l4
for m in "" / // /m2 /m3 /l4 /l4/ /m5/ /m1; do ( MODPATH=$m; abort "! test" ) > /dev/null; echo "abort[$m] rc=$?"; done
for d in /m1 /m2 /m3 /m4 /m5 /etc /l4; do [ -e "$d" ] && echo "kept $d" || echo "gone $d"; done
SH
out=$(timeout 120 docker run --rm --network none -v "$h:/w:ro" alpine:3.22 sh /w/abort.sh 2>&1)
want='abort[] rc=1
abort[/] rc=1
abort[//] rc=1
abort[/m2] rc=1
abort[/m3] rc=1
abort[/l4] rc=1
abort[/l4/] rc=1
abort[/m5/] rc=1
abort[/m1] rc=1
gone /m1
kept /m2
kept /m3
kept /m4
gone /m5
kept /etc
kept /l4'
if [ "$out" = "$want" ]; then
  ok "fallback abort removes only a real MODPATH with this module's module.prop"
else
  bad "fallback abort: $(echo "$out" | tr '\n' ' ')"
fi
rm -rf "$h"
[ "$FAILS" -eq 0 ]
