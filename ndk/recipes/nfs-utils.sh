# nfs-utils: mount.nfs only (NFS client mount helper; also mount.nfs4, umount.nfs, umount.nfs4 by argv[0]).
# No server daemons, no idmapd, no GSS.
VERSION=2.9.2
URL=https://www.kernel.org/pub/linux/utils/nfs-utils/$VERSION/nfs-utils-$VERSION.tar.xz
SHA256=e1dd8a9c95af15492065942cc3b52b1339ffd586baa2280ed86c9d3dc4097e8c
CHECKSUM_SOURCE="kernel.org sha256sums.asc in the same directory (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE=GPL-2.0-or-later
DEPS="libtirpc libnl libevent util-linux"
# mount.nfs resolves the server name (getaddrinfo): system libc for netd DNS; libtirpc and the helpers static
LINKAGE=dynamic
build() {
  # configure checks that mount.nfs does not need: libresolv's res_querydomain (libnfsidmap; bionic has the
  # resolver in libc: an empty libresolv.a) and getrpcbynumber() (in libtirpc, which the check does not link).
  # versionsort() (bionic has none) only orders nfs.conf.d-style drop-in files: alphasort()
  mkdir -p compat
  $AR rc compat/libresolv.a
  export LDFLAGS="$LDFLAGS -L$PWD/compat" CPPFLAGS="$CPPFLAGS -Dversionsort=alphasort"
  ac_cv_lib_resolv___res_querydomain=yes ac_cv_func_getrpcbynumber=yes \
  configure_std --disable-nfsv4 --disable-nfsv41 --disable-gss --disable-uuid --disable-nfsdcld --disable-nfsrahead \
    --disable-nfsdctl --disable-junction --disable-caps --disable-ldap --without-systemd --without-tcp-wrappers \
    --with-rpcgen=internal
  # rpcgen runs on the builder
  make -j"$JOBS" -C tools/rpcgen CC=gcc CFLAGS=-O2 CPPFLAGS= LDFLAGS= LIBS=
  local d
  for d in include misc nfs export; do make -j"$JOBS" -C "support/$d"; done
  make -j"$JOBS" -C support/reexport libreexport.a
  make -j"$JOBS" -C utils/mount mount.nfs LDFLAGS="$LT_LDFLAGS -L$PWD/compat"
  install_bin utils/mount/mount.nfs mount.nfs
  # upstream installs these three names as links to mount.nfs (mode chosen by argv[0])
  install_bin utils/mount/mount.nfs mount.nfs4
  install_bin utils/mount/mount.nfs umount.nfs
  install_bin utils/mount/mount.nfs umount.nfs4
  # libtirpc's netconfig database: $ALTDIR/etc/netconfig
  local t="$OUT/data/rt/nfs-utils/etc"
  rm -rf "$OUT/data/rt/nfs-utils"
  mkdir -p "$t"
  cp "$DEPROOT/etc/netconfig" "$t/netconfig"
}
