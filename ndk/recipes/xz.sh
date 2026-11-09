VERSION=5.8.4
URL=https://github.com/tukaani-project/xz/releases/download/v$VERSION/xz-$VERSION.tar.xz
SHA256=4ce24038fd4221e0d13bc1a2de7a4db56e90b92b3bf75321f6c14be73f65de4b
CHECKSUM_SOURCE="detached signature $URL.sig, Lasse Collin key 3690C240CE51B4670D30AD1C38EE757D69184620"
LICENSE="0BSD AND GPL-2.0-or-later"
build() {
  configure_std --enable-sandbox=no --disable-doc --disable-scripts --disable-lzmainfo --disable-lzmadec \
    --disable-xzdec --disable-lzma-links
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin src/xz/xz xz
  # liblzma.a + headers for dependants (bcc's MiniDebugInfo reader, bpftrace)
  install_lib -C src/liblzma install
}
