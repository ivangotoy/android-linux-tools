# ncat only (from the nmap source tree)
VERSION=7.993
URL=https://nmap.org/dist/nmap-$VERSION.tar.bz2
SHA256=270e55f04915bfcecb5db8feb959d4c5ba86a48c094520a4f1c07571e1c79c59
CHECKSUM_SOURCE="detached signature https://nmap.org/dist/sigs/nmap-$VERSION.tar.bz2.asc (Nmap Project key 436D66AB9A798425FDA0E3F801AF9F036B9355D0) and the SHA256 in sigs/nmap-$VERSION.tar.bz2.digest.txt"
LICENSE=LicenseRef-NPSL
DEPS="libpcap"
# resolves host names (getaddrinfo): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  configure_std --with-libpcap="$DEPROOT" --without-openssl --without-liblua --without-libssh2 --without-libz \
    --without-zenmap --without-ndiff --without-nping --without-nmap-update --with-libpcre=included
  make -j"$JOBS" build-ncat
  install_bin ncat/ncat ncat
}
