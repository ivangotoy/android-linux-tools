# libtalloc (static) for mount.cifs
VERSION=2.5.0
URL=https://download.samba.org/pub/talloc/talloc-$VERSION.tar.gz
SHA256=912afa237510ae542a7733998eb18a12bcda35ab6729c8e2ddb43e8d0ebab007
CHECKSUM_SOURCE="detached signature ${URL%.gz}.asc over the uncompressed tar, Samba Library Distribution Key 9147A339719518EE9011BCB54793916113084025"
LICENSE=LGPL-3.0-or-later
build() {
  # waf cannot run target test programs: answer them for aarch64 bionic (as buildroot's libtalloc-cache.txt
  # does for glibc/musl); link tests against the API-35 libc.so stubs, not the static libc.a
  cat > cross-answers.txt <<'ANS'
Checking uname sysname type: "Linux"
Checking uname machine type: "aarch64"
Checking uname release type: "6.6.0"
Checking uname version type: "#1 SMP PREEMPT"
rpath library support: OK
-Wl,--version-script support: OK
Checking getconf LFS_CFLAGS: NO
Checking for large file support without additional flags: OK
Checking for -D_FILE_OFFSET_BITS=64: OK
Checking for -D_LARGE_FILES: OK
Checking correct behavior of strtoll: OK
Checking for working strptime: OK
Checking for C99 vsnprintf: OK
Checking for HAVE_SHARED_MMAP: OK
Checking for HAVE_MREMAP: OK
Checking for HAVE_INCOHERENT_MMAP: NO
Checking for HAVE_SECURE_MKSTEMP: OK
ANS
  LDFLAGS="$LDFLAGS_BASE" PYTHON=python3 ./configure --prefix=/usr --disable-python --disable-rpath \
    --cross-compile --cross-answers="$PWD/cross-answers.txt" --hostcc=gcc
  if grep -q UNKNOWN cross-answers.txt; then grep UNKNOWN cross-answers.txt; return 1; fi
  # only the library: talloc.c and the libreplace core it needs, as a static archive (waf builds .so only)
  local o=static-build
  mkdir -p $o
  for f in talloc.c lib/replace/replace.c; do
    $CC $CFLAGS -I bin/default -I lib/replace -I . -DHAVE_CONFIG_H=1 -D_GNU_SOURCE=1 -D__STDC_WANT_LIB_EXT1__=1 -D_SAMBA_BUILD_=4 \
      -DTALLOC_BUILD_VERSION_MAJOR=2 -DTALLOC_BUILD_VERSION_MINOR=5 -DTALLOC_BUILD_VERSION_RELEASE=0 \
      -c $f -o $o/$(basename ${f%.c}).o
  done
  mkdir -p "$PKGDIR/lib/pkgconfig" "$PKGDIR/include"
  rm -f "$PKGDIR/lib/libtalloc.a"
  $AR rcs "$PKGDIR/lib/libtalloc.a" $o/talloc.o $o/replace.o
  cp talloc.h "$PKGDIR/include/"
  printf '%s\n' "prefix=/usr" 'libdir=${prefix}/lib' 'includedir=${prefix}/include' '' 'Name: talloc' \
    "Version: $VERSION" 'Description: A hierarchical pool based memory system with destructors' \
    'Libs: -L${libdir} -ltalloc' 'Cflags: -I${includedir}' > "$PKGDIR/lib/pkgconfig/talloc.pc"
}
