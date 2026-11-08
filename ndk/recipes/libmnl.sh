VERSION=1.0.5
URL=https://www.netfilter.org/pub/libmnl/libmnl-$VERSION.tar.bz2
SHA256=274b9b919ef3152bfb3da3a13c950dd60d6e2bcd54230ffeca298d03b40d0525
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 37D964ACC04981C75500FB9BD55D978A8A1420E4 (signed 2022-04-05, key expired 2024-10)"
LICENSE=LGPL-2.1-or-later
build() {
  configure_std
  make -j"$JOBS"
  install_lib
}
