VERSION=1.8.1.3
URL=http://www.dest-unreach.org/socat/download/socat-$VERSION.tar.bz2
SHA256=25bc6476292b2e614220989c77b0b6fca87bb2525d9747b31a6639b1fb602418
CHECKSUM_SOURCE="http://www.dest-unreach.org/socat/download.sha256sum (published by the author)"
LICENSE="GPL-2.0-only WITH OpenSSL-Exception"
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  # bionic's struct __res_state is opaque: drop socat's resolver tweak options (lookups use getaddrinfo)
  ac_cv_header_resolv_h=no configure_std --disable-openssl --disable-readline --disable-libwrap --disable-fips
  make -j"$JOBS" socat
  install_bin socat socat
}
