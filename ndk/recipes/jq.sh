VERSION=1.8.2
URL=https://github.com/jqlang/jq/releases/download/jq-$VERSION/jq-$VERSION.tar.gz
SHA256=71b8d6e8f5fe81f6c6d0d110e3892251f6ce76ed095abd315e26e6e1193af3af
CHECKSUM_SOURCE="sha256sum.txt published in the GitHub release jq-$VERSION"
LICENSE=MIT
DEPS="oniguruma"
build() {
  configure_std --with-oniguruma="$DEPROOT" --disable-docs --disable-maintainer-mode --disable-valgrind
  # jq --build-configuration embeds the configure command line: write it without builder paths
  mkdir -p src
  ./config.status --config | sed -e "s|$DEPROOT|/usr|g" -e "s|$B/src|/usr/src|g" -e "s|$SYSROOT|/ndk-sysroot|g" \
    -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/^/"/' -e 's/$/"/' -e 's/^/#define JQ_CONFIG /' > src/config_opts.inc
  make -j"$JOBS" LDFLAGS="$LT_LDFLAGS"
  install_bin jq jq
}
