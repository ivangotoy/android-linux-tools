VERSION=1.11.0
URL=https://github.com/lz4/lz4/releases/download/v$VERSION/lz4-$VERSION.tar.gz
SHA256=247e5fa64da5f7b75ee3dd3bed484076396c9ebe8254d9ccf693eb62800c5e26
CHECKSUM_SOURCE="$URL.sha256 published in the GitHub release"
LICENSE="BSD-2-Clause AND GPL-2.0-or-later"
build() {
  make -j"$JOBS" -C programs lz4 CC="$CC" AR="$AR" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
  install_bin programs/lz4 lz4
  # liblz4.a + headers + liblz4.pc for dependants (erofs-utils, squashfs-tools)
  make -j"$JOBS" -C lib liblz4.a CC="$CC" AR="$AR" CFLAGS="$CFLAGS"
  install_lib -C lib install PREFIX=/usr BUILD_SHARED=no CC="$CC" AR="$AR" CFLAGS="$CFLAGS"
}
