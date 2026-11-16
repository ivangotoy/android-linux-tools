#!/system/bin/sh
# android-linux-tools: run by the root manager (as root) when the module is removed; Magisk, KernelSU and APatch
# do not run it when a new version is installed over the old one. Removes the module's root-only directory under
# /data/local (root's adb key pair and root's temporary files of the wrappers), only if it is a real directory
# owned by root, not a symlink. Nothing else is touched.
ALT_ROOT=/data/local/android-linux-tools
if [ -d "$ALT_ROOT" ] && [ ! -L "$ALT_ROOT" ] && [ -O "$ALT_ROOT" ]; then
  rm -rf "$ALT_ROOT"
fi
exit 0
