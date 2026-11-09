# nmap, nping (NSE with the bundled Lua, OpenSSL, zlib) and ncat from the nmap source tree
VERSION=7.993
URL=https://nmap.org/dist/nmap-$VERSION.tar.bz2
SHA256=270e55f04915bfcecb5db8feb959d4c5ba86a48c094520a4f1c07571e1c79c59
CHECKSUM_SOURCE="detached signature https://nmap.org/dist/sigs/nmap-$VERSION.tar.bz2.asc (Nmap Project key 436D66AB9A798425FDA0E3F801AF9F036B9355D0) and the SHA256 in sigs/nmap-$VERSION.tar.bz2.digest.txt"
LICENSE=LicenseRef-NPSL
DEPS="libpcap openssl"
# resolves host names (getaddrinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  # ncat as in v2.3: its own copy of the tree, configured without OpenSSL and Lua
  rm -rf "../nmap-ncat-$VERSION"
  cp -a . "../nmap-ncat-$VERSION"
  (
    cd "../nmap-ncat-$VERSION"
    configure_std --with-libpcap="$DEPROOT" --without-openssl --without-liblua --without-libssh2 --without-libz \
      --without-zenmap --without-ndiff --without-nping --without-nmap-update --with-libpcre=included
    make -j"$JOBS" build-ncat
    install_bin ncat/ncat ncat
  )
  rm -rf "../nmap-ncat-$VERSION"
  # nmap and nping: data files (nmap-services, nmap-os-db, NSE scripts and nselib) are read from
  # NMAPDATADIR = <datadir>/nmap = $ALTDIR/share/nmap, so nmap needs no --datadir from the user
  configure_std --datadir=/system/etc/android-linux-tools/share --with-libpcap="$DEPROOT" \
    --with-openssl="$DEPROOT" --with-liblua=included --with-libz --without-libssh2 --with-libpcre=included \
    --with-libdnet=included --with-liblinear=included --without-zenmap --without-ndiff --without-nmap-update \
    --without-ncat LDFLAGS="$LDFLAGS -static-libstdc++"
  make -j"$JOBS"
  install_bin nmap nmap
  install_bin nping/nping nping
  local d="$B/destdir/$NAME"
  rm -rf "$d"
  make DESTDIR="$d" STRIP="$STRIP" install-nmap install-nse
  mkdir -p "$OUT/data/rt/nmap/share"
  rm -rf "$OUT/data/rt/nmap/share/nmap"
  cp -a "$d/system/etc/android-linux-tools/share/nmap" "$OUT/data/rt/nmap/share/nmap"
}
