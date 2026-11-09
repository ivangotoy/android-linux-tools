# libnl-3 and libnl-genl-3 (static) for iw
VERSION=3.12.0
URL=https://github.com/thom311/libnl/releases/download/libnl${VERSION//./_}/libnl-$VERSION.tar.gz
SHA256=fc51ca7196f1a3f5fdf6ffd3864b50f4f9c02333be28be4eeca057e103c0dd18
CHECKSUM_SOURCE="detached signature $URL.sig, Thomas Haller key 67DA3FAEBAE276BA58FC6CE314F18A98993AECD5 (expired 2025), and $URL.sha256sum of the GitHub release"
LICENSE=LGPL-2.1-only
build() {
  # with the patched private linux/socket.h, bionic's struct sockaddr_storage provides the kernel's
  # __kernel_sockaddr_storage (as termux-packages packages/libnl/build.sh does)
  export CFLAGS="$CFLAGS -Dsockaddr_storage=__kernel_sockaddr_storage"
  configure_std --disable-cli --disable-debug --disable-pthreads
  make -j"$JOBS"
  install_lib
}
