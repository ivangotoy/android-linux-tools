VERSION=2.78
URL=https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-$VERSION.tar.xz
SHA256=0d621e562fd932ccf67b9660fb018e468a683d7b827541df27813228c996bb11
CHECKSUM_SOURCE="kernel.org sha256sums.asc in the same directory (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE="BSD-3-Clause OR GPL-2.0-only"
build() {
  local mk=(CC="$CC" BUILD_CC=gcc AR="$AR" RANLIB="$RANLIB" OBJCOPY="$OBJCOPY" SHARED=no LIBCSTATIC=yes
            PTHREADS=no GOLANG=no PAM_CAP=no USE_GPERF=no COPTS="$CFLAGS -DSHELL=\\\"/system/bin/sh\\\"")
  make -j"$JOBS" -C libcap "${mk[@]}" libcap.a
  make -j"$JOBS" -C progs "${mk[@]}" capsh getpcaps getcap setcap
  mkdir -p "$PKGDIR/lib" "$PKGDIR/include/sys"
  cp libcap/libcap.a "$PKGDIR/lib/"
  cp libcap/include/sys/capability.h "$PKGDIR/include/sys/"
  install_bin progs/capsh capsh
  install_bin progs/getpcaps getpcaps
  install_bin progs/getcap getcap
  install_bin progs/setcap setcap
}
