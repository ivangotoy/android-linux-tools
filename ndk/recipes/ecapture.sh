# eCapture: SSL/TLS plaintext capture without a CA certificate (eBPF uprobes), Go + cgo (libpcap).
# As upstream's Android release (.github/workflows/release.yml, builder/Makefile.release: ANDROID=1 make with
# KERN_HEADERS = a configured kernel source tree): both BPF object sets are embedded, the CO-RE objects (from
# kern/bpf/arm64/vmlinux.h in the source) and the non-CO-RE objects (from those kernel headers). At run time
# (--btf=0, the default) internal/probe/bytecode/selector.go picks CO-RE when the kernel has BTF, else non-CO-RE.
# Differences: cgo and the BPF objects use the NDK clang, and the program is linked fully static against bionic
# (upstream: glibc static PIE).
VERSION=2.10.0
URL=https://github.com/gojue/ecapture/archive/refs/tags/v$VERSION.tar.gz
TARBALL=ecapture-$VERSION.tar.gz
SHA256=9c6213d37cd7961a454fa7b011695a85080df38cc5c395212aff68072fed9895
# kernel source for the headers of the non-CO-RE BPF objects (configured with the arm64 defconfig)
LINUX_VERSION=6.18.62
EXTRA_SRCS=("https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$LINUX_VERSION.tar.xz 490a7aedf1b355c565d3a6c05333ccccb5da82064eca46b590448a7099d7d651")
CHECKSUM_SOURCE="tag v$VERSION -> commit eb363adcaeb094eb82c943f60297a2629d14420f (GitHub-verified signature); GitHub tag archive, sha256 recorded at pin time; Go modules verified against go.sum (and sum.golang.org when fetched); linux-$LINUX_VERSION.tar.xz: kernel.org detached signature linux-$LINUX_VERSION.tar.sign (over the uncompressed tar), Greg Kroah-Hartman key 647F28654894E3BD457199BE38DBBDC86092693E"
LICENSE="Apache-2.0 AND (MIT OR GPL-2.0-only) AND BSD-3-Clause AND MIT AND MPL-2.0 AND LicenseRef-ecapture_decryptor"
DEPS="libpcap"
build() {
  local top=$PWD
  # Go: toolchain from the builder image (GOTOOLCHAIN=local); modules pinned by go.sum, kept in $DL/go-mod.
  # A build with a complete module cache runs offline (GOPROXY=off); otherwise the missing modules are fetched
  # from proxy.golang.org and checked against go.sum and sum.golang.org.
  export GOENV=off GOFLAGS=-mod=readonly GOMODCACHE="$DL/go-mod" GOPATH="$B/tmp/gopath-$NAME" GOCACHE="$B/tmp/gocache-$NAME"
  export GOSUMDB=sum.golang.org GOPROXY=off
  rm -rf "$GOCACHE" "$GOPATH"
  go mod download || GOPROXY=https://proxy.golang.org go mod download
  go mod verify

  # configured kernel headers (arm64 defconfig, make prepare with the NDK LLVM tools; host tools with gcc)
  rm -rf alt-linux
  mkdir alt-linux
  tar -xf "$DL/linux-$LINUX_VERSION.tar.xz" -C alt-linux --strip-components=1 --no-same-owner
  make -C alt-linux ARCH=arm64 LLVM=1 HOSTCC=gcc defconfig
  make -C alt-linux -j"$JOBS" ARCH=arm64 LLVM=1 HOSTCC=gcc prepare

  # BPF compiler wrappers: clang with the build directory mapped out of the BTF line info; llc (not in the NDK)
  # as clang compiling LLVM IR from stdin for the BPF target (-O2, llc's default)
  mkdir -p alt-bin
  printf '%s\n' '#!/bin/sh' "exec clang -ffile-prefix-map=$B/src=/usr/src \"\$@\"" > alt-bin/ecap-clang
  printf '%s\n' '#!/bin/sh' 'out=' 'while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift ;; esac; shift; done' \
    "exec clang --target=bpf -O2 -Wno-override-module -ffile-prefix-map=$B/src=/usr/src -c -x ir - -o \"\$out\"" > alt-bin/llc
  chmod +x alt-bin/ecap-clang alt-bin/llc
  export PATH="$top/alt-bin:$PATH"

  # libpcap from the libpcap recipe in place of the submodule build (lib/libpcap is not in the tag archive)
  mkdir -p .build/ecap_android-arm64/libpcap
  cp "$DEPROOT/lib/libpcap.a" .build/ecap_android-arm64/libpcap/libpcap.a
  # CO-RE and non-CO-RE BPF objects for the Android target set and their go-bindata asset (upstream's `assets`). CLANG_VERSION: the NDK clang
  # banner does not parse in variables.mk; KERNEL_HEADER_GEN: the headers are prepared above; bpftool is not used
  # for arm64 (kern/bpf/arm64/vmlinux.h is in the source)
  make ANDROID=1 TARGET_ARCH=arm64 KERN_HEADERS="$top/alt-linux" KERNEL_HEADER_GEN=true KERN_RELEASE="$LINUX_VERSION" \
    CMD_CLANG=ecap-clang CMD_LLC="$top/alt-bin/llc" CMD_STRIP=llvm-strip CMD_BPFTOOL=true CMD_CC="$CC" CMD_AR="$AR" \
    CLANG_VERSION=21 SNAPSHOT_VERSION="v$VERSION" assets

  # the program: upstream's gobuild (functions.mk) for the `build` target (ByteCodeFiles=all; the version suffix is
  # the kernel release of the headers instead of the build host's uname -r), static non-PIE against bionic.
  # runtime/cgo links -lpthread (in bionic's libc: an empty archive) and, for __ANDROID__, logs fatal errors with
  # __android_log_vprint (liblog has no static library: a no-op stub; the message is printed to stderr first)
  mkdir -p alt-compat
  $AR rc alt-compat/libpthread.a
  printf '%s\n' '#include <stdarg.h>' \
    'int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap);' \
    'int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap) {' \
    '  (void) prio; (void) tag; (void) fmt; (void) ap; return 0;' '}' > alt-compat/log_stub.c
  $CC $CFLAGS -c alt-compat/log_stub.c -o alt-compat/log_stub.o
  $AR rc alt-compat/liblog_stub.a alt-compat/log_stub.o
  CGO_ENABLED=1 CGO_CFLAGS="$CFLAGS $CPPFLAGS" CGO_LDFLAGS="-L$DEPROOT/lib -L$top/alt-compat -lpcap -llog_stub" \
  GOOS=linux GOARCH=arm64 CXX="$CXX" \
    go build -trimpath -buildmode=exe -mod=readonly -tags 'ecap_android,netgo,ebpfassets,dynamic' \
    -ldflags "-w -s -X 'github.com/gojue/ecapture/v2/cli/cmd.GitVersion=ecap_android_arm64:v$VERSION:$LINUX_VERSION' -X 'github.com/gojue/ecapture/v2/internal/config.ByteCodeFiles=all' -linkmode=external -extld=$CC -extldflags '$LDFLAGS'" \
    -o ecapture .
  install_bin ecapture ecapture

  # licences of every linked Go module and of the Go toolchain (runtime and standard library); listed before any
  # LICENSE.* file is added to the package directory
  local p v d f
  CGO_ENABLED=1 GOOS=linux GOARCH=arm64 go list -deps -tags 'ecap_android,netgo,ebpfassets,dynamic' \
    -f '{{with .Module}}{{if not .Main}}{{.Path}} {{.Version}} {{.Dir}}{{end}}{{end}}' . | sort -u > alt-go-modules.txt
  cp "$(go env GOROOT)/LICENSE" LICENSE.golang-toolchain
  while read -r p v d; do
    for f in $(cd "$d" && find . -maxdepth 1 -type f \( -iname 'licen[cs]e*' -o -iname 'copying*' -o -iname 'copyright*' -o -iname 'notice*' \) | sed 's|^\./||' | sort); do
      cp "$d/$f" "LICENSE.go-$(echo "$p" | tr '/' '_')-$f"
    done
  done < alt-go-modules.txt
  # the kernel headers' licence (GPL-2.0 with the syscall note) for the BPF objects built from them
  cp alt-linux/COPYING LICENSE.linux-COPYING
}
