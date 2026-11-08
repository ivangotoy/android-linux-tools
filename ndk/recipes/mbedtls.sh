VERSION=3.6.7
URL=https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$VERSION/mbedtls-$VERSION.tar.bz2
SHA256=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6
CHECKSUM_SOURCE="sha256 published in the GitHub release mbedtls-$VERSION (mbedtls-$VERSION-sha256sum.txt)"
LICENSE="Apache-2.0 OR GPL-2.0-or-later"
build() {
  cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_INSTALL_PREFIX=/usr -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF \
    -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON -DMBEDTLS_FATAL_WARNINGS=OFF
  cmake --build build -j"$JOBS"
  rm -rf "$B/destdir/$NAME"
  DESTDIR="$B/destdir/$NAME" cmake --install build
  cp -a "$B/destdir/$NAME/usr/." "$DEPROOT/"
  sed -i "s|^prefix=.*|prefix=$DEPROOT|" "$DEPROOT"/lib/pkgconfig/mbed*.pc
}
