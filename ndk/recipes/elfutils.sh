# libelf (for libbpf/bpftool, bcc, bpftrace, ltrace) and the programs eu-stack, eu-readelf, eu-nm, eu-unstrip,
# eu-addr2line. argp (argp-standalone) and obstack (musl-obstack) are linked into the programs only.
VERSION=0.197
URL=https://sourceware.org/elfutils/ftp/$VERSION/elfutils-$VERSION.tar.bz2
SHA256=1fdf525f22dcf796d99a99ba3ea00a1f7b1ae5421bc62e8443a708920b99b904
ARGP_VERSION=1.5.0
OBSTACK_VERSION=1.2.3
EXTRA_SRCS=("https://github.com/argp-standalone/argp-standalone/archive/refs/tags/$ARGP_VERSION.tar.gz c29eae929dfebd575c38174f2c8c315766092cec99a8f987569d0cad3c6d64f6"
            "https://github.com/void-linux/musl-obstack/archive/refs/tags/v$OBSTACK_VERSION.tar.gz 9ffb3479b15df0170eba4480e51723c3961dbe0b461ec289744622db03a69395")
CHECKSUM_SOURCE="detached signature $URL.sig (key 6C2B631563B8D330578D3CB474FD3FA2779E7073) and sha512.sum in the same directory; argp-standalone $ARGP_VERSION and musl-obstack $OBSTACK_VERSION: GitHub tag archives, no upstream signature, sha256 recorded at pin time (argp-standalone: the same sha256 as termux-packages packages/argp/build.sh)"
LICENSE="(LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later"
build() {
  local top=$PWD dep=$PWD/alt-deps
  mkdir -p "$dep/include" "$dep/lib"
  # argp and obstack for the eu-* programs (bionic has neither): static libraries in a private prefix
  rm -rf "argp-standalone-$ARGP_VERSION" "musl-obstack-$OBSTACK_VERSION"
  tar -xf "$DL/$ARGP_VERSION.tar.gz" --no-same-owner
  tar -xf "$DL/v$OBSTACK_VERSION.tar.gz" --no-same-owner
  (cd "argp-standalone-$ARGP_VERSION" && autoreconf -fi && configure_std && make -j"$JOBS" libargp.a)
  cp "argp-standalone-$ARGP_VERSION/libargp.a" "$dep/lib/"
  cp "argp-standalone-$ARGP_VERSION/argp.h" "$dep/include/"
  (cd "musl-obstack-$OBSTACK_VERSION" && ./bootstrap.sh && configure_std && make -j"$JOBS")
  cp "musl-obstack-$OBSTACK_VERSION/.libs/libobstack.a" "$dep/lib/"
  cp "musl-obstack-$OBSTACK_VERSION/obstack.h" "$dep/include/"
  # argp-standalone ships no licence file: its notice (LGPL-2.0-or-later; COPYING-LGPLV3 is a later version)
  sed -n '1,19p' "argp-standalone-$ARGP_VERSION/argp-parse.c" > LICENSE.argp-standalone
  cp "musl-obstack-$OBSTACK_VERSION/COPYING" LICENSE.musl-obstack
  # lib/eu-config.h includes <libintl.h> unconditionally; bionic has no gettext: header-only no-op shim
  mkdir -p compat
  printf '%s\n' '#define dgettext(d, s) ((char *)(s))' '#define gettext(s) ((char *)(s))' \
    '#define ngettext(s, p, n) ((n) == 1 ? (char *)(s) : (char *)(p))' '#define dngettext(d, s, p, n) ngettext(s, p, n)' \
    '#define textdomain(d) ((void)0)' '#define bindtextdomain(d, x) ((void)0)' > compat/libintl.h
  # glibc's program_invocation_short_name/program_invocation_name: bionic's getprogname()
  printf '%s\n' '#include <stdlib.h>' '#define program_invocation_short_name ((char *) getprogname())' \
    '#define program_invocation_name ((char *) getprogname())' > compat/progname.h
  # -Wno-error: libcpu's x86 tables use printf %n, which bionic's format checking rejects
  export CFLAGS="$CFLAGS -Wno-error"
  export CPPFLAGS="$CPPFLAGS -I$top/compat -I$dep/include -include $top/compat/progname.h" LDFLAGS="$LDFLAGS -L$dep/lib"
  configure_std --disable-debuginfod --disable-libdebuginfod --without-zstd --without-bzlib --without-lzma \
    --disable-symbol-versioning --disable-demangler --disable-textrelcheck
  # static archives only (elfutils always builds its shared libraries otherwise); libdw.a contains libdwfl,
  # libdwfl_stacktrace, libdwelf, libebl, the backends and libcpu
  make -j"$JOBS" -C lib
  local a
  for a in libelf/libelf.a libebl/libebl.a backends/libebl_backends.a libcpu/libcpu.a libdwelf/libdwelf.a \
           libdwfl/libdwfl.a libdwfl_stacktrace/libdwfl_stacktrace.a libdw/libdw.a; do
    make -j"$JOBS" -C "${a%/*}" "${a#*/}"
  done
  make -j"$JOBS" -C src readelf nm unstrip addr2line stack \
    libdw='../libdw/libdw.a -lz ../libelf/libelf.a' libelf='../libelf/libelf.a -lz' \
    readelf_DEPENDENCIES= nm_DEPENDENCIES= unstrip_DEPENDENCIES= addr2line_DEPENDENCIES= stack_DEPENDENCIES=
  for a in stack readelf nm unstrip addr2line; do
    install_bin "src/$a" "eu-$a"
  done
  # libelf for dependants: libelf objects and the four libeu helpers it uses
  mkdir -p "$PKGDIR/lib" "$PKGDIR/include"
  rm -f "$PKGDIR/lib/libelf.a"
  $AR rcs "$PKGDIR/lib/libelf.a" libelf/*.o lib/eu-search.o lib/next_prime.o lib/crc32.o lib/xmalloc.o
  cp libelf/libelf.h libelf/gelf.h libelf/nlist.h "$PKGDIR/include/"
  mkdir -p "$PKGDIR/include/elfutils"
  cp libelf/elf-knowledge.h "$PKGDIR/include/elfutils/" 2>/dev/null || true
}
