# bcc symbol/ELF/proc helpers only (upstream target bcc-loader-static: no LLVM, no clang frontend); for bpftrace
VERSION=0.37.0
URL=https://github.com/iovisor/bcc/releases/download/v$VERSION/bcc-src-with-submodule-$VERSION.tar.gz
SRCDIR=bcc-src-with-submodule-$VERSION/bcc
SHA256=7734b780202b22dff335780b506b56833ec6cf7435e03b1346d5bf644b4e1f95
CHECKSUM_SOURCE="no upstream checksum or signature; sha256 equals the GitHub release asset digest"
LICENSE=Apache-2.0
DEPS="elfutils xz"
build() {
  # src/cc/CMakeLists.txt: bcc-loader-static = bcc_sym_sources (bcc_syms.cc bcc_elf.c bcc_perf_map.c
  # bcc_proc.c bcc_zip.c) + bcc_util_sources (common.cc); bpftrace uses only bcc_syms/bcc_elf/bcc_proc.
  # common.cc's libbpf calls are resolved by bpftrace's own libbpf at link time.
  # HAVE_LIBLZMA: read .gnu_debugdata (MiniDebugInfo, xz) symbol tables, as in Android system libraries
  cd src/cc
  rm -rf obj && mkdir obj
  for f in bcc_elf.c bcc_perf_map.c bcc_proc.c bcc_zip.c; do
    $CC $CFLAGS $CPPFLAGS -DHAVE_LIBLZMA -I. -Ilibbpf/include -c "$f" -o "obj/${f%.c}.o"
  done
  for f in bcc_syms.cc common.cc; do
    $CXX $CXXFLAGS $CPPFLAGS -DHAVE_LIBLZMA -std=c++17 -I. -Ilibbpf/include -c "$f" -o "obj/${f%.cc}.o"
  done
  mkdir -p "$PKGDIR/lib" "$PKGDIR/include/bcc"
  rm -f "$PKGDIR/lib/libbcc-loader-static.a"
  $AR rcsD "$PKGDIR/lib/libbcc-loader-static.a" obj/bcc_elf.o obj/bcc_perf_map.o obj/bcc_proc.o obj/bcc_zip.o \
    obj/bcc_syms.o obj/common.o
  cp bcc_syms.h bcc_proc.h bcc_elf.h "$PKGDIR/include/bcc/"
}
