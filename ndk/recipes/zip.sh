# Info-ZIP Zip 3.0 (zip, zipcloak, zipnote, zipsplit) with Debian's patch series (security and build fixes)
VERSION=3.0
URL=https://downloads.sourceforge.net/infozip/zip30.tar.gz
SRCDIR=zip30
SHA256=f0e8bb1f9b7eb0b01285495a2699df3a4b766784c1765a8f1aeedf63c0806369
CHECKSUM_SOURCE="no upstream signature; sha256 equals zip_3.0.orig.tar.gz in Debian's zip_3.0-16.dsc (signed by Santiago Vila, key D54C3BFAFFB042DE382DA5D741CE7F0B9F1B8B32), which also lists the sha256 of the patch series below"
LICENSE=Info-ZIP
# Debian's zip_3.0-16 packaging (debian/patches/series), from snapshot.debian.org
EXTRA_SRCS=(
  "https://snapshot.debian.org/archive/debian/20260807T202035Z/pool/main/z/zip/zip_3.0-16.debian.tar.xz fa79a0226f00f487b290489f62e1cd7f4a338df529a1e413fea4d168b8eee8f7"
)
build() {
  local p
  tar -xf "$DL/zip_3.0-16.debian.tar.xz"
  for p in $(grep -v '^#' debian/patches/series); do
    patch -p1 -s --no-backup-if-mismatch < "debian/patches/$p"
  done
  # unix/configure as in debian/rules (LDFLAGS from the environment, no -s). Its Large File Support test runs a
  # test program, which a cross build cannot do: -DLARGE_FILE_SUPPORT (Zip64, 64-bit off_t on aarch64) is given here
  LDFLAGS="$LDFLAGS" sh unix/configure "$CC" "-I. -DUNIX $CFLAGS $CPPFLAGS -DLARGE_FILE_SUPPORT"
  grep -q -e '-DUNICODE_SUPPORT' flags
  ! grep -n -e '-DNO_DIR' -e '-DZMEM' -e '-DNO_ERRNO' -e '-DNO_MKSTEMP' flags
  make -f unix/Makefile generic
  for p in zip zipcloak zipnote zipsplit; do install_bin "$p" "$p"; done
  # the patches are Debian's (same licence as the package)
  cp debian/copyright LICENSE.debian-copyright
}
