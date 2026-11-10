# rizin: reverse engineering framework (rizin, rz-bin, rz-asm, rz-hash, rz-diff, rz-find, rz-gg, rz-ax, rz-run,
# rz-sign, rz-ar). Built as upstream builds its Android release (BUILDING.md, .github/meson-android-aarch64.ini):
# static libraries, static runtime and the "blob" (one executable for all programs), with the bundled subprojects
# (capstone, tree-sitter, libzip, zlib, xz, lz4, zstd, pcre2, ...) of the source release.
VERSION=0.9.1
URL=https://github.com/rizinorg/rizin/releases/download/v$VERSION/rizin-src-v$VERSION.tar.xz
SRCDIR=rizin-v$VERSION
SHA256=7ac1cd7daca7afdda742e15478b1f747fc1f813e496fee71839d1e109e543dca
CHECKSUM_SOURCE="no upstream signature; sha256 equals the GitHub release asset digest (tag v$VERSION -> commit c3a90e9226d977f58f4e9c75f78fa6b07afe13c7)"
LICENSE="LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0"
build() {
  local alt=/system/etc/android-linux-tools f
  # meson cross file: the NDK compiler and the flags of env.sh for the target (in a cross build meson gives the
  # CFLAGS/LDFLAGS environment variables to the native helper programs, so they are unset below)
  q() { printf "'%s'," "$@" | sed 's/,$//'; }
  cat > alt-cross.ini <<INI
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = 'false'
[built-in options]
c_args = [$(q $CFLAGS)]
cpp_args = [$(q $CXXFLAGS)]
c_link_args = [$(q $LDFLAGS)]
cpp_link_args = [$(q $LDFLAGS)]
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
INI
  # a cross build compiles pcre2 and softfloat a second time for the builder (generators run during the build);
  # upstream's wraps clone them with git (pcre2_cross_native = the pcre2 10.47 commit, softfloat_cross_native =
  # the same revision as softfloat). Use the copies bundled in the source release instead: no download
  cp -a subprojects/softfloat subprojects/softfloat_cross_native
  cp -a subprojects/pcre2-10.47 subprojects/pcre2_cross_native
  cp subprojects/packagefiles/pcre2_cross_native/meson.build subprojects/pcre2_cross_native/meson.build
  # prefix = the module runtime tree: the data files (share/rizin: sdb databases, signatures of the formats, themes,
  # fortunes, ...) are found by their compiled-in path /system/etc/android-linux-tools/share/rizin
  env -u CC -u CXX -u CPP -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u AR -u LD -u STRIP -u RANLIB -u NM -u OBJCOPY -u OBJDUMP -u READELF \
  meson setup alt-build --cross-file alt-cross.ini --buildtype=release --default-library=static --prefix="$alt" \
    --wrap-mode=nodownload -Dblob=true -Dstatic_runtime=true -Dcli=enabled -Denable_tests=false -Denable_rz_test=false \
    -Dregenerate_cmds=disabled -Dinstall_sigdb=false -Dsubprojects_check=false
  ninja -C alt-build -j"$JOBS"
  rm -rf alt-dest
  DESTDIR="$PWD/alt-dest" meson install -C alt-build --no-rebuild
  install_bin "alt-dest$alt/bin/rizin" rizin
  local t="$OUT/data/rt/rizin/share"
  rm -rf "$OUT/data/rt/rizin"
  mkdir -p "$t"
  (cd "alt-dest$alt/share" && find rizin -type f | sort) | while read -r f; do
    mkdir -p "$t/$(dirname "$f")"
    cp "alt-dest$alt/share/$f" "$t/$f"
  done
  [ "$(find "$t/rizin" -type f | wc -l)" -gt 50 ]
  # licence texts of rizin (REUSE: LICENSES/) and of the bundled subprojects
  for f in LICENSES/*.txt; do cp "$f" "LICENSE.$(basename "$f" .txt)"; done
  cp COPYING.LESSER LICENSE.COPYING.LESSER
  local d
  for d in subprojects/*/; do
    d=${d%/}
    for f in $(cd "$d" && ls -d COPYING* LICENSE* LICENCE* License* NOTICE* 2>/dev/null); do
      [ -f "$d/$f" ] && cp "$d/$f" "LICENSE.subproject-$(basename "$d")-$f"
    done
  done
}
