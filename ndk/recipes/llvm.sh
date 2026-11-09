# LLVM + clang static libraries for bpftrace (BPF target only, no tools); host tablegen built first
VERSION=23.1.5
URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-$VERSION/llvm-project-$VERSION.src.tar.xz
SRCDIR=llvm-project-$VERSION.src
SHA256=fb50b1eac93ddeb3aa8dab4cfe324dff74f4a9c2bdee6160c9e36188f8d06a6e
CHECKSUM_SOURCE="detached signature $URL.sig, LLVM release key FFB3368980F3E6BB5737145A316C56D064CACBA5 (Douglas Yung) from releases.llvm.org/release-keys.asc; sigstore bundle $URL.jsonl"
LICENSE="Apache-2.0 WITH LLVM-exception"
build() {
  # 1. native tablegen tools (llvm-min-tblgen, llvm-tblgen, clang-tblgen) with the builder's gcc/g++
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS CC=gcc CXX=g++ \
  cmake -S llvm -B build-host -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang \
    -DLLVM_TARGETS_TO_BUILD=BPF -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBPFM=OFF -DCLANG_ENABLE_STATIC_ANALYZER=OFF
  ninja -C build-host -j"$JOBS" llvm-min-tblgen llvm-tblgen clang-tblgen
  # 2. aarch64 Android static libraries; bpftrace needs clang (Driver, Frontend, CodeGen, libclang C API)
  #    and the LLVM BPF backend only (src/ast/passes/codegen_llvm.cpp initialises BPF alone).
  #    llvm/CMakeLists.txt defaults LLVM_DEFAULT_TARGET_TRIPLE to the host triple only when the native
  #    backend is built; with BPF alone it is empty and libclang (bpftrace's ClangParser, no -target) and
  #    the clang driver (clang_build.cpp) fail with "unknown target triple 'unknown'": set it to the host.
  cmake -S llvm -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" -DCMAKE_INSTALL_PREFIX=/usr \
    -DLLVM_NATIVE_TOOL_DIR="$PWD/build-host/bin" -DLLVM_HOST_TRIPLE=aarch64-unknown-linux-android$API \
    -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-android$API \
    -DLLVM_ENABLE_PROJECTS=clang -DLLVM_TARGETS_TO_BUILD=BPF -DLLVM_ENABLE_PIC=ON \
    -DLIBCLANG_BUILD_STATIC=ON -DLLVM_ENABLE_RTTI=ON -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_BUILD_TOOLS=OFF -DLLVM_BUILD_UTILS=OFF -DLLVM_INSTALL_UTILS=OFF -DCLANG_BUILD_TOOLS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_DOCS=OFF -DLLVM_ENABLE_BINDINGS=OFF -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DCLANG_ENABLE_STATIC_ANALYZER=OFF -DCLANG_ENABLE_OBJC_REWRITER=OFF -DCLANG_PLUGIN_SUPPORT=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBPFM=OFF -DLLVM_ENABLE_FFI=OFF -DLLVM_ENABLE_CURL=OFF \
    -DLLVM_ENABLE_TELEMETRY=OFF -DLLVM_INCLUDE_RUNTIMES=OFF -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_LINK_LLVM_DYLIB=OFF -DCLANG_LINK_CLANG_DYLIB=OFF -DLLVM_PARALLEL_LINK_JOBS=2
  ninja -C build -j"$JOBS"
  rm -rf "$B/destdir/$NAME"
  DESTDIR="$B/destdir/$NAME" cmake --install build
  mkdir -p "$PKGDIR"
  cp -a "$B/destdir/$NAME/usr/." "$PKGDIR/"
}
