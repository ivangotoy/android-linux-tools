# brotli libraries (libbrotlicommon, libbrotlidec, libbrotlienc) for android-tools (adb sync compression)
VERSION=1.2.1
URL=https://github.com/google/brotli/archive/refs/tags/v$VERSION.tar.gz
TARBALL=brotli-$VERSION.tar.gz
SHA256=98d35d11a78dc453aebb7d10c3748f3f73ff78c8267c0dc697b8631f67bf7e8f
CHECKSUM_SOURCE="no upstream checksum or signature for the source; GitHub tag archive of v$VERSION (commit db24a98aed38a16de78cc05ca15cdd8dc2a0d92d), sha256 recorded at pin time"
LICENSE=MIT
build() {
  cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF -DBROTLI_DISABLE_TESTS=ON -DBROTLI_BUILD_TOOLS=OFF
  cmake --build build -j"$JOBS"
  rm -rf "$B/destdir/$NAME"
  DESTDIR="$B/destdir/$NAME" cmake --install build
  mkdir -p "$PKGDIR"
  cp -a "$B/destdir/$NAME/usr/include" "$B/destdir/$NAME/usr/lib" "$PKGDIR/"
}
