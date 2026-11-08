VERSION=8.23.0
URL=https://curl.se/download/curl-$VERSION.tar.xz
SHA256=8dadd7d2536a314f982ad05a651b713f426bf7d02cc2c76cffb9796f2218e6c5
CHECKSUM_SOURCE="detached signature $URL.asc, Daniel Stenberg key 27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2"
LICENSE=curl
DEPS="mbedtls cacert"
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  configure_std --with-mbedtls="$DEPROOT" --with-zlib --without-libpsl --without-libidn2 --without-nghttp2 \
    --without-brotli --without-zstd --without-libssh2 --without-librtmp --disable-ldap --disable-ldaps \
    --enable-threaded-resolver --disable-ares --disable-manual --disable-docs \
    --with-ca-bundle=/system/etc/android-linux-tools/etc/ssl/cert.pem \
    --without-ca-path --without-ca-fallback
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin src/curl curl
}
