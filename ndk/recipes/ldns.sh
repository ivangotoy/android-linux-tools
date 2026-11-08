VERSION=1.9.2
URL=https://nlnetlabs.nl/downloads/ldns/ldns-$VERSION.tar.gz
SHA256=b524fa21994b6e834200ceb8c27f1b84bda5982fe35706f058196c079db94d5d
CHECKSUM_SOURCE="$URL.sha256 published by NLnet Labs"
LICENSE=BSD-3-Clause
build() {
  configure_std --without-ssl --with-drill --without-examples --without-pyldns --without-pyldnsx \
    --disable-dane --disable-gost --disable-ecdsa --disable-ed25519 --disable-ed448 --disable-sha2 --disable-dsa
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin drill/drill drill
}
