# libcrypto/libssl (static) for BIND (dig, host); curl keeps mbedTLS
VERSION=3.5.9
URL=https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz
SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
CHECKSUM_SOURCE="detached signature $URL.asc, OpenSSL key C46ED3F2CBEFDA1FDAADA44264ED7B1DCCE71CB2; also $URL.sha256"
LICENSE=Apache-2.0
build() {
  # OPENSSLDIR: default CA file is <dir>/cert.pem = the module's Mozilla bundle (dig +tls verification)
  env -u CFLAGS -u CXXFLAGS -u LDFLAGS ANDROID_NDK_ROOT=/opt/ndk PATH="$TC/bin:$PATH" CC=clang \
    ./Configure android-arm64 -D__ANDROID_API__=$API --prefix=/usr --libdir=lib \
    --openssldir=/system/etc/android-linux-tools/etc/ssl \
    no-shared no-module no-engine no-dso no-tests no-docs no-apps no-ui-console no-ssl3 no-comp \
    $CFLAGS
  # crypto/buildinf.h would embed the full compiler command line (including the build paths of
  # -ffile-prefix-map); generate it with a fixed description instead
  make crypto/buildinf.h
  perl util/mkbuildinf.pl "clang (Android NDK, aarch64-linux-android$API)" android-arm64 > crypto/buildinf.h
  make -j"$JOBS" build_libs
  install_lib install_dev
  rm -rf "$PKGDIR/lib/cmake"
}
