VERSION=710
URL=https://ftp.gnu.org/gnu/less/less-$VERSION.tar.gz
SHA256=d1008fb78dcae1323ddab664bcb352a61f022b1b131bd8018548e021d975ec7a
CHECKSUM_SOURCE="GNU detached signature $URL.sig, Mark Nudelman key AE27252BD6846E7D6EAE1DD6F153A7C833235259"
LICENSE="GPL-3.0-or-later OR BSD-2-Clause"
DEPS="ncurses"
build() {
  LIBS=-lncursesw configure_std --with-regex=posix
  make -j"$JOBS"
  install_bin less less
}
