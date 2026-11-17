# dosfstools: FAT12/16/32 tools (mkfs.fat, fsck.fat, fatlabel)
VERSION=4.2
URL=https://github.com/dosfstools/dosfstools/releases/download/v$VERSION/dosfstools-$VERSION.tar.gz
SHA256=64926eebf90092dca21b14259a5301b7b98e7b1943e8a201c7d726084809b527
CHECKSUM_SOURCE="detached signature $URL.sig, Andreas Bombe key 25714AECDBFDACEE1CE95FE77F6022516E869F64"
LICENSE=GPL-3.0-or-later
build() {
  # without iconv: names and labels are converted with dosfstools' built-in CP850 table; bionic's iconv has
  # only ASCII and the Unicode encodings (UTF-8/16/32), not the DOS codepages
  configure_std --without-iconv
  make -j"$JOBS"
  install_bin src/mkfs.fat mkfs.fat
  install_bin src/fsck.fat fsck.fat
  install_bin src/fatlabel fatlabel
}
