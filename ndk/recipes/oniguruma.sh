VERSION=6.9.10
URL=https://github.com/kkos/oniguruma/releases/download/v$VERSION/onig-$VERSION.tar.gz
SRCDIR=onig-$VERSION
SHA256=2a5cfc5ae259e4e97f86b68dfffc152cdaffe94e2060b770cb827238d769fc05
CHECKSUM_SOURCE="$URL.sha256 published in the GitHub release"
LICENSE=BSD-2-Clause
build() {
  configure_std
  make -j"$JOBS"
  install_lib
}
