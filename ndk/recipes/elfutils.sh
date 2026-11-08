# libelf only (for libbpf/bpftool)
VERSION=0.197
URL=https://sourceware.org/elfutils/ftp/$VERSION/elfutils-$VERSION.tar.bz2
SHA256=1fdf525f22dcf796d99a99ba3ea00a1f7b1ae5421bc62e8443a708920b99b904
CHECKSUM_SOURCE="detached signature $URL.sig (key 6C2B631563B8D330578D3CB474FD3FA2779E7073) and sha512.sum in the same directory"
LICENSE="LGPL-3.0-or-later OR GPL-2.0-or-later"
build() {
  # lib/eu-config.h includes <libintl.h> unconditionally; bionic has no gettext: header-only no-op shim
  mkdir -p compat
  printf '%s\n' '#define dgettext(d, s) ((char *)(s))' '#define gettext(s) ((char *)(s))' \
    '#define textdomain(d) ((void)0)' '#define bindtextdomain(d, x) ((void)0)' > compat/libintl.h
  export CPPFLAGS="$CPPFLAGS -I$PWD/compat"
  # configure insists on argp and obstack (used by the eu-* tools, not by libelf): answer the probes
  ac_cv_search_argp_parse='none required' ac_cv_search__obstack_free='none required' \
  ac_cv_search_fts_close='none required' ac_cv_search__obstack_free='none required' \
    configure_std --disable-debuginfod --disable-libdebuginfod --without-zstd --without-bzlib --without-lzma \
    --disable-symbol-versioning --disable-demangler --disable-textrelcheck
  # only libelf and the four libeu helpers it uses (the rest of libeu needs argp)
  make -C lib eu-search.o next_prime.o crc32.o xmalloc.o
  make -j"$JOBS" -C libelf libelf.a
  mkdir -p "$PKGDIR/lib" "$PKGDIR/include"
  rm -f "$PKGDIR/lib/libelf.a"
  $AR rcs "$PKGDIR/lib/libelf.a" libelf/*.o lib/eu-search.o lib/next_prime.o lib/crc32.o lib/xmalloc.o
  cp libelf/libelf.h libelf/gelf.h libelf/nlist.h "$PKGDIR/include/"
  mkdir -p "$PKGDIR/include/elfutils"
  cp libelf/elf-knowledge.h "$PKGDIR/include/elfutils/" 2>/dev/null || true
}
