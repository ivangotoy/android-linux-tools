# Mozilla CA bundle as extracted by the curl project (https://curl.se/docs/caextract.html).
VERSION=2026-11-05
URL=https://curl.se/ca/cacert-$VERSION.pem
SHA256=427c064216761a1e72a8b30f0d954d08cb6e4435a82091fb865afd20c8497285
# the bundle's licence text (MPL-2.0; the bundle itself carries no licence file): SPDX license-list-data, tag
# v3.29.0 = commit 31ba1a50e5397e00a304dbadc76531740e89ee48, fetched by commit so the bytes cannot change
SPDX_COMMIT=31ba1a50e5397e00a304dbadc76531740e89ee48
EXTRA_SRCS=("https://raw.githubusercontent.com/spdx/license-list-data/$SPDX_COMMIT/text/MPL-2.0.txt 66a3107d5ad6a058aab753eaac2047ccb2ed0e39465dd0fe5844da3e300d5172")
CHECKSUM_SOURCE="https://curl.se/ca/cacert.pem.sha256 (same file as cacert.pem on 2026-11-05); MPL-2.0.txt: no upstream checksum, SPDX license-list-data tag v3.29.0 (commit $SPDX_COMMIT), sha256 recorded at pin time"
LICENSE=MPL-2.0
SRCDIR=cacert-$VERSION
build() {
  mkdir -p "$OUT/data"
  install -m 0644 "cacert-$VERSION.pem" "$OUT/data/cacert.pem"
  # LICENSE*: collected into the licence directory by build.sh
  install -m 0644 "$DL/MPL-2.0.txt" LICENSE.MPL-2.0.txt
}
