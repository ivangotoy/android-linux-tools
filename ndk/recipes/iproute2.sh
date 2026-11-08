VERSION=7.3.0
URL=https://mirrors.edge.kernel.org/pub/linux/utils/net/iproute2/iproute2-$VERSION.tar.xz
SHA256=5c1789d290bba048a6135ed1ab81b0402dd0fb528d1f1421765c42b1fc3d6289
CHECKSUM_SOURCE="kernel.org ${URL%.xz}.sign (Stephen Hemminger key 110B8614708F62B83DD19F23F028172EC6AEB2B3, over the uncompressed tar) and sha256sums.asc (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE=GPL-2.0-or-later
DEPS="libmnl"
# resolves host names (getaddrinfo/gethostbyname2/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  ./configure --prefix=/usr --libbpf_force off --color auto
  sed -i -e '/^HAVE_ELF/d' -e '/^HAVE_SELINUX/d' -e '/^HAVE_CAP/d' -e '/^HAVE_BERKELEY_DB/d' -e '/^HAVE_TIRPC/d' config.mk
  # SHARED_LIBS=n links link types, qdiscs, filters and actions into ip/tc instead of looking them up
  # with dlopen(), which is a stub in static bionic
  make -j"$JOBS" SUBDIRS="lib ip tc misc bridge" SHARED_LIBS=n CC="$CC" AR="$AR" \
    CCOPTS="$CFLAGS" LDFLAGS="$LDFLAGS" V=1
  install_bin ip/ip ip
  install_bin tc/tc tc
  install_bin misc/ss ss
  install_bin bridge/bridge bridge
}
