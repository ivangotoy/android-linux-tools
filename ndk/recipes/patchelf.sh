VERSION=0.19.3
URL=https://github.com/NixOS/patchelf/releases/download/$VERSION/patchelf-$VERSION.tar.bz2
SHA256=20dbe23e9dbc4ad769078a867ad002c04297a069ff93c95fb72242dd55d4dd6f
CHECKSUM_SOURCE="no upstream signature or checksum file; sha256 equals the GitHub release asset digest; tag $VERSION -> commit 2b4b49d36b62690860414dd127f567be4f1f3208 (GitHub-verified signature)"
LICENSE=GPL-3.0-or-later
build() {
  LDFLAGS="$LDFLAGS -static-libstdc++" configure_std
  make -j"$JOBS"
  install_bin src/patchelf patchelf
}
