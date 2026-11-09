# dropbear (server, never started by the module), dbclient (also as ssh), dropbearkey, dropbearconvert, scp
VERSION=2026.94
URL=https://matt.ucc.asn.au/dropbear/releases/dropbear-$VERSION.tar.bz2
SHA256=e098034a843699200c8c977a991fff73159735bf795d5f72ef672c41a6b1ae81
CHECKSUM_SOURCE="detached signature $URL.asc, Dropbear SSH Release Signing key F7347EF2EE2E07A267628CA944931494F29C6773"
LICENSE="MIT AND BSD-3-Clause AND Unlicense AND LicenseRef-PublicDomain"
# dbclient and the server resolve host names (getaddrinfo/getnameinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  # Android: host keys, pid file and authorized_keys (patched default of -D, for every user) in
  # /data/local/dropbear; public-key authentication only (no shadow/crypt on Android); PATH of the
  # session = bionic's _PATH_DEFPATH (includes /system/bin); scp runs the module's dbclient
  cat > localoptions.h <<'H'
#define DSS_PRIV_FILENAME "/data/local/dropbear/dropbear_dss_host_key"
#define RSA_PRIV_FILENAME "/data/local/dropbear/dropbear_rsa_host_key"
#define ECDSA_PRIV_FILENAME "/data/local/dropbear/dropbear_ecdsa_host_key"
#define ED25519_PRIV_FILENAME "/data/local/dropbear/dropbear_ed25519_host_key"
#define DROPBEAR_PIDFILE "/data/local/dropbear/dropbear.pid"
#define DROPBEAR_SVR_PASSWORD_AUTH 0
#define DROPBEAR_SVR_PAM_AUTH 0
#define DROPBEAR_SVR_PUBKEY_AUTH 1
#define DROPBEAR_X11FWD 0
#define DO_MOTD 0
#define DROPBEAR_PATH_SSH_PROGRAM "/system/etc/android-linux-tools/libexec/dbclient"
#define DEFAULT_PATH "/product/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/apex/com.android.virt/bin:/system_ext/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin:/vendor/xbin"
#define DEFAULT_ROOT_PATH DEFAULT_PATH
H
  # --disable-static: dropbear's --enable-static (in configure_std) means fully static programs
  configure_std --disable-static --enable-bundled-libtom --disable-pam --disable-shadow --disable-lastlog --disable-utmp \
    --disable-utmpx --disable-wtmp --disable-wtmpx --disable-loginfunc --disable-pututline --disable-pututxline
  make -j"$JOBS" PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp"
  for p in dropbear dbclient dropbearkey dropbearconvert scp; do
    install_bin "$p" "$p"
  done
}
