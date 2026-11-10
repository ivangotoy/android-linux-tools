# ncdu 1.x (the maintained C line; 2.x is the Zig rewrite): disk usage browser on ncurses
VERSION=1.22
URL=https://dev.yorhel.nl/download/ncdu-$VERSION.tar.gz
SHA256=0ad6c096dc04d5120581104760c01b8f4e97d4191d6c9ef79654fa3c691a176b
CHECKSUM_SOURCE="detached signature $URL.asc, Yoran Heling key 74460D32B80810EBA9AFA2E962394C698C2739FA"
LICENSE=MIT
DEPS="ncurses"
build() {
  # the wide-character ncurses of the ncurses recipe (terminfo: $TERMINFO from the wrapper); the shell that the
  # "spawn shell" key starts when $NCDU_SHELL and $SHELL are unset
  configure_std --with-ncursesw --with-shell=/system/bin/sh
  make -j"$JOBS"
  install_bin ncdu ncdu
}
