VERSION=7.3
URL=https://github.com/strace/strace/releases/download/v$VERSION/strace-$VERSION.tar.xz
SHA256=529634c40910895a9a1f3c5c1e65da2ca9ed72fb158dfc4bcc89efdf05e39b72
CHECKSUM_SOURCE="detached signature $URL.asc, Dmitry V. Levin key FB3DCD19FF874735E4F61CE64E9FE8522F160EC2"
LICENSE=LGPL-2.1-or-later
build() {
  configure_std --enable-mpers=no --disable-gcc-Werror --without-libdw --without-libunwind --without-libiberty
  make -j"$JOBS"
  install_bin src/strace strace
}
