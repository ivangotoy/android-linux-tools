VERSION=7.8.1
URL=https://github.com/libbpf/bpftool/releases/download/v$VERSION/bpftool-libbpf-v$VERSION-sources.tar.gz
SRCDIR=bpftool-libbpf-v$VERSION-sources
SHA256=fed76b7acb54d810cc3982eb6394726010114977542fd146695887a7d904b60c
CHECKSUM_SOURCE="no upstream checksum for the sources tarball; sha256 equals the GitHub release asset digest"
LICENSE="GPL-2.0-only OR BSD-2-Clause"
DEPS="elfutils libcap"
build() {
  # qsort_r() is API 36: declared hidden at API 29 but present in the static libc.a (GNU argument order)
  printf '%s\n' '#include <stddef.h>' \
    'void qsort_r(void *, size_t, size_t, int (*)(const void *, const void *, void *), void *);' > qsort_r_decl.h
  make -j"$JOBS" -C src CC="$CC" AR="$AR" HOSTCC=gcc HOSTAR=ar HOSTLD=ld LLVM_STRIP="$STRIP" \
    SKIP_LLVM=1 SKIP_LIBBFD=1 SKIP_CRYPTO=1 VMLINUX_BTF= feature-libcap=1 feature-zlib=1 feature-libelf=1 \
    EXTRA_CFLAGS="$CFLAGS $CPPFLAGS -include $PWD/qsort_r_decl.h" EXTRA_LDFLAGS="$LDFLAGS" V=1
  install_bin src/bpftool bpftool
}
