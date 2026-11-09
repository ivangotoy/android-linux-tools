VERSION=3.43
URL=https://brick.kernel.dk/snaps/fio-$VERSION.tar.bz2
SHA256=5e74e333f47fd4f311599b57c7c846b3a9f4f6b00411cbe7103791ad7e484c23
CHECKSUM_SOURCE="detached signature $URL.asc, Jens Axboe key C0FC392DCADE26D975FA5E4AF7D358FB2971E0A6"
LICENSE=GPL-2.0-only
# the net I/O engine resolves host names (getaddrinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  # configure detects targetos=Android from __ANDROID__. --disable-shm: bionic has no SysV shared memory
  # and fio's ashmem emulation needs /dev/ashmem; without shm fio runs jobs as threads. --as-needed: the
  # Makefile adds -llog for Android, which fio does not use.
  ./configure --prefix=/usr --cc="$CC" --extra-cflags="$CFLAGS $CPPFLAGS" --extra-ldflags="$LDFLAGS -Wl,--as-needed" \
    --disable-native --disable-shm --disable-optimizations --disable-gfapi --disable-rados --disable-rbd \
    --disable-http --disable-pmem --disable-libnfs --disable-xnvme --disable-isal --disable-libblkio \
    --disable-libzbc --disable-tcmalloc --disable-dfs --disable-numa --disable-rdma
  make -j"$JOBS" V=1 fio
  install_bin fio fio
}
