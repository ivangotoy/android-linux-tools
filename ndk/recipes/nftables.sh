VERSION=1.1.7
URL=https://www.netfilter.org/pub/nftables/nftables-$VERSION.tar.xz
SHA256=a6fbf060d8d4fff001517a2b94f356bb4366bfbf0ba366366f9d27cc38caa58f
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 8C5F7146A1757A65E2422A94D70D1A666ACF2B21"
LICENSE=GPL-2.0-only
DEPS="libmnl libnftnl"
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  configure_std --with-mini-gmp --without-cli --without-json --without-xtables \
    --disable-man-doc --disable-python
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin src/nft nft
}
