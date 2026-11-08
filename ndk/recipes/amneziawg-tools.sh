VERSION=3.1.20260812
URL=https://github.com/amnezia-vpn/amneziawg-tools/archive/refs/tags/v$VERSION.tar.gz
TARBALL=amneziawg-tools-v$VERSION.tar.gz
SHA256=dbd8ce0748d835d18f30bb76720246b7bfc80bd09cd17c379b1c59f683a18493
CHECKSUM_SOURCE="no signed tarball or checksum upstream; GitHub tag archive of v$VERSION (commit ee0f0a9aa34ff0a0da4b3433b9512781cfe02843), sha256 recorded at pin time"
LICENSE=GPL-2.0-only
# awg resolves endpoint host names (getaddrinfo); awg-quick dlopen()s libbinder_ndk.so for the DNS resolver
LINKAGE=dynamic
build() {
  make -j"$JOBS" -C src wg PLATFORM=linux
  install_bin src/wg awg
  # awg-quick: upstream's Android variant (src/wg-quick/android.c, a "shell script written in C" that drives
  # ip/iptables/ndc and the netd DnsResolver over binder), built like wireguard-android/Termux build wg-quick
  $CC $CFLAGS $CPPFLAGS -std=gnu11 -D_GNU_SOURCE -o src/awg-quick src/wg-quick/android.c $LDFLAGS -ldl
  install_bin src/awg-quick awg-quick
}
