# Protocol Buffers C++ runtime (libprotobuf) for android-tools, and a native protoc of the same version that
# generates its sources. 3.21.12 is the last release line without the abseil dependency.
VERSION=3.21.12
URL=https://github.com/protocolbuffers/protobuf/releases/download/v21.12/protobuf-cpp-$VERSION.tar.gz
SHA256=4eab9b524aa5913c6fffb20b2a8abf5ef7f95a80bc0701f3a6dbb4c607f73460
CHECKSUM_SOURCE="no upstream checksum or signature; release asset of tag v21.12 (commit f0dc78d7e6e331b8c6bb2d5283e06aa26883ca7c), sha256 recorded at pin time"
LICENSE=BSD-3-Clause
build() {
  # 1. native protoc with the builder's gcc/g++ (runs during the android-tools build): $PKGDIR/hostbin/protoc
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS CC=gcc CXX=g++ \
  cmake -S . -B build-host -G Ninja -DCMAKE_BUILD_TYPE=Release -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_SHARED_LIBS=OFF -Dprotobuf_WITH_ZLIB=OFF
  ninja -C build-host -j"$JOBS" protoc
  # 2. libprotobuf for the target. On Android protobuf logs through liblog (__android_log_write), which has no
  #    static library and would add a liblog.so dependency: log to stderr as on other systems
  sed -i 's/^#if defined(__ANDROID__)$/#if defined(PROTOBUF_USE_ANDROID_LOG)/' src/google/protobuf/stubs/common.cc
  ! grep -n '__ANDROID__' src/google/protobuf/stubs/common.cc
  sed -i '/^if(\${CMAKE_SYSTEM_NAME} STREQUAL "Android")$/,/^endif()$/d' cmake/libprotobuf.cmake cmake/libprotobuf-lite.cmake
  ! grep -n 'Android' cmake/libprotobuf.cmake cmake/libprotobuf-lite.cmake
  cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
    -Dprotobuf_BUILD_TESTS=OFF -Dprotobuf_BUILD_SHARED_LIBS=OFF -Dprotobuf_BUILD_PROTOC_BINARIES=OFF \
    -Dprotobuf_WITH_ZLIB=OFF
  cmake --build build -j"$JOBS"
  rm -rf "$B/destdir/$NAME"
  DESTDIR="$B/destdir/$NAME" cmake --install build
  mkdir -p "$PKGDIR/hostbin"
  cp -a "$B/destdir/$NAME/usr/include" "$B/destdir/$NAME/usr/lib" "$PKGDIR/"
  cp build-host/protoc "$PKGDIR/hostbin/protoc"
}
