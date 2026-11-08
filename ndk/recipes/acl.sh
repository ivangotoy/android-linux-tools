VERSION=2.4.0
URL=https://download.savannah.nongnu.org/releases/acl/acl-$VERSION.tar.xz
SHA256=e661131456d2708a01c614a0f400e11d7d1bfaeb6f3e74b75bb980b72f0161a3
CHECKSUM_SOURCE="detached signature $URL.sig, key 259B3792B3D6D319212CC4DCD5BF9FEB0313653A"
LICENSE="LGPL-2.1-or-later AND GPL-2.0-or-later"
DEPS="attr"
build() {
  configure_std
  make -j"$JOBS" getfacl setfacl LDFLAGS="$LT_LDFLAGS"
  install_bin getfacl getfacl
  install_bin setfacl setfacl
}
