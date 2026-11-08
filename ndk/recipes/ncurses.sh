VERSION=6.6
URL=https://ftp.gnu.org/gnu/ncurses/ncurses-$VERSION.tar.gz
SHA256=355b4cbbed880b0381a04c46617b7656e362585d52e9cf84a67e2009b749ff11
CHECKSUM_SOURCE="GNU detached signature $URL.sig, Thomas E. Dickey key 19882D92DDA4C400C22C0D56CC2AF4472167BE03"
LICENSE=X11
MODTERMINFO=/data/adb/modules/android-linux-tools/share/terminfo
TERMS="xterm,xterm-256color,xterm-color,screen,screen-256color,tmux,tmux-256color,linux,vt100,vt220,dumb,ansi,rxvt,rxvt-unicode,rxvt-unicode-256color"
build() {
  # host tic (same source) to compile the terminfo entries shipped in share/terminfo
  local hs="$B/src/ncurses-host-$VERSION"
  rm -rf "$hs" && cp -a . "$hs"
  ( cd "$hs" && env -u CFLAGS -u CPPFLAGS -u LDFLAGS -u CXXFLAGS -u PKG_CONFIG_LIBDIR -u CONFIG_SITE \
      CC=gcc CXX=false AR=ar RANLIB=ranlib ./configure --without-shared --without-cxx --without-cxx-binding \
      --without-ada --without-tests --without-manpages --enable-widec --disable-db-install \
    && env -u CFLAGS -u CPPFLAGS -u LDFLAGS make -j"$JOBS" -C include \
    && env -u CFLAGS -u CPPFLAGS -u LDFLAGS make -j"$JOBS" -C ncurses \
    && env -u CFLAGS -u CPPFLAGS -u LDFLAGS make -j"$JOBS" -C progs tic )
  rm -rf "$OUT/data/terminfo"
  mkdir -p "$OUT/data/terminfo"
  TERMINFO="$OUT/data/terminfo" "$hs/progs/tic" -x -e "$TERMS" misc/terminfo.src

  configure_std --without-shared --with-normal --without-debug --without-ada --without-cxx --without-cxx-binding \
    --without-tests --without-progs --without-manpages --enable-widec --enable-pc-files \
    --with-pkg-config-libdir=/usr/lib/pkgconfig --with-build-cc=gcc \
    --with-default-terminfo-dir="$MODTERMINFO" --with-terminfo-dirs="$MODTERMINFO:/system/etc/terminfo" \
    --disable-termcap --disable-db-install --without-gpm --disable-stripping
  make -j"$JOBS" -C include
  make -j"$JOBS" -C ncurses
  rm -rf "$B/destdir/$NAME"
  make -C include DESTDIR="$B/destdir/$NAME" install
  make -C ncurses DESTDIR="$B/destdir/$NAME" install
  make -C misc DESTDIR="$B/destdir/$NAME" install.libs
  mkdir -p "$PKGDIR"
  cp -a "$B/destdir/$NAME/usr/." "$PKGDIR/"
  # also provide the non-wide names and the include/ncursesw/ layout that some configure scripts expect
  for l in ncurses; do ln -sf lib${l}w.a "$PKGDIR/lib/lib$l.a"; done
  ln -sf libncursesw.a "$PKGDIR/lib/libtinfo.a"
  ln -sf libncursesw.a "$PKGDIR/lib/libtinfow.a"
  ln -sf ncursesw.pc "$PKGDIR/lib/pkgconfig/ncurses.pc"
  local d h
  for d in ncursesw ncurses; do
    mkdir -p "$PKGDIR/include/$d"
    for h in curses.h ncurses.h ncurses_dll.h term.h termcap.h unctrl.h; do
      [ -f "$PKGDIR/include/$h" ] && ln -sf "../$h" "$PKGDIR/include/$d/$h"
    done
  done
}
