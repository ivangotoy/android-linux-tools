VERSION=1.1.1
URL=https://www.netfilter.org/pub/libnetfilter_conntrack/libnetfilter_conntrack-$VERSION.tar.xz
SHA256=769d3eaf57fa4fbdb05dd12873b6cb9a5be7844d8937e222b647381d44284820
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 8C5F7146A1757A65E2422A94D70D1A666ACF2B21"
LICENSE=GPL-2.0-or-later
DEPS="libmnl libnfnetlink"
build() {
  configure_std
  make -j"$JOBS"
  install_lib
}
