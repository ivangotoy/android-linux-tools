VERSION=20250605
URL=https://github.com/iputils/iputils/releases/download/$VERSION/iputils-$VERSION.tar.xz
SHA256=6f213700dbf96b5cc4499ca70cb15ecd69c09f405b06785bb4a1a10b572b6276
CHECKSUM_SOURCE="sha256sums.asc in the GitHub release $VERSION (key 2016FEA4858B1C36B32E833AC0DEC2EE72F33A5F)"
LICENSE="BSD-3-Clause AND GPL-2.0-or-later"
# arping/tracepath resolve host names: link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  cat > cross.ini <<X
[binaries]
c = '$CC'
ar = '$AR'
strip = '$STRIP'
pkg-config = 'pkgconf'
[built-in options]
c_args = [$(printf "'%s'," $CFLAGS)]
c_link_args = [$(printf "'%s'," $LDFLAGS)]
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
X
  meson setup b --cross-file cross.ini -DUSE_CAP=false -DUSE_IDN=false -DUSE_GETTEXT=false -DBUILD_MANS=false \
    -DBUILD_HTML_MANS=false -DSKIP_TESTS=true -DNO_SETCAP_OR_SUID=true -DBUILD_PING=false -DBUILD_CLOCKDIFF=false
  ninja -C b -j"$JOBS"
  install_bin b/arping arping
  install_bin b/tracepath tracepath
}
