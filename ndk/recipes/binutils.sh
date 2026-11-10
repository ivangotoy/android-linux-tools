# GNU binutils: objdump, nm, addr2line, readelf, strings, objcopy, strip, size, ar, c++filt, elfedit for aarch64 ELF (bfd/opcodes for the aarch64 target)
VERSION=2.47
URL=https://ftp.gnu.org/gnu/binutils/binutils-$VERSION.tar.xz
SHA256=154ab23b60070e8f27013c22977f1129425d67d1e8acd6e13010e617811e4cff
CHECKSUM_SOURCE="detached signature $URL.sig, Nick Clifton key 3A24BC1E8FB409FA9F14371813FCEF89DD9E3C4F"
LICENSE="GPL-3.0-or-later AND LGPL-2.1-or-later"
build() {
  # release build: no development-mode -Werror
  sed -i '/^development=/s/true/false/' bfd/development.sh
  mkdir -p build
  cd build
  ../configure "${CONFIGURE_HOST[@]}" --target="$TARGET" --disable-gdb --disable-gdbserver --disable-gas --disable-ld \
    --disable-gold --disable-gprof --disable-gprofng --disable-sim --disable-libctf --disable-werror --disable-plugins \
    --with-system-zlib --without-zstd --without-debuginfod --without-msgpack --disable-libdecnumber --disable-readline \
    --disable-pgo-build
  make -j"$JOBS" configure-binutils all-libiberty all-bfd all-opcodes all-libsframe
  # libtool links the programs: -all-static for fully static executables
  make -j"$JOBS" -C binutils objdump nm-new addr2line readelf strings objcopy strip-new size ar cxxfilt elfedit LDFLAGS="$LT_LDFLAGS"
  install_bin binutils/objdump objdump
  install_bin binutils/nm-new nm
  install_bin binutils/addr2line addr2line
  install_bin binutils/readelf readelf
  install_bin binutils/strings strings
  install_bin binutils/objcopy objcopy
  install_bin binutils/strip-new strip
  install_bin binutils/size size
  install_bin binutils/ar ar
  install_bin binutils/cxxfilt c++filt
  install_bin binutils/elfedit elfedit
}
