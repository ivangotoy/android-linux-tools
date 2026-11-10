# bcc libbpf-tools: the CO-RE (BPF compile once, run everywhere) tools in libbpf-tools/ of the bcc release that the
# bcc recipe pins (same tarball), built with upstream's Makefile: BPF objects by the NDK clang (-target bpf) against
# libbpf-tools/arm64/vmlinux.h, skeletons by a native bootstrap bpftool built from the source the bpftool recipe
# pins, user space linked statically with the libbpf of the tarball (src/cc/libbpf), libelf of the elfutils recipe
# and the NDK zlib. argp (bionic has none) from argp-standalone as in the elfutils recipe.
VERSION=0.37.0
URL=https://github.com/iovisor/bcc/releases/download/v$VERSION/bcc-src-with-submodule-$VERSION.tar.gz
SRCDIR=bcc-src-with-submodule-$VERSION/bcc
SHA256=7734b780202b22dff335780b506b56833ec6cf7435e03b1346d5bf644b4e1f95
ARGP_VERSION=1.5.0
BPFTOOL_VERSION=7.8.1
EXTRA_SRCS=("https://github.com/argp-standalone/argp-standalone/archive/refs/tags/$ARGP_VERSION.tar.gz c29eae929dfebd575c38174f2c8c315766092cec99a8f987569d0cad3c6d64f6"
            "https://github.com/libbpf/bpftool/releases/download/v$BPFTOOL_VERSION/bpftool-libbpf-v$BPFTOOL_VERSION-sources.tar.gz fed76b7acb54d810cc3982eb6394726010114977542fd146695887a7d904b60c")
CHECKSUM_SOURCE="no upstream checksum or signature; sha256 equals the GitHub release asset digest; argp-standalone $ARGP_VERSION and the bpftool $BPFTOOL_VERSION sources: the pins of the elfutils and bpftool recipes"
LICENSE="(LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0"
DEPS="elfutils"
# the tools of upstream's APPS list (libbpf-tools/Makefile); every one must build
ALT_APPS="bashreadline bindsnoop biolatency biopattern biosnoop biostacks biotop bitesize cachestat capable cpudist
  cpufreq drsnoop execsnoop exitsnoop filelife filetop fsdist fsslower funclatency futexctn gethostlatency hardirqs
  javagc klockstat ksnoop llcstat mdflush memleak mountsnoop numamove offcputime oomkill opensnoop profile readahead
  runqlat runqlen runqslower sigsnoop slabratetop softirqs solisten statsnoop syncsnoop syscount tcpconnect tcpconnlat
  tcplife tcppktlat tcprtt tcpstates tcpsynbl tcptop tcptracer vfsstat wakeuptime"
build() {
  cd libbpf-tools
  local top=$PWD dep=$PWD/alt-deps a
  mkdir -p "$dep/include" "$dep/lib"
  rm -rf "argp-standalone-$ARGP_VERSION" alt-bpftool
  tar -xf "$DL/$ARGP_VERSION.tar.gz" --no-same-owner
  (cd "argp-standalone-$ARGP_VERSION" && autoreconf -fi && configure_std && make -j"$JOBS" libargp.a)
  cp "argp-standalone-$ARGP_VERSION/libargp.a" "$dep/lib/"
  cp "argp-standalone-$ARGP_VERSION/argp.h" "$dep/include/"
  sed -n '1,19p' "argp-standalone-$ARGP_VERSION/argp-parse.c" > ../LICENSE.argp-standalone
  # native bootstrap bpftool (gen skeleton only) with the builder's gcc; the tarball's libbpf-tools/bpftool
  # submodule lacks its own libbpf submodule, so the bpftool recipe's source release is used
  mkdir -p alt-bpftool .output/bpftool
  tar -xf "$DL/bpftool-libbpf-v$BPFTOOL_VERSION-sources.tar.gz" -C alt-bpftool --strip-components=1 --no-same-owner
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS make -j"$JOBS" -C alt-bpftool/src OUTPUT="$top/.output/bpftool/" \
    CC=gcc HOSTCC=gcc AR=ar LD=ld SKIP_CRYPTO=1 bootstrap
  # mountsnoop.c defines a stub strerrorname_np() for non-glibc; bionic has the function (API 35)
  sed -i 's/^#if !defined(__GLIBC__) || __GLIBC__ < 2/#if !defined(__BIONIC__) \&\& (!defined(__GLIBC__) || __GLIBC__ < 2/; /^#if !defined(__BIONIC__)/s/$/)/' mountsnoop.c
  grep -q '__BIONIC__' mountsnoop.c
  # libbpf (built by the Makefile from ../src/cc/libbpf) takes CFLAGS from the environment: headers of the sysroot
  export CFLAGS="$CFLAGS $CPPFLAGS -I$dep/include"
  # BPF objects: kernel UAPI headers of the NDK sysroot (the builder has no <asm/...> for arm64);
  # -ffile-prefix-map keeps the build directory out of the BTF line info
  make -j"$JOBS" V=1 ARCH=arm64 CC="$CC" CLANG=clang LLVM_STRIP=llvm-strip USE_BLAZESYM=0 \
    BPFTOOL="$top/.output/bpftool/bootstrap/bpftool" \
    BPFCFLAGS="-g -O2 -Wall -Werror=undef -ffile-prefix-map=$B/src=/usr/src -idirafter $SYSROOT/usr/include -idirafter $SYSROOT/usr/include/$TARGET" \
    EXTRA_CFLAGS="$CFLAGS -Wno-error" EXTRA_LDFLAGS="$LDFLAGS -L$dep/lib -largp" $ALT_APPS
  for a in $ALT_APPS; do install_bin "$a" "$a"; done
  # licences: bcc (LICENSE.txt in the source directory), the libbpf-tools sources (SPDX headers:
  # LGPL-2.1 OR BSD-2-Clause, texts from the bundled libbpf), bpftool for the generated skeleton code
  cp ../src/cc/libbpf/LICENSE.LGPL-2.1 ../LICENSE.libbpf-LGPL-2.1
  cp ../src/cc/libbpf/LICENSE.BSD-2-Clause ../LICENSE.libbpf-BSD-2-Clause
}
