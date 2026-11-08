VERSION=1.0.2
URL=https://www.netfilter.org/pub/libnfnetlink/libnfnetlink-$VERSION.tar.bz2
SHA256=b064c7c3d426efb4786e60a8e6859b82ee2f2c5e49ffeea640cfe4fe33cbc376
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 37D964ACC04981C75500FB9BD55D978A8A1420E4 (signed 2022-04-05, key expired 2024-10)"
LICENSE=GPL-2.0-or-later
build() {
  configure_std
  make -j"$JOBS"
  install_lib
}
