# fzf: command-line fuzzy finder (Go). Linked like the ecapture recipe: Go with cgo, external link by the NDK
# clang, fully static against bionic.
VERSION=0.75.0
URL=https://github.com/junegunn/fzf/archive/refs/tags/v$VERSION.tar.gz
TARBALL=fzf-$VERSION.tar.gz
SHA256=165f6e0c1b9ba082346233681e3f1d1374e37f9fd3c1d7b6dfe09659ab893faa
REVISION=c7bf2b8
CHECKSUM_SOURCE="tag v$VERSION -> commit c7bf2b8eea25952dd257a466c0afa72faae206fb (GitHub-verified signature on the tag object); GitHub tag archive, sha256 recorded at pin time; Go modules verified against go.sum (and sum.golang.org when fetched)"
LICENSE="MIT AND BSD-3-Clause AND Apache-2.0"
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
  # upstream's BUILD_FLAGS (Makefile): -trimpath, version and revision of the tag
  CGO_ENABLED=1 CGO_CFLAGS="$CFLAGS $CPPFLAGS" CGO_LDFLAGS="-L$top/alt-compat -llog_stub" \
  GOOS=linux GOARCH=arm64 CXX="$CXX" \
    go build -trimpath -buildmode=exe -mod=readonly -tags 'netgo,osusergo' \
    -ldflags "-w -s -X main.version=$VERSION -X main.revision=$REVISION -linkmode=external -extld=$CC -extldflags '$LDFLAGS'" \
    -o fzf-android .
  install_bin fzf-android fzf
  # licences of every linked Go module and of the Go toolchain (runtime and standard library)
  local p v d f
  CGO_ENABLED=1 GOOS=linux GOARCH=arm64 go list -deps -tags 'netgo,osusergo' \
    -f '{{with .Module}}{{if not .Main}}{{.Path}} {{.Version}} {{.Dir}}{{end}}{{end}}' . | sort -u > alt-go-modules.txt
  cp "$(go env GOROOT)/LICENSE" LICENSE.golang-toolchain
  while read -r p v d; do
    for f in $(cd "$d" && find . -maxdepth 1 -type f \( -iname 'licen[cs]e*' -o -iname 'copying*' -o -iname 'copyright*' -o -iname 'notice*' \) | sed 's|^\./||' | sort); do
      cp "$d/$f" "LICENSE.go-$(echo "$p" | tr '/' '_')-$f"
    done
  done < alt-go-modules.txt
}
