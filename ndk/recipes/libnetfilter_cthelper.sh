VERSION=1.0.1
URL=https://www.netfilter.org/pub/libnetfilter_cthelper/libnetfilter_cthelper-$VERSION.tar.bz2
SHA256=14073d5487233897355d3ff04ddc1c8d03cc5ba8d2356236aa88161a9f2dc912
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 37D964ACC04981C75500FB9BD55D978A8A1420E4"
LICENSE=GPL-2.0-or-later
DEPS="libmnl"
build() {
  configure_std
  make -j"$JOBS"
  install_lib
}
