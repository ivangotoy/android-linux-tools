# BIND 9 dig and host (no named, no DoH)
VERSION=9.20.30
URL=https://downloads.isc.org/isc/bind9/$VERSION/bind-$VERSION.tar.xz
SHA256=9e1443a40a72a30272cbc3196d020a6b2e26937111c83e59e101e82e1e3b4fef
CHECKSUM_SOURCE="detached signature $URL.asc, ISC code-signing key (Michal Nowak) D99CCEAF879747014F038D63182E23579462EFAA"
LICENSE=MPL-2.0
DEPS="libuv liburcu openssl libcap"
# dig/host resolve server names (@name) with getaddrinfo: system libc for netd DNS; BIND's own libraries
# (libisc, libdns, libisccfg) and all dependencies are linked in statically
LINKAGE=dynamic
build() {
  # the libcap recipe installs libcap.a and headers but no libcap.pc
  LIBCAP_CFLAGS=" " LIBCAP_LIBS="-lcap" \
  configure_std --disable-doh --without-libnghttp2 --without-jemalloc --without-libxml2 --without-json-c \
    --without-lmdb --without-gssapi --without-libidn2 --without-readline --without-zlib --disable-geoip \
    --without-cmocka --disable-dnstap --disable-tracing --disable-fips-mode --disable-chroot
  make -j"$JOBS" -C lib
  make -j"$JOBS" -C bin/dig dig host
  install_bin bin/dig/dig dig
  install_bin bin/dig/host host
}
