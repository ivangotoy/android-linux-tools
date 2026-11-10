# android-tools: adb, fastboot, simg2img, img2simg, lpunpack, lpmake from the AOSP platform-tools sources in the
# CMake packaging of nmeum/android-tools (vendored AOSP trees, BoringSSL, fmt and libusb in the release tarball)
VERSION=37.0.0p1
URL=https://github.com/nmeum/android-tools/releases/download/$VERSION/android-tools-$VERSION.tar.xz
SHA256=2c6de1abe16b211c7d9f59276217e14fd9e0e18b20e331d3c84358f5dffd576e
# googletest: only the header gtest/gtest_prod.h (FRIEND_TEST declarations in AOSP headers); nothing is linked
GTEST_VERSION=1.17.0
EXTRA_SRCS=("https://github.com/google/googletest/releases/download/v$GTEST_VERSION/googletest-$GTEST_VERSION.tar.gz 65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c")
CHECKSUM_SOURCE="no upstream signature; sha256 equals the GitHub release asset digest (tag $VERSION -> commit fc6d1ecca7fb40746f58699c566b25dac902f44c) and the pin of termux-packages packages/android-tools/build.sh; googletest $GTEST_VERSION: GitHub release asset, no upstream signature, sha256 recorded at pin time"
LICENSE="Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT AND OpenSSL AND LGPL-2.1-or-later"
DEPS="protobuf brotli pcre2 lz4 zstd"
# adb resolves host names (adb connect): system libc for netd DNS; every library is linked statically
LINKAGE=dynamic
build() {
  rm -rf alt-gtest
  mkdir alt-gtest
  tar -xf "$DL/googletest-$GTEST_VERSION.tar.gz" -C alt-gtest --strip-components=1 --no-same-owner
  # INCFS_SUPPORT_DISABLED: libziparchive's SIGBUS handling for files on incremental-fs needs the platform's
  # incfs support library (incfs_support/signal_handling.h selects it for every bionic build otherwise)
  local inc="-I$PWD/alt-gtest/googletest/include -DINCFS_SUPPORT_DISABLED=1"
  # libusb, fmt and BoringSSL: the copies vendored in the release tarball; ANDROID_TOOLS_PATCH_VENDOR=OFF: the
  # tarball's vendored trees are already patched by upstream (it would run git)
  cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS $CPPFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS $inc" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
    -DCMAKE_FIND_ROOT_PATH="$DEPROOT" -DProtobuf_DIR="$DEPROOT/lib/cmake/protobuf" \
    -DProtobuf_PROTOC_EXECUTABLE="$DEPROOT/hostbin/protoc" -DPKG_CONFIG_EXECUTABLE=/usr/bin/pkgconf \
    -DANDROID_TOOLS_USE_BUNDLED_LIBUSB=ON -DANDROID_TOOLS_USE_BUNDLED_FMT=ON -DANDROID_TOOLS_PATCH_VENDOR=OFF
  local p d f
  cmake --build build -j"$JOBS" --target adb fastboot simg2img img2simg lpunpack lpmake
  for p in adb fastboot simg2img img2simg lpunpack lpmake; do install_bin "build/vendor/$p" "$p"; done
  # licences of the vendored trees linked into the programs (the top-level LICENSE is the packaging's)
  for d in adb avb boringssl core/fastboot core/libcutils core/libutils core/libsparse extras/ext4_utils fmtlib fs_mgr \
           libbase libusb libziparchive logging/liblog selinux; do
    for f in NOTICE LICENSE COPYING; do
      [ -f "vendor/$d/$f" ] && cp "vendor/$d/$f" "LICENSE.vendor-$(echo "$d" | tr '/' '_')-$f"
    done
  done
  ls LICENSE.vendor-adb-NOTICE LICENSE.vendor-boringssl-LICENSE LICENSE.vendor-libusb-COPYING LICENSE.vendor-fmtlib-LICENSE >/dev/null
  cp alt-gtest/LICENSE LICENSE.googletest
}
