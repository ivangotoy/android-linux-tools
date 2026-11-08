VERSION=1.0pre4
URL=https://www.ex-parrot.com/pdw/iftop/download/iftop-$VERSION.tar.gz
SHA256=f733eeea371a7577f8fe353d86dd88d16f5b2a2e702bd96f5ffb2c197d9b4f97
CHECKSUM_SOURCE="no upstream checksum or signature published; sha256 pinned at download (same file as Alpine aports community/iftop)"
LICENSE=GPL-2.0-or-later
DEPS="libpcap ncurses"
# resolves host names (getnameinfo in the resolver thread): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  LIBS=-lncursesw configure_std --with-libpcap="$DEPROOT" --with-resolver=netdb
  make -j"$JOBS"
  install_bin iftop iftop
}
