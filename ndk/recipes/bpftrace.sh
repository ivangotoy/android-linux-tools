# bpftrace with statically linked LLVM/clang (BPF target), bcc symbol helpers and the vendored libbpf
VERSION=0.27.1
URL=https://github.com/bpftrace/bpftrace/archive/refs/tags/v$VERSION.tar.gz
TARBALL=bpftrace-$VERSION.tar.gz
SHA256=52a923555b6e16fe13a285b6713637bfaab30a5efa60f44c03134bd832342012
# libbpf at the commit of bpftrace's libbpf submodule (GitHub tag archives omit submodules)
LIBBPF_COMMIT=85c0d575a447651bbeb8e2376eacd64c30dce9a6
EXTRA_SRCS=("https://github.com/libbpf/libbpf/archive/$LIBBPF_COMMIT.tar.gz 6afe4301effebd56f976847603f86b30cca07d2ac8f954c95778463ec79d4d3f")
CHECKSUM_SOURCE="tag v$VERSION -> commit 24e9fe60faffcbed50b44428067fcd9b03770584 (GitHub-verified signature); the tag archive equals the git tree of that commit; libbpf submodule commit $LIBBPF_COMMIT archive sha256 recorded at pin time"
LICENSE="Apache-2.0 AND (LGPL-2.1-only OR BSD-2-Clause)"
DEPS="llvm bcc cereal elfutils xz libpcap"
build() {
  rm -rf libbpf
  tar -xf "$DL/$LIBBPF_COMMIT.tar.gz" --no-same-owner
  mv "libbpf-$LIBBPF_COMMIT" libbpf
  for f in LICENSE LICENSE.BSD-2-Clause LICENSE.LGPL-2.1-only; do cp "libbpf/$f" "LICENSE.libbpf-${f#LICENSE.}"; done
  # the vendored libbpf is built by cmake/FindLibBpf.cmake with make (CC/CFLAGS from the environment):
  # static library only, headers from the private sysroot
  export BUILD_STATIC_ONLY=y CFLAGS="$CFLAGS $CPPFLAGS"
  cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/ndk/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-$API -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$CFLAGS" -DCMAKE_CXX_FLAGS="$CXXFLAGS $CPPFLAGS" -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS" \
    -DSTATIC_LINKING=ON -DBUILD_TESTING=OFF -DENABLE_MAN=OFF -DENABLE_SYSTEMD=OFF -DENABLE_SKB_OUTPUT=ON \
    -DUSE_SYSTEM_LIBBPF=OFF -DLLVM_DIR="$DEPROOT/lib/cmake/llvm" -DClang_DIR="$DEPROOT/lib/cmake/clang" \
    -DLIBBCC_INCLUDE_DIRS="$DEPROOT/include" -DLIBBCC_LIBRARIES="$DEPROOT/lib/libbcc-loader-static.a" \
    -DLIBBCC_BPF_LIBRARIES="$DEPROOT/lib/libbcc-loader-static.a" \
    -DLIBBCC_LOADER_LIBRARY_STATIC="$DEPROOT/lib/libbcc-loader-static.a" \
    -DLIBELF_INCLUDE_DIRS="$DEPROOT/include" -DLIBELF_LIBRARIES="$DEPROOT/lib/libelf.a" \
    -DLIBCEREAL_INCLUDE_DIRS="$DEPROOT/include" -DLIBLZMA_INCLUDE_DIRS="$DEPROOT/include" \
    -DLIBLZMA_LIBRARIES="$DEPROOT/lib/liblzma.a" \
    -DLIBPCAP_INCLUDE_DIRS="$DEPROOT/include" -DLIBPCAP_LIBRARIES="$DEPROOT/lib/libpcap.a"
  cmake --build build -j"$JOBS" --target bpftrace
  install_bin build/src/bpftrace bpftrace
}
