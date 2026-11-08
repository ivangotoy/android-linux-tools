VERSION=3.54.1
URL=https://www.sqlite.org/2026/sqlite-autoconf-3540100.tar.gz
SRCDIR=sqlite-autoconf-3540100
SHA256=926ef8d3eab93fbf6e06011901273eec076b25594a4e1cdadd50c987f4f6d64e
CHECKSUM_SOURCE="SHA3-256 b6ced585c750916b1052667239a12c25a7ff34e7f06e1e6e01ecb0427657d9c4 published on sqlite.org/download.html (verified at pin time)"
LICENSE=blessing
build() {
  # amalgamation + CLI shell compiled directly (no readline, no extension loading)
  $CC $CPPFLAGS $CFLAGS -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_MATH_FUNCTIONS -DHAVE_USLEEP \
    shell.c sqlite3.c $LDFLAGS -lm -o sqlite3
  install_bin sqlite3 sqlite3
}
