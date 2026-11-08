VERSION=1.53.0
URL=https://dist.libuv.org/dist/v$VERSION/libuv-v$VERSION.tar.gz
SRCDIR=libuv-v$VERSION
SHA256=cb0d6dd2128d5a95bd242c6cc982a24fe608fa93da57b6b4ec763b0018c53e64
CHECKSUM_SOURCE="detached signature $URL.sign, Santiago Gimeno key 612F0EAD9401622379DF4402F28C3C8DA33C03BE"
LICENSE="MIT AND CC-BY-4.0"
build() {
  # src/unix/linux.c already disables io_uring for __ANDROID_API__ (seccomp) and statx below API 30
  cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
    -DLIBUV_BUILD_SHARED=OFF -DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF -DBUILD_TESTING=OFF
  cmake --build build -j"$JOBS"
  rm -rf "$B/destdir/$NAME"
  DESTDIR="$B/destdir/$NAME" cmake --install build
  mkdir -p "$PKGDIR/lib/pkgconfig"
  cp -a "$B/destdir/$NAME/usr/include" "$PKGDIR/"
  cp "$B/destdir/$NAME/usr/lib/libuv.a" "$PKGDIR/lib/"
  # static-only install has just libuv-static.pc; BIND asks pkg-config for "libuv"
  printf '%s\n' "prefix=/usr" 'libdir=${prefix}/lib' 'includedir=${prefix}/include' '' 'Name: libuv' \
    "Version: $VERSION" 'Description: multi-platform support library with a focus on asynchronous I/O.' \
    'Libs: -L${libdir} -luv' 'Libs.private: -ldl' 'Cflags: -I${includedir}' > "$PKGDIR/lib/pkgconfig/libuv.pc"
}
