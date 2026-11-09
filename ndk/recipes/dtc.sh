# Device tree compiler and the libfdt utilities fdtdump, fdtget, fdtput, fdtoverlay
VERSION=1.8.1
URL=https://www.kernel.org/pub/software/utils/dtc/dtc-$VERSION.tar.xz
SHA256=23526015a6f1550e0541a53fe7acea1b5a11e3697cdf3a3bdc076abc38f6045d
CHECKSUM_SOURCE="kernel.org detached signature https://www.kernel.org/pub/software/utils/dtc/dtc-$VERSION.tar.sign (over the uncompressed tar), David Gibson signing subkey 3BE74DB14E04DF25D45D12B6CD0245DBBA31D867 (primary BB38B1154955BA147D239FB6FC2A7DC16C4E2157)"
LICENSE="GPL-2.0-or-later AND (GPL-2.0-or-later OR BSD-2-Clause)"
build() {
  # STATIC_BUILD=1: the utilities link libfdt.a; no YAML output (libyaml), no Python bindings
  make -j"$JOBS" CC="$CC" AR="$AR" EXTRA_CFLAGS="$CFLAGS $CPPFLAGS" LDFLAGS="$LDFLAGS" NO_PYTHON=1 NO_YAML=1 \
    NO_VALGRIND=1 STATIC_BUILD=1 V=1 dtc fdtdump fdtget fdtput fdtoverlay
  local p
  for p in dtc fdtdump fdtget fdtput fdtoverlay; do
    install_bin "$p" "$p"
  done
  # licence texts are in GPL, BSD-2-Clause and README.license
  cp GPL LICENSE.GPL
  cp BSD-2-Clause LICENSE.BSD-2-Clause
  cp README.license LICENSE.README
}
