# android-linux-tools v2 installer hook (Magisk, KernelSU, APatch), for builds without Alpine/musl binaries.
# Uses only ui_print/set_perm/set_perm_recursive from the manager, with fallbacks.

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

# one ZIP since the lite/full flavours were merged; it installs over either of them (same module id)
alt_version=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null)
ui_print "- Android Linux tools $alt_version"

ALT_DIRS="/system/bin /system/xbin /system_ext/bin /product/bin /vendor/bin /vendor/xbin /odm/bin"
for alt_d in /apex/*/bin; do
  [ -d "$alt_d" ] && ALT_DIRS="$ALT_DIRS $alt_d"
done

# wrappers of this module: v2.2+ (ALTDIR=/system/etc/...) and older versions (MODDIR=...)
alt_is_module_file() {
  head -c 400 "$1" 2>/dev/null | grep -qE 'ALTDIR=/system/etc/android-linux-tools|MODDIR=/data/adb/modules/android-linux-tools'
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
# runtime files (programs, terminfo, CA bundle, scripts, data): module system/etc/android-linux-tools, mounted by
# the root manager at /system/etc/android-linux-tools so every uid can use them (/data/adb is 0700 root)
ALT_RT="$MODPATH/system/etc/android-linux-tools"
ALT_MAP="$ALT_RT/etc/alt-tools.map"
mkdir -p "$ALT_RT/etc"
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

# root:root, system_file label; dirs, programs and scripts 0755, data 0644
ALT_CTX=u:object_r:system_file:s0
set_perm_recursive "$MODPATH" 0 0 0755 0644 "$ALT_CTX"
set_perm_recursive "$ALT_BIN" 0 0 0755 0755 "$ALT_CTX"
set_perm_recursive "$ALT_RT/libexec" 0 0 0755 0755 "$ALT_CTX"
for alt_s in dns-servers phone-test.sh; do
  [ -f "$ALT_RT/share/android-linux-tools/$alt_s" ] && set_perm "$ALT_RT/share/android-linux-tools/$alt_s" 0 0 0755 "$ALT_CTX"
done
# v2.1+: every program is an NDK (bionic) build (static, or linked against the system libc only): there is no
# bundled musl loader and no resolv.conf overlay; names resolve through Android netd, and DNS query tools
# take the active network's DNS servers from /system/etc/android-linux-tools/share/android-linux-tools/dns-servers.
ui_print "- Done. Reboot to activate."
