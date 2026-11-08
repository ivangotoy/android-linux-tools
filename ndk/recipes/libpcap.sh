VERSION=1.10.7
URL=https://www.tcpdump.org/release/libpcap-$VERSION.tar.xz
SHA256=68fa62cffb974f4275641ce14c2e2d75739251f30e00e6a0900903b247d76a03
CHECKSUM_SOURCE="detached signature $URL.sig, The Tcpdump Group key 1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D"
LICENSE=BSD-3-Clause
build() {
  configure_std --with-pcap=linux --without-libnl --disable-dbus --disable-rdma --disable-bluetooth \
    --disable-usb --disable-netmap --without-dpdk --disable-remote
  make -j"$JOBS"
  install_lib
}
