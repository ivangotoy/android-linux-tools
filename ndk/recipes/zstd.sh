VERSION=1.5.7
URL=https://github.com/facebook/zstd/releases/download/v$VERSION/zstd-$VERSION.tar.gz
SHA256=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
CHECKSUM_SOURCE="$URL.sha256 and detached signature $URL.sig (key 4EF4AC63455FC9F4545D9B7DEF8FE99528B52FFD)"
LICENSE="BSD-3-Clause OR GPL-2.0-only"
build() {
  make -j"$JOBS" -C programs zstd CC="$CC" AR="$AR" MOREFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS" \
    HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 HAVE_THREAD=1 ZSTD_LEGACY_SUPPORT=0 BACKTRACE=0
  install_bin programs/zstd zstd
}
