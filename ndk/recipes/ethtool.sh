VERSION=7.2
URL=https://www.kernel.org/pub/software/network/ethtool/ethtool-$VERSION.tar.xz
SHA256=44256ddf4631ed08d816b7b8725f4b2e0f05e96b8c7ca64ee5c81449da2b6507
CHECKSUM_SOURCE="kernel.org sha256sums.asc in the same directory (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE=GPL-2.0-only
DEPS="libmnl"
build() {
  configure_std --enable-netlink --disable-pretty-dump
  make -j"$JOBS"
  install_bin ethtool ethtool
}
