VERSION=3.5.2
URL=https://download.samba.org/pub/rsync/src/rsync-$VERSION.tar.gz
SHA256=a10d591825251e070f74c98df3daad195def4ed81b4a2de16169026aea33f6c8
CHECKSUM_SOURCE="detached signature $URL.asc, key 8EDF88F4731A1E8B45D67FBE6909546B2C52EC2D"
LICENSE=GPL-3.0-or-later
# resolves host names (rsync:// and daemon mode use getaddrinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  configure_std --disable-openssl --disable-xxhash --disable-zstd --disable-lz4 --disable-md2man \
    --disable-iconv --disable-acl-support --disable-xattr-support --with-included-popt --with-included-zlib \
    --disable-idn --with-rsh=ssh
  make -j"$JOBS" rsync
  install_bin rsync rsync
}
