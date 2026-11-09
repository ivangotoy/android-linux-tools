VERSION=6.17
URL=https://www.kernel.org/pub/software/network/iw/iw-$VERSION.tar.xz
SHA256=7d182e498289ab39b257da6780d562e415377107f50358ee5b55b8cfe40b1e33
CHECKSUM_SOURCE="kernel.org detached signature https://www.kernel.org/pub/software/network/iw/iw-$VERSION.tar.sign (over the uncompressed tar), Johannes Berg key C0EBC440F6DA091C884D8532E0F373F37BF9099A"
LICENSE=ISC
DEPS="libnl"
build() {
  # iw finds its command table through __start___cmd/__stop___cmd; with --gc-sections lld (start-stop-gc
  # by default) would drop the __cmd section, so keep sections referenced by __start_/__stop_
  make -j"$JOBS" CC="$CC" PKG_CONFIG="$PKG_CONFIG" LDFLAGS="$LDFLAGS -Wl,-z,nostart-stop-gc" V=1
  install_bin iw iw
}
