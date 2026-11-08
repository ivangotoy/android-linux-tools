VERSION=1.0.1
URL=https://www.netfilter.org/pub/libnetfilter_cttimeout/libnetfilter_cttimeout-$VERSION.tar.bz2
SHA256=0b59da2f3204e1c80cb85d1f6d72285fc07b01a2f5678abf5dccfbbefd650325
CHECKSUM_SOURCE="netfilter.org detached signature $URL.sig, Netfilter Core Team key 37D964ACC04981C75500FB9BD55D978A8A1420E4"
LICENSE=GPL-2.0-or-later
DEPS="libmnl"
build() {
  configure_std
  make -j"$JOBS"
  install_lib
}
