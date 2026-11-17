# exfatprogs: exFAT filesystem tools (mkfs.exfat, fsck.exfat, tune.exfat, exfatlabel, dump.exfat)
VERSION=1.4.4
URL=https://github.com/exfatprogs/exfatprogs/releases/download/$VERSION/exfatprogs-$VERSION.tar.xz
SHA256=102bbdfd934776c12c6d83743a31ec648f8c2f1ddfa1832b6e13b6efd09412cb
CHECKSUM_SOURCE="detached signature $URL.asc, Hyunchul Lee key D58529CC5376E36D6E1E6F6234F230FAF78E48D3; sha256 equals $URL.sha256"
LICENSE=GPL-2.0-or-later
# mkfs.exfat looks for an existing filesystem or partition table with util-linux's libblkid
DEPS="util-linux"
build() {
  configure_std
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin mkfs/mkfs.exfat mkfs.exfat
  install_bin fsck/fsck.exfat fsck.exfat
  install_bin tune/tune.exfat tune.exfat
  install_bin label/exfatlabel exfatlabel
  install_bin dump/dump.exfat dump.exfat
}
