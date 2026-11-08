# android-linux-tools installer hook (Magisk, KernelSU, APatch).
# Uses only ui_print/set_perm/set_perm_recursive from the manager, with fallbacks.

ALT_ID=android-linux-tools
ALT_MODDIR=/data/adb/modules/$ALT_ID

command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
if ! command -v set_perm >/dev/null 2>&1; then
  set_perm() {
    chown "$2:$3" "$1" 2>/dev/null
    chmod "$4" "$1"
    chcon "${5:-u:object_r:system_file:s0}" "$1" 2>/dev/null
    return 0
  }
fi
if ! command -v set_perm_recursive >/dev/null 2>&1; then
  set_perm_recursive() {
    find "$1" -type d 2>/dev/null | while read -r alt_f; do set_perm "$alt_f" "$2" "$3" "$4" "$6"; done
    find "$1" -type f 2>/dev/null | while read -r alt_f; do set_perm "$alt_f" "$2" "$3" "$5" "$6"; done
  }
fi
[ -n "$MODPATH" ] || { ui_print "! MODPATH not set by the root manager"; exit 1; }

alt_flavour=$(sed -n 's/^flavour=//p' "$MODPATH/module.prop" 2>/dev/null)
ui_print "- Android Linux tools ($alt_flavour flavour)"

if [ -d /data/adb/modules/prototype-tools ]; then
  touch /data/adb/modules/prototype-tools/remove
  ui_print "- Prototype module prototype-tools marked for removal (gone after reboot)"
fi

ALT_DIRS="/system/bin /system/xbin /system_ext/bin /product/bin /vendor/bin /vendor/xbin /odm/bin"
for alt_d in /apex/*/bin; do
  [ -d "$alt_d" ] && ALT_DIRS="$ALT_DIRS $alt_d"
done

alt_is_module_file() {
  head -c 400 "$1" 2>/dev/null | grep -qE 'MODDIR=/data/adb/modules/(android-linux-tools|prototype-tools)'
}

alt_device_path() {
  for alt_dd in $ALT_DIRS; do
    if [ -e "$alt_dd/$1" ] || [ -L "$alt_dd/$1" ]; then
      alt_is_module_file "$alt_dd/$1" && continue
      echo "$alt_dd/$1"
      return 0
    fi
  done
  return 1
}

ALT_BIN="$MODPATH/system/bin"
ALT_MAP="$MODPATH/etc/alt-tools.map"
mkdir -p "$MODPATH/etc"
: > "$ALT_MAP.new"
alt_renamed=0
for alt_w in $(ls "$ALT_BIN" | sort); do
  alt_new=$alt_w
  alt_dev=$(alt_device_path "$alt_w")
  if [ -n "$alt_dev" ]; then
    alt_new="$alt_w-ng"
    while alt_device_path "$alt_new" >/dev/null || [ -e "$ALT_BIN/$alt_new" ]; do
      alt_new="$alt_new-ng"
    done
    mv "$ALT_BIN/$alt_w" "$ALT_BIN/$alt_new"
    ui_print "  renamed $alt_w -> $alt_new (device has $alt_dev)"
    alt_renamed=$((alt_renamed + 1))
  fi
  echo "$alt_w $alt_new ${alt_dev:--}" >> "$ALT_MAP.new"
done
mv -f "$ALT_MAP.new" "$ALT_MAP"
ui_print "- $alt_renamed wrapper(s) renamed to avoid shadowing device binaries; run alt-list to see all"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/bin" 0 2000 0755 0755
set_perm_recursive "$MODPATH/libexec" 0 0 0755 0755
set_perm_recursive "$MODPATH/share/android-linux-tools" 0 0 0755 0755
# Alpine (musl) tools only: bundled musl loader. NDK (bionic) tools use /system/bin/linker64 or are static.
if [ -f "$MODPATH/lib/ld-musl-aarch64.so.1" ]; then
  set_perm "$MODPATH/lib/ld-musl-aarch64.so.1" 0 0 0755
  if [ ! -L "$MODPATH/lib/libc.musl-aarch64.so.1" ]; then
    rm -f "$MODPATH/lib/libc.musl-aarch64.so.1"
    ln -s ld-musl-aarch64.so.1 "$MODPATH/lib/libc.musl-aarch64.so.1"
  fi
  chcon -h u:object_r:system_file:s0 "$MODPATH/lib/libc.musl-aarch64.so.1" 2>/dev/null
fi

rm -f "$MODPATH/system/etc/resolv.conf"
# The resolv.conf overlay is only needed by remaining Alpine (musl) network tools; NDK tools resolve
# names through bionic/netd. The build ships share/android-linux-tools/resolv-refresh only then.
alt_rc=""
if [ ! -f "$MODPATH/share/android-linux-tools/resolv-refresh" ]; then
  alt_rc=none
  ui_print "- No musl network tools: no resolv.conf overlay (names resolve through Android netd)"
fi
[ -n "$alt_rc" ] || for alt_e in /system/etc/resolv.conf /etc/resolv.conf; do
  if [ -e "$alt_e" ] || [ -L "$alt_e" ]; then
    case "$(readlink "$alt_e" 2>/dev/null)" in
      "$ALT_MODDIR"/*) ;;
      *) alt_rc=$alt_e; break ;;
    esac
  fi
done
if [ "$alt_rc" = none ]; then
  :
elif [ -n "$alt_rc" ]; then
  ui_print "- Device already has $alt_rc: not overlaying it"
else
  mkdir -p "$MODPATH/system/etc"
  set_perm "$MODPATH/system/etc" 0 0 0755
  ln -sf "$ALT_MODDIR/etc/resolv.conf" "$MODPATH/system/etc/resolv.conf"
  chcon -h u:object_r:system_file:s0 "$MODPATH/system/etc/resolv.conf" 2>/dev/null
  ui_print "- /system/etc/resolv.conf -> $ALT_MODDIR/etc/resolv.conf (written at run time by network tools)"
fi
ui_print "- Done. Reboot to activate."
