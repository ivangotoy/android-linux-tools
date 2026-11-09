# header-only C++ serialisation library (bpftrace's AOT/serialised types)
VERSION=1.3.2
URL=https://github.com/USCiLab/cereal/archive/refs/tags/v$VERSION.tar.gz
TARBALL=cereal-$VERSION.tar.gz
SHA256=16a7ad9b31ba5880dac55d62b5d6f243c3ebc8d46a3514149e56b5e7ea81f85f
CHECKSUM_SOURCE="no upstream checksum or signature; GitHub tag archive of the unsigned tag v$VERSION, sha256 recorded at pin time"
LICENSE=BSD-3-Clause
build() {
  mkdir -p "$PKGDIR/include"
  cp -a include/cereal "$PKGDIR/include/"
}
