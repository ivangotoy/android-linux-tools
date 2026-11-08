VERSION=0.96
URL=https://github.com/traviscross/mtr/archive/refs/tags/v$VERSION.tar.gz
TARBALL=mtr-$VERSION.tar.gz
SHA256=73e6aef3fb6c8b482acb5b5e2b8fa7794045c4f2420276f035ce76c5beae632d
CHECKSUM_SOURCE="GitHub tag archive v$VERSION (the bitwizard.nl release tarball is known to lack utils.h); no upstream signature"
LICENSE=GPL-2.0-only
# libcap: mtr-packet drops its capabilities after opening the raw sockets
DEPS="ncurses libcap"
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  echo "$VERSION" > .tarball-version
  ./bootstrap.sh
  configure_std --without-gtk --without-jansson --with-ncurses
  make -j"$JOBS"
  # mtr-packet does no name resolution: relink it fully static
  rm -f mtr-packet
  make mtr-packet LDFLAGS="$LDFLAGS_BASE -static"
  install_bin mtr mtr
  install_bin mtr-packet mtr-packet
}
