# ltrace with the aarch64 backend (upstream ltrace 0.8.x, gitlab.com/cespedes/ltrace)
VERSION=0.8.1
URL=https://gitlab.com/cespedes/ltrace/-/archive/$VERSION/ltrace-$VERSION.tar.gz
SHA256=11c85a1353fcf2b5438b19d0ccc2d376c96656ce6f11cf9537e3a92b84392c58
CHECKSUM_SOURCE="no upstream signature or published checksum: GitLab archive of tag $VERSION (commit 7ef6e6097586b751cce298c256a919404dab259d), sha256 pinned at download; the same sha256 is in termux-packages packages/ltrace/build.sh"
LICENSE=GPL-2.0-or-later
DEPS="elfutils"
build() {
  ./autogen.sh
  # configure accepts only linux-gnu host systems; the backend is the same for bionic (patched)
  # prototype files (libc.so.conf, syscalls.conf, ...) are read from <datadir>/ltrace = $ALTDIR/share/ltrace
  # C++ demangling (-C) from the NDK's static libc++abi, not libc++_shared.so
  ac_cv_host=aarch64-unknown-linux-gnu ac_cv_lib_supcpp___cxa_demangle=no ac_cv_lib_stdcpp___cxa_demangle=yes \
    configure_std --datadir=/system/etc/android-linux-tools/share \
    --sysconfdir=/system/etc/android-linux-tools/etc --with-libelf="$DEPROOT" --without-libunwind \
    --without-elfutils --disable-werror LIBS="-lz"
  make -j"$JOBS" libstdcxx_LIBS=-l:libc++abi.a
  install_bin ltrace ltrace
  local d="$B/destdir/$NAME"
  rm -rf "$d"
  make DESTDIR="$d" install-dist_pkgdataDATA
  mkdir -p "$OUT/data/rt/ltrace/share"
  rm -rf "$OUT/data/rt/ltrace/share/ltrace"
  cp -a "$d/system/etc/android-linux-tools/share/ltrace" "$OUT/data/rt/ltrace/share/ltrace"
}
