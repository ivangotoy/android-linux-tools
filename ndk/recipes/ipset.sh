VERSION=7.24
URL=https://www.netfilter.org/pub/ipset/ipset-$VERSION.tar.bz2
SHA256=fbe3424dff222c1cb5e5c34d38b64524b2217ce80226c14fdcbb13b29ea36112
CHECKSUM_SOURCE="no upstream signature found for 7.24 (ipset.netfilter.org unreachable at pin time); sha512 cross-checked against Alpine aports 3.24-stable main/ipset/APKBUILD"
LICENSE=GPL-2.0-only
DEPS="libmnl"
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  configure_std --with-kmod=no
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin src/ipset ipset
}
