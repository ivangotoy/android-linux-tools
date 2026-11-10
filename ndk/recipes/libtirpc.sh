# libtirpc (transport-independent RPC) for mount.nfs; no GSS
VERSION=1.3.8
URL=https://downloads.sourceforge.net/project/libtirpc/libtirpc/$VERSION/libtirpc-$VERSION.tar.bz2
SHA256=8839959bfcc7a0f4c609d8e4f53f1c67ae33de23775ec35beb39ff15adf11920
CHECKSUM_SOURCE="SHA1 fe35ce7e81ccfa974c74ced9ac725207af9fa318 shown on the SourceForge files page of the release (verified at pin time); no upstream signature"
LICENSE=BSD-3-Clause
build() {
  # the netconfig database (transports for rpcbind queries, NFSv3 mounts) is read from the module's runtime tree:
  # Android has no /etc/netconfig
  sed -i 's|#define NETCONFIG "/etc/netconfig"|#define NETCONFIG "/system/etc/android-linux-tools/etc/netconfig"|' tirpc/netconfig.h
  grep -q android-linux-tools/etc/netconfig tirpc/netconfig.h
  configure_std --disable-gssapi
  make -j"$JOBS"
  install_lib install
  # the netconfig file for dependants that ship it (nfs-utils)
  mkdir -p "$PKGDIR/etc"
  cp doc/netconfig "$PKGDIR/etc/netconfig"
}
