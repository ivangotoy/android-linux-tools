# Mozilla CA bundle as extracted by the curl project (https://curl.se/docs/caextract.html).
VERSION=2026-11-05
URL=https://curl.se/ca/cacert-$VERSION.pem
SHA256=427c064216761a1e72a8b30f0d954d08cb6e4435a82091fb865afd20c8497285
CHECKSUM_SOURCE="https://curl.se/ca/cacert.pem.sha256 (same file as cacert.pem on 2026-11-05)"
LICENSE=MPL-2.0
SRCDIR=cacert-$VERSION
build() {
  mkdir -p "$OUT/data"
  install -m 0644 "cacert-$VERSION.pem" "$OUT/data/cacert.pem"
}
