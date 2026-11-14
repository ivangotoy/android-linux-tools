# fd: Rust, built with cargo against Cargo.lock; the linker is the NDK clang at API $API
VERSION=10.5.2
URL=https://github.com/sharkdp/fd/archive/refs/tags/v$VERSION.tar.gz
TARBALL=fd-$VERSION.tar.gz
SHA256=8991b6504cac33c00528050622dfe3f2a0db1be1a6faf99f69b46d1a8f737dc5
CHECKSUM_SOURCE="tag v$VERSION -> commit b2a287b3993768e0ec52f0852916917f23fb2a38 (unsigned); GitHub tag archive, sha256 recorded at pin time; crates verified by cargo against the checksums in Cargo.lock"
LICENSE="MIT OR Apache-2.0"
# PIE against the system libc/libm/libdl (Rust's std for aarch64-linux-android); every crate is linked statically
LINKAGE=dynamic
build() {
  # Rust: toolchain from the builder image; crates pinned by Cargo.lock (--locked), kept in $DL/cargo-home.
  # A build with a complete crate cache runs offline; otherwise the missing crates are downloaded from crates.io
  # and checked against the Cargo.lock checksums.
  export CARGO_HOME="$DL/cargo-home" CARGO_TARGET_DIR="$PWD/target" CARGO_INCREMENTAL=0 CARGO_TERM_COLOR=never
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC" CC_aarch64_linux_android="$CC" AR_aarch64_linux_android="$AR"
  export RUSTFLAGS="--remap-path-prefix=$CARGO_HOME=/cargo --remap-path-prefix=$PWD=/usr/src/$NAME -C link-arg=-Wl,--build-id=sha1 -C strip=none"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS cargo fetch --locked --offline --target aarch64-linux-android ||
    env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS cargo fetch --locked --target aarch64-linux-android
  # default features without use-jemalloc: the bundled jemalloc is not built for bionic (the system allocator is used)
  # CFLAGS/LDFLAGS of env.sh are for the NDK clang; build scripts run on the builder: not passed to cargo
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    cargo build -j "$JOBS" --release --locked --offline --target aarch64-linux-android --no-default-features --features completions
  install_bin target/aarch64-linux-android/release/fd fd
  alt_crate_licenses
  alt_rust_std_licenses
}
# Rust's standard library is linked into the program too (cargo tree does not list it): its notice file and
# the MIT and Apache-2.0 texts from the toolchain of the builder image
alt_rust_std_licenses() {
  local d
  d="$(rustc --print sysroot)/share/doc/rust"
  cp "$d/COPYRIGHT-library.html" LICENSE.rust-std-COPYRIGHT-library.html
  cp "$d/licenses/MIT.txt" LICENSE.rust-std-MIT.txt
  cp "$d/licenses/Apache-2.0.txt" LICENSE.rust-std-Apache-2.0.txt
}
# licences of every crate linked into the program: cargo tree of the target's normal and build dependencies
alt_crate_licenses() {
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS cargo tree --locked --offline --target aarch64-linux-android \
    --no-default-features --features completions -e normal,build --prefix none --format '{p}|{l}' | grep -v "($PWD" | sed -e 's/ (proc-macro)//' -e 's/ (\*)$//' | sort -u > alt-crates.txt
  local n v l d f
  echo 'Rust crates linked into this program (name version licence):' > LICENSE.crates.txt
  while IFS='|' read -r n l; do
    v=${n#* v}; n=${n%% *}
    echo "$n $v $l" >> LICENSE.crates.txt
    for d in "$CARGO_HOME"/registry/src/*/"$n-$v"; do
      for f in $(cd "$d" && find . -maxdepth 1 -type f \( -iname 'licen[cs]e*' -o -iname 'copying*' -o -iname 'unlicense*' -o -iname 'copyright*' -o -iname 'notice*' \) | sed 's|^\./||' | sort); do
        cp "$d/$f" "LICENSE.crate-$n-$v-$f"
      done
    done
  done < alt-crates.txt
  [ "$(wc -l < alt-crates.txt)" -gt 5 ]
}
