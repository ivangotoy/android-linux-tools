VERSION=2.3.2
URL=https://oldmanprogrammer.net/tar/tree/tree-$VERSION.tgz
SHA256=6b941dd6cbecfb4d3250700e4d08d8e0c251488981dd4868b90d744234300e21
CHECKSUM_SOURCE="no upstream checksum or signature published; sha256 pinned at download"
LICENSE=GPL-2.0-or-later
build() {
  make -j"$JOBS" CC="$CC" CFLAGS="$CFLAGS -std=c11 -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64" LDFLAGS="$LDFLAGS"
  install_bin tree tree
}
