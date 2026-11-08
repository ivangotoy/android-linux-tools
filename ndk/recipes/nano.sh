VERSION=9.3
URL=https://www.nano-editor.org/dist/v9/nano-$VERSION.tar.xz
SHA256=a9affc52c9596ee0682bcdd4ceb3c0b235eb221d83d733dfd9b0dff45897cb0d
CHECKSUM_SOURCE="detached signature $URL.asc, Benno Schulenberg key 168E6F4297BFD7A79AFD4496514BBE2EB8E1961F"
LICENSE=GPL-3.0-or-later
DEPS="ncurses"
build() {
  configure_std --enable-utf8 --disable-libmagic --disable-speller --with-wordbounds
  make -j"$JOBS"
  install_bin src/nano nano
}
