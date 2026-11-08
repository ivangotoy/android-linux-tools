VERSION=1.11.0
URL=https://github.com/lz4/lz4/releases/download/v$VERSION/lz4-$VERSION.tar.gz
SHA256=247e5fa64da5f7b75ee3dd3bed484076396c9ebe8254d9ccf693eb62800c5e26
CHECKSUM_SOURCE="$URL.sha256 published in the GitHub release"
LICENSE="BSD-2-Clause AND GPL-2.0-or-later"
build() {
  make -j"$JOBS" -C programs lz4 CC="$CC" AR="$AR" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"
  install_bin programs/lz4 lz4
}
