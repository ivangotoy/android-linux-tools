VERSION=3.22
URL=https://downloads.es.net/pub/iperf/iperf-$VERSION.tar.gz
SHA256=1c0d0fb02c52626111d6e132db80edfbf27bbaff8bd9245df2a371dcb0b35a92
CHECKSUM_SOURCE="$URL.sha256 published by ESnet"
LICENSE=BSD-3-Clause-LBNL
SRCDIR=iperf-$VERSION
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  configure_std --without-openssl --without-sctp
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin src/iperf3 iperf3
}
