VERSION=1.0.20260223
URL=https://git.zx2c4.com/wireguard-tools/snapshot/wireguard-tools-$VERSION.tar.xz
SHA256=af459827b80bfd31b83b08077f4b5843acb7d18ad9a33a2ef532d3090f291fbf
CHECKSUM_SOURCE="cgit signed snapshot ${URL%.xz}.asc (signature over the uncompressed tar), Jason A. Donenfeld key AB9942E6D4A4CFC3412620A749FC7012A5DE03AE"
LICENSE=GPL-2.0-only
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  make -j"$JOBS" -C src wg PLATFORM=linux
  install_bin src/wg wg
}
