VERSION=3.5.3
URL=https://github.com/htop-dev/htop/releases/download/$VERSION/htop-$VERSION.tar.xz
SHA256=a8b164386494cb85bb255a415a3f5f80afe7a0c4491da5d113b3a0f951087e65
CHECKSUM_SOURCE="$URL.sha256 published in the GitHub release"
LICENSE=GPL-2.0-or-later
DEPS="ncurses"
build() {
  # pow/log10 live in libm.a; configure's ceil() probe is satisfied by a compiler builtin
  LIBS=-lm configure_std --enable-unicode --disable-sensors --disable-delayacct --disable-capabilities \
    --disable-hwloc --disable-unwind --enable-affinity
  make -j"$JOBS"
  install_bin htop htop
}
