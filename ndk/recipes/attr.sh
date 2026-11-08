VERSION=2.6.0
URL=https://download.savannah.nongnu.org/releases/attr/attr-$VERSION.tar.xz
SHA256=6c8a2148a7b85043b68492bce43316b0e2e214fc4e628c7ede078e76e216330b
CHECKSUM_SOURCE="detached signature $URL.sig, key 259B3792B3D6D319212CC4DCD5BF9FEB0313653A"
LICENSE="LGPL-2.1-or-later AND GPL-2.0-or-later"
build() {
  configure_std
  make -j"$JOBS" libattr.la
  install_lib install-libLTLIBRARIES install-pkgconfDATA install-data-local
}
