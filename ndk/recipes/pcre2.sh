# PCRE2 8-bit library for android-tools (libselinux file contexts)
VERSION=10.49
URL=https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$VERSION/pcre2-$VERSION.tar.bz2
SHA256=53c156e1ba416a20da8e65395daa132da0d80e76910424caca3fcdae7831d384
CHECKSUM_SOURCE="detached signature $URL.sig, Nicholas Wilson key A95536204A3BB489715231282A98E77EB6F24CA8 (signing subkey BACF71F10404D5761C09D392021DE40BFB63B406)"
LICENSE="BSD-3-Clause WITH PCRE2-exception"
build() {
  configure_std --enable-pcre2-8 --disable-pcre2-16 --disable-pcre2-32 --disable-jit --disable-pcre2grep-libz \
    --disable-pcre2grep-libbz2 --disable-pcre2test-libreadline
  make -j"$JOBS" libpcre2-8.la libpcre2-8.pc
  install_lib install-libLTLIBRARIES install-includeHEADERS install-nodist_includeHEADERS install-pkgconfigDATA
}
