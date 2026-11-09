# erofs-utils: mkfs.erofs, fsck.erofs, dump.erofs with lz4/lz4hc, lzma (xz), deflate (zlib) and zstd
VERSION=1.9.4
URL=https://git.kernel.org/pub/scm/linux/kernel/git/xiang/erofs-utils.git/snapshot/erofs-utils-$VERSION.tar.gz
SHA256=7d135aa2550326a5acf20f53c518aea5a8900015ce50700044e40f818c31dd80
CHECKSUM_SOURCE="no release tarball or signature; git.kernel.org snapshot of tag v$VERSION (tag object 20ca6747ae03043895a3120c1ea3c863a573213a -> commit f36cadb5c563995ab3aa8572a60ed6b721b9557d), sha256 recorded at pin time"
LICENSE="MIT AND (GPL-2.0-or-later OR MIT)"
DEPS="zstd xz lz4"
build() {
  ./autogen.sh
  # zlib: the NDK's libz (no zlib.pc); no libuuid, SELinux, FUSE, libdeflate, QPL or xxhash; single-threaded
  # (the multi-threaded build requires a separate libpthread, which bionic does not have)
  configure_std --enable-lz4 --enable-lzma --with-zlib --with-libzstd --without-uuid --without-selinux --disable-fuse \
    --without-libdeflate --without-qpl --without-xxhash --disable-multithreading zlib_CFLAGS=" " zlib_LIBS=-lz
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin mkfs/mkfs.erofs mkfs.erofs
  install_bin fsck/fsck.erofs fsck.erofs
  install_bin dump/dump.erofs dump.erofs
  cp LICENSES/GPL-2.0 LICENSE.GPL-2.0
  cp LICENSES/MIT LICENSE.MIT
}
