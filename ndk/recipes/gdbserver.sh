# gdbserver only, from the GNU gdb source tree
VERSION=18.1
URL=https://ftp.gnu.org/gnu/gdb/gdb-$VERSION.tar.xz
SHA256=cd9fc3fe2b47743840e42c1592d3d87f8302eb18639c0b8b4ba0898002e2348f
CHECKSUM_SOURCE="detached signature $URL.sig, Joel Brobecker key F40ADB902B24264AA42E50BF92EDB04BFF325CF3 (GNU keyring)"
LICENSE=GPL-3.0-or-later
SRCDIR=gdb-$VERSION
# gdbserver HOST:PORT resolves the host name (getaddrinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  # gnulib's cdefs.h (from glibc) redefines __bos() in terms of glibc's __USE_FORTIFY_LEVEL, which bionic's
  # FORTIFY headers then fail to compile with: build without -D_FORTIFY_SOURCE
  export CFLAGS="${CFLAGS/-D_FORTIFY_SOURCE=2 /}" CXXFLAGS="${CXXFLAGS/-D_FORTIFY_SOURCE=2 /}"
  mkdir -p build
  cd build
  # no in-process agent (a shared library)
  LDFLAGS="$LDFLAGS -static-libstdc++" ../configure "${CONFIGURE_HOST[@]}" --disable-gdb --enable-gdbserver \
    --disable-inprocess-agent --disable-sim --disable-gprofng --disable-ld --disable-gas --disable-binutils \
    --disable-gold --disable-libctf --disable-readline --disable-libdecnumber --disable-werror \
    --disable-unit-tests --without-zstd --without-debuginfod
  make -j"$JOBS" all-gdbserver
  install_bin gdbserver/gdbserver gdbserver
}
