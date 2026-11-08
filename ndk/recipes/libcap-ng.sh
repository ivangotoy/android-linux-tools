VERSION=0.9.6
URL=https://github.com/stevegrubb/libcap-ng/archive/refs/tags/v$VERSION.tar.gz
TARBALL=libcap-ng-$VERSION.tar.gz
SHA256=399040138e0ca62fa2bcabd63da9af4431a246ef7a654561a0ca3cb00010a539
CHECKSUM_SOURCE="GitHub tag archive v$VERSION (upstream publishes no checksum or signature for 0.9.x)"
LICENSE=LGPL-2.1-or-later
build() {
  ./autogen.sh
  configure_std --without-python --without-python3 --disable-cap-audit
  make -j"$JOBS" -C src libcap-ng.la
  install_lib -C src install
}
