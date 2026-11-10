VERSION=3.54.1
URL=https://www.sqlite.org/2026/sqlite-autoconf-3540100.tar.gz
SRCDIR=sqlite-autoconf-3540100
SHA256=926ef8d3eab93fbf6e06011901273eec076b25594a4e1cdadd50c987f4f6d64e
# full source tree of the same release for tool/sqldiff.c and tool/sqlite3_rsync.c (not in the autoconf tarball)
EXTRA_SRCS=("https://www.sqlite.org/2026/sqlite-src-3540100.zip 387e7f6cad4797b17848c07d453dc6606917bb356a6cfe5a3abafd38c240c71b")
CHECKSUM_SOURCE="SHA3-256 b6ced585c750916b1052667239a12c25a7ff34e7f06e1e6e01ecb0427657d9c4 published on sqlite.org/download.html (verified at pin time); sqlite-src-3540100.zip: SHA3-256 877c6f4996ce7adb368686bce21638de9e3d91534832ad3d9d119037d1bc22ad published there (verified at pin time)"
LICENSE=blessing
build() {
  # amalgamation + CLI shell compiled directly (no readline, no extension loading)
  $CC $CPPFLAGS $CFLAGS -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_MATH_FUNCTIONS -DHAVE_USLEEP \
    shell.c sqlite3.c $LDFLAGS -lm -o sqlite3
  install_bin sqlite3 sqlite3
  # sqldiff and sqlite3_rsync as main.mk builds them: the tool source with the amalgamation
  unzip -q -o "$DL/sqlite-src-3540100.zip" 'sqlite-src-3540100/tool/sqldiff.c' 'sqlite-src-3540100/tool/sqlite3_rsync.c' \
    'sqlite-src-3540100/ext/misc/sqlite3_stdio.h' 'sqlite-src-3540100/ext/misc/sqlite3_stdio.c' \
    'sqlite-src-3540100/LICENSE.md'
  # the autoconf tarball has no licence file: the public-domain dedication of the source tree
  cp sqlite-src-3540100/LICENSE.md LICENSE.md
  $CC $CPPFLAGS $CFLAGS -I. -Isqlite-src-3540100/ext/misc -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION \
    sqlite-src-3540100/tool/sqldiff.c sqlite3.c $LDFLAGS -lm -o sqldiff
  $CC $CPPFLAGS $CFLAGS -I. -DSQLITE_ENABLE_DBPAGE_VTAB -DSQLITE_THREADSAFE=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_DEPRECATED \
    sqlite-src-3540100/tool/sqlite3_rsync.c sqlite3.c $LDFLAGS -lm -o sqlite3_rsync
  install_bin sqldiff sqldiff
  install_bin sqlite3_rsync sqlite3_rsync
}
