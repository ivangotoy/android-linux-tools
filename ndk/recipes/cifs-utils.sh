VERSION=7.9
URL=https://download.samba.org/pub/linux-cifs/cifs-utils/cifs-utils-$VERSION.tar.bz2
SHA256=9f3750f402520b15c2c8eb52fd485df6ea77e5e66fe5e39ce8ac4386c32c0296
CHECKSUM_SOURCE="detached signature $URL.asc, cifs-utils Distribution Verification Key C699981A31F338706C817650DF5BA9D30642D5A0"
LICENSE=GPL-3.0-or-later
DEPS="talloc libcap"
# mount.cifs resolves the server name (getaddrinfo): system libc for netd DNS; talloc/libcap static
LINKAGE=dynamic
build() {
  # addmntent()/getpass() for bionic (android_compat.c from the patch); bionic has res_query in libc, no libresolv
  mkdir -p compat
  $CC $CFLAGS $CPPFLAGS -c android_compat.c -o compat/android_compat.o
  $AR rcs compat/libandroidcompat.a compat/android_compat.o
  $AR rcs compat/libresolv.a
  LIBS="-L$PWD/compat -landroidcompat" ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes \
  LDFLAGS="$LDFLAGS -L$PWD/compat" ROOTSBINDIR=/usr/sbin \
    configure_std --disable-cifsupcall --disable-cifscreds --disable-cifsidmap --disable-cifsacl \
    --disable-smbinfo --disable-pythontools --disable-pam --disable-systemd --disable-man --with-libcap=yes
  make -j"$JOBS" mount.cifs
  install_bin mount.cifs mount.cifs
}
