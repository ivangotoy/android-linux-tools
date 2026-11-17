# mosh: mosh-server and mosh-client (the Perl front end "mosh" is not shipped: no Perl in the module)
VERSION=1.4.0
URL=https://github.com/mobile-shell/mosh/releases/download/mosh-$VERSION/mosh-$VERSION.tar.gz
SHA256=872e4b134e5df29c8933dff12350785054d2fd2839b5ae6b5587b14db1465ddd
CHECKSUM_SOURCE="no upstream checksum or signature; GitHub release asset, sha256 recorded at pin time (equal to the pin of Termux packages/mosh)"
LICENSE=GPL-3.0-or-later
DEPS="protobuf ncurses openssl"
build() {
  # protoc: the native one of the protobuf recipe. The protobuf .pc carries absolute /usr paths: flags given here.
  # Crypto: AES-OCB from OpenSSL 3 (EVP). Static: mosh-client and mosh-server take numeric addresses only
  # (getaddrinfo with AI_NUMERICHOST), so no DNS through netd is needed.
  configure_std --with-crypto-library=openssl-with-openssl-ocb --without-utempter \
    --disable-hardening PROTOC="$DEPROOT/hostbin/protoc" \
    protobuf_CFLAGS="-I$DEPROOT/include" protobuf_LIBS="-L$DEPROOT/lib -lprotobuf" \
    LDFLAGS="$LDFLAGS -static-libstdc++"
  make -j"$JOBS"
  install_bin src/frontend/mosh-server mosh-server
  install_bin src/frontend/mosh-client mosh-client
}
