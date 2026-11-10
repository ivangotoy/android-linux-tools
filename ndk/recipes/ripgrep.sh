# ripgrep (rg): Rust, built with cargo against Cargo.lock; the linker is the NDK clang at API $API
VERSION=15.2.0
URL=https://github.com/BurntSushi/ripgrep/archive/refs/tags/$VERSION.tar.gz
TARBALL=ripgrep-$VERSION.tar.gz
SHA256=7605249d3eb0d5f170e3414498e3344e26b1e7a147aec518b57090b80036a562
CHECKSUM_SOURCE="tag $VERSION -> commit e89fff89ac9af12e8d4ce9d5fd07beb408ca730f (GitHub-verified signature on the tag object); GitHub tag archive, sha256 recorded at pin time; crates verified by cargo against the checksums in Cargo.lock"
LICENSE="Unlicense OR MIT"
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
  # CFLAGS/LDFLAGS of env.sh are for the NDK clang; build scripts run on the builder: not passed to cargo
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    cargo build -j "$JOBS" --release --locked --offline --target aarch64-linux-android
  install_bin target/aarch64-linux-android/release/rg rg
  # the Unlicense text (the MIT text is LICENSE-MIT; COPYING explains the dual licence)
  cp UNLICENSE LICENSE.UNLICENSE
  alt_crate_licenses
}
# licences of every crate linked into the program: cargo tree of the target's normal and build dependencies
alt_crate_licenses() {
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS cargo tree --locked --offline --target aarch64-linux-android \
    -e normal,build --prefix none --format '{p}|{l}' | grep -v "($PWD" | sed -e 's/ (proc-macro)//' -e 's/ (\*)$//' | sort -u > alt-crates.txt
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
