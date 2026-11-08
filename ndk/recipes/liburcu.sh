VERSION=0.15.7
URL=https://lttng.org/files/urcu/userspace-rcu-$VERSION.tar.bz2
SRCDIR=userspace-rcu-$VERSION
SHA256=2556b83adc0f9b3ac8024e613e17d014d04c4c49110604ce55fcb14eae32edd3
CHECKSUM_SOURCE="detached signature $URL.asc, Mathieu Desnoyers key 2A0B4ED915F2D3FA45F5B16217280A9781186ACF; also $URL.sha256"
LICENSE="LGPL-2.1-or-later AND MIT"
build() {
  configure_std --disable-numa
  make -j"$JOBS" -C include
  make -j"$JOBS" -C src
  install_lib -C include install
  install_lib -C src install
}
