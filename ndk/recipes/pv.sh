VERSION=1.12.7
URL=https://www.ivarch.com/s/pv-$VERSION.tar.gz
SHA256=5326ed7ee95ef18039390c0b17891ac28985ac7c7a4235070fab767c1fe37bd8
CHECKSUM_SOURCE="detached signature $URL.txt exists but its key was not obtainable at pin time; sha256 pinned at download"
LICENSE=Artistic-2.0
build() {
  configure_std --disable-ipc --disable-copy-file-range
  make -j"$JOBS"
  install_bin pv pv
}
