# squashfs-tools: mksquashfs, unsquashfs, sqfstar, sqfscat with gzip (zlib), xz, lz4 and zstd
VERSION=4.7.5
URL=https://github.com/plougher/squashfs-tools/releases/download/$VERSION/squashfs-tools-$VERSION.tar.gz
SHA256=547b7b7f4d2e44bf91b6fc554664850c69563701deab9fd9cd7e21f694c88ea6
CHECKSUM_SOURCE="no upstream signature (tag $VERSION is an unsigned tag object -> commit 708c59ae80853b0845017c33b42e56061cc546cd); sha256 equals the GitHub release asset digest"
LICENSE=GPL-2.0-or-later
DEPS="zstd xz lz4"
build() {
  cd squashfs-tools
  # the Makefile links -lpthread; bionic has pthreads in libc: an empty libpthread.a
  mkdir -p compat
  $AR rc compat/libpthread.a
  make -j"$JOBS" CC="$CC" EXTRA_CFLAGS="$CFLAGS $CPPFLAGS" EXTRA_LDFLAGS="$LDFLAGS -L$PWD/compat" \
    GZIP_SUPPORT=1 XZ_SUPPORT=1 LZ4_SUPPORT=1 ZSTD_SUPPORT=1 LZO_SUPPORT=0 LZMA_XZ_SUPPORT=0 XATTR_SUPPORT=1 \
    mksquashfs unsquashfs
  install_bin mksquashfs mksquashfs
  install_bin unsquashfs unsquashfs
  # upstream installs sqfstar and sqfscat as links: same binaries, mode chosen by argv[0]
  install_bin mksquashfs sqfstar
  install_bin unsquashfs sqfscat
}
