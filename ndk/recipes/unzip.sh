# Info-ZIP UnZip 6.0 (unzip, funzip; zipinfo is unzip -Z) with Debian's patch series (CVE and build fixes)
VERSION=6.0
URL=https://downloads.sourceforge.net/infozip/unzip60.tar.gz
SRCDIR=unzip60
SHA256=036d96991646d0449ed0aa952e4fbe21b476ce994abc276e49d30e686708bd37
CHECKSUM_SOURCE="no upstream signature; sha256 equals unzip_6.0.orig.tar.gz in Debian's unzip_6.0-31.dsc (signed by Santiago Vila, key D54C3BFAFFB042DE382DA5D741CE7F0B9F1B8B32), which also lists the sha256 of the patch series below"
LICENSE=Info-ZIP
# Debian's unzip_6.0-31 packaging (debian/patches/series), from snapshot.debian.org
EXTRA_SRCS=(
  "https://snapshot.debian.org/archive/debian/20260810T202458Z/pool/main/u/unzip/unzip_6.0-31.debian.tar.xz d7dc23f5254c6711dc05f467e70236cfd50a7931001c6152904474b19f295c38"
)
build() {
  local p
  tar -xf "$DL/unzip_6.0-31.debian.tar.xz"
  # every patch of the series except Debian's branding of the usage banner ("UnZip ... by Debian")
  for p in $(grep -v '^#' debian/patches/series | grep -vx this-is-debian-unzip.patch); do
    patch -p1 -s --no-backup-if-mismatch < "debian/patches/$p"
  done
  # the defines of debian/rules without bzip2 (no bzip2 library in this tree: stored and deflated entries)
  make -f unix/Makefile unzips CC="$CC" LF2="$LDFLAGS" \
    CF="$CFLAGS $CPPFLAGS -I. -DACORN_FTYPE_NFS -DWILD_STOP_AT_DIR -DLARGE_FILE_SUPPORT -DUNICODE_SUPPORT \
        -DUNICODE_WCHAR -DUTF8_MAYBE_NATIVE -DNO_LCHMOD -DDATE_FORMAT=DF_YMD -DIZ_HAVE_UXUIDGID -DNOMEMCPY \
        -DNO_WORKING_ISPRINT"
  install_bin unzip unzip
  install_bin funzip funzip
  cp debian/copyright LICENSE.debian-copyright
}
