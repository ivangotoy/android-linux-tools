VERSION=1.3.2
URL=https://www.netfilter.org/pub/libnftnl/libnftnl-$VERSION.tar.xz
SHA256=c97abc3409f8fa396b4462b2bb7f147a3a47a4ddc97cfa0b2f18890c9cfde8b0
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 8C5F7146A1757A65E2422A94D70D1A666ACF2B21"
LICENSE=GPL-2.0-or-later
DEPS="libmnl"
build() {
  configure_std
  make -j"$JOBS"
  install_lib
}
