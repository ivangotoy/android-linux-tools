# lldb-server (debug server for a remote lldb: platform and gdbserver modes) from the LLVM release the llvm recipe
# pins. A separate build of the same source tarball: the llvm recipe (BPF-only static libraries for bpftrace) is
# unchanged. Only the lldb-server target and the libraries it links are compiled.
VERSION=23.1.5
URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-$VERSION/llvm-project-$VERSION.src.tar.xz
SRCDIR=llvm-project-$VERSION.src
SHA256=fb50b1eac93ddeb3aa8dab4cfe324dff74f4a9c2bdee6160c9e36188f8d06a6e
CHECKSUM_SOURCE="detached signature $URL.sig, LLVM release key FFB3368980F3E6BB5737145A316C56D064CACBA5 (Douglas Yung) from releases.llvm.org/release-keys.asc; sigstore bundle $URL.jsonl"
LICENSE="Apache-2.0 WITH LLVM-exception"
build() {
  local off="-DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_DOCS=OFF
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBPFM=OFF
    -DLLVM_ENABLE_BINDINGS=OFF -DCLANG_ENABLE_STATIC_ANALYZER=OFF -DCLANG_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_DOCS=OFF
    -DLLDB_ENABLE_PYTHON=OFF -DLLDB_ENABLE_LUA=OFF -DLLDB_ENABLE_LIBEDIT=OFF -DLLDB_ENABLE_CURSES=OFF -DLLDB_ENABLE_LZMA=OFF
    -DLLDB_ENABLE_LIBXML2=OFF -DLLDB_ENABLE_FBSDVMCORE=OFF -DLLDB_INCLUDE_TESTS=OFF"
  # 1. native tablegen tools (llvm-min-tblgen, llvm-tblgen, clang-tblgen, lldb-tblgen) with the builder's gcc/g++
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS CC=gcc CXX=g++ \
  cmake -S llvm -B build-lldb-host -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS="clang;lldb" \
    -DLLVM_TARGETS_TO_BUILD=AArch64 $off
  ninja -C build-lldb-host -j"$JOBS" llvm-min-tblgen llvm-tblgen clang-tblgen lldb-tblgen
  # 2. lldb-server for aarch64 Android, static (as the lldb-server of the NDK): the AArch64 target only
  cmake -S llvm -B build-lldb -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
    -DLLVM_NATIVE_TOOL_DIR="$PWD/build-lldb-host/bin" -DLLVM_HOST_TRIPLE=aarch64-unknown-linux-android$API \
    -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-android$API \
    -DLLVM_ENABLE_PROJECTS="clang;lldb" -DLLVM_TARGETS_TO_BUILD=AArch64 -DLLVM_ENABLE_PIC=ON \
    -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_ENABLE_PLUGINS=OFF -DCLANG_PLUGIN_SUPPORT=OFF -DLLVM_ENABLE_FFI=OFF \
    -DLLVM_ENABLE_CURL=OFF -DLLVM_ENABLE_TELEMETRY=OFF -DLLVM_INCLUDE_RUNTIMES=OFF -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_LINK_LLVM_DYLIB=OFF -DCLANG_LINK_CLANG_DYLIB=OFF -DLLVM_PARALLEL_LINK_JOBS=2 $off
  ninja -C build-lldb -j"$JOBS" lldb-server
  install_bin build-lldb/bin/lldb-server lldb-server
  cp lldb/LICENSE.TXT LICENSE.lldb.TXT
  cp clang/LICENSE.TXT LICENSE.clang.TXT
}
