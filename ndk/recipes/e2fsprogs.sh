VERSION=1.47.4
URL=https://www.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v$VERSION/e2fsprogs-$VERSION.tar.xz
SHA256=fd5bf388cbdbe006a3d3b318d983b2948382440acc85a87f1e7d108653e8db0b
CHECKSUM_SOURCE="kernel.org sha256sums.asc in the same directory (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE="GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT"
build() {
  # backtrace() is API 33 and qsort_r() API 36 (both in libc.a); CONFIG_SITE already says no, keep explicit
  configure_std --disable-fuse2fs --disable-uuidd --disable-fsck --disable-defrag --disable-e2initrd-helper \
    --disable-backtrace --without-libarchive --disable-tdb ac_cv_func_qsort_r=no ac_cv_func_backtrace=no
  make -j"$JOBS" libs
  make -j"$JOBS" -C e2fsck e2fsck
  make -j"$JOBS" -C misc mke2fs tune2fs
  make -j"$JOBS" -C resize resize2fs
  install_bin e2fsck/e2fsck e2fsck
  install_bin misc/mke2fs mke2fs
  install_bin misc/tune2fs tune2fs
  install_bin resize/resize2fs resize2fs
}
