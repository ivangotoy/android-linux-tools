VERSION=2.1.6
URL=https://downloads.sourceforge.net/project/traceroute/traceroute/traceroute-$VERSION/traceroute-$VERSION.tar.gz
SHA256=9ccef9cdb9d7a98ff7fbf93f79ebd0e48881664b525c4b232a0fcec7dcb9db5e
CHECKSUM_SOURCE="no upstream checksum or signature published; sha256 pinned at download"
LICENSE=GPL-2.0-or-later
# resolves host names (getaddrinfo/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  # traceroute/mod-tcp.c relies on <string.h> arriving indirectly (glibc/musl headers do, bionic does not)
  make -j1 CC="$CC" DEPEND="$CC -MM -MG" AR="$AR" RANLIB="$RANLIB" CFLAGS="$CFLAGS -include string.h" LDFLAGS="$LDFLAGS"
  install_bin traceroute/traceroute traceroute
}
