# 7-Zip (7zz: the standalone console program with every format built in), upstream source of 7-zip.org
VERSION=26.06
URL=https://github.com/ip7z/7zip/releases/download/$VERSION/7z2606-src.tar.xz
# the source archive has no top-level directory: under a name that build.sh's extract() copies into $SRCDIR
# instead of unpacking it into the shared source directory; build() unpacks it
TARBALL=7z2606-src.txz
SRCDIR=7zip-$VERSION
SHA256=a4e374c8f864f51df48c2cfd0e1413ec3b2ea030deae852d6a655402ebb61ac4
CHECKSUM_SOURCE="no upstream signature; 7-zip.org/download.html links this GitHub release asset; sha256 equals the GitHub release asset digest"
LICENSE="LGPL-2.1-or-later AND BSD-3-Clause AND BSD-2-Clause AND LicenseRef-unRAR"
build() {
  tar -xf 7z2606-src.txz
  rm 7z2606-src.txz
  # upstream's clang/arm64 makefile (arm64 assembler for LZMA decoding and CRC); compiler flags of env.sh on top.
  # -D_GNU_SOURCE for the CPU affinity macros of sched.h (as aports and Termux). -Werror of upstream's warning set
  # is left out (newer clang warnings would stop the build). Link: the flags of env.sh (static); bionic has the
  # pthread functions in libc.
  make -C CPP/7zip/Bundles/Alone2 -f ../../cmpl_clang_arm64.mak -j"$JOBS" \
    CC="$CC $CFLAGS $CPPFLAGS -D_GNU_SOURCE" CXX="$CXX $CXXFLAGS $CPPFLAGS -D_GNU_SOURCE" \
    CFLAGS_WARN_WALL="-Wall -Wextra" LDFLAGS_STATIC_3="$LDFLAGS" LIB2=-ldl
  install_bin CPP/7zip/Bundles/Alone2/b/c_arm64/7zz 7zz
  # DOC/License.txt: licence summary (LGPL-2.1, BSD-3-Clause, BSD-2-Clause, unRAR restriction)
  cp DOC/License.txt LICENSE.txt
  cp DOC/copying.txt COPYING.LGPL-2.1
  cp DOC/unRarLicense.txt LICENSE.unRAR.txt
}
