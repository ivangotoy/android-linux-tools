VERSION=3.8
URL=https://github.com/tmux/tmux/releases/download/$VERSION/tmux-$VERSION.tar.gz
SHA256=e79c699c7e949dccd0a4a125e17b8d1261e311b16979dbc8eb34542f3966d82e
CHECKSUM_SOURCE="no upstream checksum or signature; sha256 equals the GitHub release asset digest"
LICENSE=ISC
DEPS="libevent ncurses"
build() {
  # Android has no /tmp: default socket/temp dir (the wrapper also sets TMUX_TMPDIR)
  export CPPFLAGS="$CPPFLAGS -D_PATH_TMP=\\\"/data/local/tmp/\\\""
  # the "working reallocarray" probe is a run test, so a cross build always adds compat/reallocarray.c,
  # which clashes with bionic's reallocarray in a static link: give tmux's copy its own name
  export CPPFLAGS="$CPPFLAGS -Dreallocarray=tmux_reallocarray"
  configure_std --disable-utf8proc --enable-static
  make -j"$JOBS"
  install_bin tmux tmux
}
