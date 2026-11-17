# tealdeer (tldr): Rust, built with cargo against Cargo.lock; the linker is the NDK clang at API $API. The English
# tldr-pages of a pinned tldr-pages commit are shipped in $ALTDIR/share/tldr (tealdeer's cache layout), so
# `tldr <command>` works offline without a first `tldr --update` (patch 0001).
VERSION=1.9.1
URL=https://github.com/tealdeer-rs/tealdeer/archive/refs/tags/v$VERSION.tar.gz
TARBALL=tealdeer-$VERSION.tar.gz
SHA256=78e7dbfcc2c8975c143a9746b073a3af875cdee72819bc383fbd411bae2c553c
CHECKSUM_SOURCE="tag v$VERSION -> commit 993a8e0232ef42c4d9935ff5598796b6e98bf213 (GitHub-verified signature on the commit); GitHub tag archive, sha256 recorded at pin time; crates verified by cargo against the checksums in Cargo.lock; tldr-pages: GitHub archive of commit 1d22cad212727e60367d34448220134af98e82b5 (GitHub-verified signature on the commit), sha256 recorded at pin time"
# tealdeer: MIT OR Apache-2.0; the tldr-pages: CC-BY-4.0
LICENSE="(MIT OR Apache-2.0) AND CC-BY-4.0"
# --update downloads the pages over HTTPS (host names through getaddrinfo): system libc for netd DNS; Rust's std
# for this target links libc.so/libdl.so anyway. Every crate is linked statically.
LINKAGE=dynamic
EXTRA_SRCS=(
  "https://github.com/tldr-pages/tldr/archive/1d22cad212727e60367d34448220134af98e82b5.tar.gz e09ea6af9f5bf505b42ffd2f5243892b9639c96e0241744c2bb0ecce133d6ec7"
)
build() {
  # Rust: toolchain from the builder image; crates pinned by Cargo.lock (--locked), kept in $DL/cargo-home.
  # A build with a complete crate cache runs offline; otherwise the missing crates are downloaded from crates.io
  # and checked against the Cargo.lock checksums.
  export CARGO_HOME="$DL/cargo-home" CARGO_TARGET_DIR="$PWD/target" CARGO_INCREMENTAL=0 CARGO_TERM_COLOR=never
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC" CC_aarch64_linux_android="$CC" AR_aarch64_linux_android="$AR"
  export RUSTFLAGS="--remap-path-prefix=$CARGO_HOME=/cargo --remap-path-prefix=$PWD=/usr/src/$NAME -C link-arg=-Wl,--build-id=sha1 -C strip=none"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS cargo fetch --locked --offline --target aarch64-linux-android ||
    env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS cargo fetch --locked --target aarch64-linux-android
  # TLS for --update: rustls (ring) with the bundled WebPKI (Mozilla) roots only. The default features also enable
  # rustls-platform-verifier, which on Android needs a JVM context that a command-line program does not have.
  # CFLAGS/LDFLAGS of env.sh are for the NDK clang; build scripts run on the builder: not passed to cargo
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS \
    cargo build -j "$JOBS" --release --locked --offline --target aarch64-linux-android --no-default-features \
    --features rustls-with-webpki-roots
  install_bin target/aarch64-linux-android/release/tldr tldr
  alt_crate_licenses
  alt_rust_std_licenses
  # the English pages (pages/<platform>/*.md of the tldr-pages repository) as tealdeer's pages.en
  local t="$OUT/data/rt/tealdeer/share/tldr" p=tldr-1d22cad212727e60367d34448220134af98e82b5
  tar -xzf "$DL/1d22cad212727e60367d34448220134af98e82b5.tar.gz" "$p/pages" "$p/LICENSE.md"
  rm -rf "$OUT/data/rt/tealdeer"
  mkdir -p "$t"
  cp -a "$p/pages" "$t/pages.en"
  [ -f "$t/pages.en/common/tar.md" ] && [ -f "$t/pages.en/android/pm.md" ]
  [ -z "$(find "$OUT/data/rt/tealdeer" ! -type f ! -type d)" ]
  cp "$p/LICENSE.md" LICENSE.tldr-pages.md
  rm -rf "$p"
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
    --no-default-features --features rustls-with-webpki-roots -e normal,build --prefix none --format '{p}|{l}' | grep -v "($PWD" | sed -e 's/ (proc-macro)//' -e 's/ (\*)$//' | sort -u > alt-crates.txt
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
