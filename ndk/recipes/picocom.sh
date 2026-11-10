# picocom: minimal dumb-terminal emulation program for serial ports (the maintained continuation of picocom 3.1)
VERSION=2024-07
URL=https://gitlab.com/wsakernel/picocom/-/archive/$VERSION/picocom-$VERSION.tar.gz
SHA256=4379de2ec591a5848123f37ccdbc7fbeee6dd3520ef1ce4119d84202fc268a17
CHECKSUM_SOURCE="no upstream checksum or signature; GitLab archive of tag $VERSION (commit 7b6acbd421a2d4ca99376b7b427828dc1bcba4d8), sha256 recorded at pin time"
LICENSE=GPL-2.0-or-later
build() {
  # the Makefile appends to CPPFLAGS/CFLAGS and takes LDFLAGS from the environment; linenoise (bundled) for the
  # file name prompts, flock() locking, custom baud rates through termios2 (the Makefile's Linux defaults)
  make -j"$JOBS" CC="$CC" picocom
  install_bin picocom picocom
}
