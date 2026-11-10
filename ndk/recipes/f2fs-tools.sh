VERSION=1.17.0
URL=https://git.kernel.org/pub/scm/linux/kernel/git/jaegeuk/f2fs-tools.git/snapshot/f2fs-tools-$VERSION.tar.gz
SHA256=1dbc89ada373b43cc9130b47ad3f575117583ca74715e952046c88a121a2a469
CHECKSUM_SOURCE="no release tarballs or checksums upstream; cgit snapshot of tag 1.17.0 (commit 83fd39a184df96db5def895ddc55bf68e720ef76), sha256 pinned at download"
LICENSE="GPL-2.0-or-later OR LGPL-2.1-or-later"
build() {
  ./autogen.sh
  # preadv2() is API 33 (in libc.a): CONFIG_SITE says no
  configure_std --without-selinux --without-blkid --without-lzo2 --without-lz4
  make -j"$JOBS" -C lib
  make -j"$JOBS" -C fsck LDFLAGS="$LT_LDFLAGS"
  make -j"$JOBS" -C mkfs LDFLAGS="$LT_LDFLAGS"
  make -j"$JOBS" -C tools LDFLAGS="$LT_LDFLAGS"
  install_bin fsck/fsck.f2fs fsck.f2fs
  # same binary, mode chosen by argv[0]
  install_bin fsck/fsck.f2fs dump.f2fs
  install_bin fsck/fsck.f2fs resize.f2fs
  install_bin fsck/fsck.f2fs sload.f2fs
  install_bin mkfs/mkfs.f2fs mkfs.f2fs
  install_bin tools/f2fs_io/f2fs_io f2fs_io
}
