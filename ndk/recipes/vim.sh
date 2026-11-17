# Vim (huge features, terminal UI only): runtime files in $ALTDIR/share/vim, the compiled-in $VIM and $VIMRUNTIME
VERSION=9.2.1355
URL=https://github.com/vim/vim/archive/refs/tags/v$VERSION.tar.gz
TARBALL=vim-$VERSION.tar.gz
SHA256=4290f6ca08613564329d8e384ab2406d75ba5dca3971b824238967c4e0090665
CHECKSUM_SOURCE="no upstream signature (Vim tags every patch); GitHub tag archive of v$VERSION, sha256 recorded at pin time"
LICENSE=Vim
DEPS="ncurses"
# ch_open() resolves host names with getaddrinfo (channel_open() in src/channel.c): system libc for netd DNS
LINKAGE=dynamic
build() {
  local alt=/system/etc/android-linux-tools
  # $VIM and $VIMRUNTIME are both $alt/share/vim (no vim92 subdirectory)
  local mk=(VIMRTDIR= "VIMRUNTIMEDIR=$alt/share/vim")
  # cross-compile answers for configure's run tests (as Termux packages/vim) and the target's uname
  configure_std --datadir="$alt/share" --with-features=huge --enable-gui=no --without-x --disable-netbeans \
    --with-tlib=ncursesw --disable-libsodium --disable-canberra --enable-fail-if-missing \
    --with-compiledby=android-linux-tools \
    vim_cv_uname_output=Linux vim_cv_uname_r_output= vim_cv_uname_m_output=aarch64 \
    vim_cv_getcwd_broken=no vim_cv_memmove_handles_overlap=yes vim_cv_stat_ignores_slash=no vim_cv_terminfo=yes \
    vim_cv_tgetent=zero vim_cv_toupper_broken=no vim_cv_tty_group=world ac_cv_small_wchar_t=no
  # auto/pathdef.c records the full compile and link command lines for :version; they contain build paths
  make -C src "${mk[@]}" auto/pathdef.c
  sed -i -e 's|^char_u \*all_cflags = .*|char_u *all_cflags = (char_u *)"aarch64-linux-android'"$API"'-clang (flags: ndk/lib/env.sh, ndk/recipes/vim.sh of android-linux-tools)";|' \
         -e 's|^char_u \*all_lflags = .*|char_u *all_lflags = (char_u *)"aarch64-linux-android'"$API"'-clang (ncursesw, system libc)";|' src/auto/pathdef.c
  ! grep -n -e /work/ -e /opt/ndk src/auto/pathdef.c
  grep -q "default_vimruntime_dir = (char_u \*)\"$alt/share/vim\"" src/auto/pathdef.c
  make -C src -j"$JOBS" "${mk[@]}" vim
  install_bin src/vim vim
  # runtime files through upstream's installruntime (syntax, ftplugin, indent, colors, autoload, plugin, pack,
  # doc, spell, tutor, ...)
  local d="$B/destdir/$NAME"
  rm -rf "$d"
  make -C src "${mk[@]}" DESTDIR="$d" installruntime
  rm -rf "$OUT/data/rt/vim"
  mkdir -p "$OUT/data/rt/vim/share"
  cp -a "$d$alt/share/vim" "$OUT/data/rt/vim/share/vim"
  [ -z "$(find "$OUT/data/rt/vim" ! -type f ! -type d)" ]
  cp runtime/doc/uganda.txt LICENSE.uganda.txt
}
