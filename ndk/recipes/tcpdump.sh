VERSION=4.99.7
URL=https://www.tcpdump.org/release/tcpdump-$VERSION.tar.xz
SHA256=39675dfa06fb0e99be8da5d4a1784acbaab58ae0870231d956ff7870cb99eec1
CHECKSUM_SOURCE="detached signature $URL.sig, The Tcpdump Group key 1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D"
LICENSE=BSD-3-Clause
DEPS="libpcap"
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  configure_std --without-crypto --without-cap-ng --without-smi --disable-local-libpcap
  make -j"$JOBS"
  install_bin tcpdump tcpdump
}
