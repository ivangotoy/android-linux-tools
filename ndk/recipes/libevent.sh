VERSION=2.1.13
URL=https://github.com/libevent/libevent/releases/download/release-$VERSION-stable/libevent-$VERSION-stable.tar.gz
SRCDIR=libevent-$VERSION-stable
SHA256=f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c
CHECKSUM_SOURCE="detached signature $URL.asc, key 7A02B3521DC75C542BA015456AFEE6D49E92B601"
LICENSE=BSD-3-Clause
build() {
  configure_std --disable-openssl --disable-mbedtls --disable-samples --disable-libevent-regress --disable-debug-mode
  make -j"$JOBS"
  install_lib
}
