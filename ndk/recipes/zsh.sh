# zsh: the shell with its modules linked in (no dynamic module loading) and its function library in
# $ALTDIR/share/zsh (compiled-in fpath). /system/bin/sh stays the default shell for everything.
VERSION=5.9.2
URL=https://www.zsh.org/pub/zsh-$VERSION.tar.xz
SHA256=36fa734374b44783582cec09bcd67822e2f992c779ec1624ab5596df078d2f81
CHECKSUM_SOURCE="detached signature $URL.asc, dana key 7CA7ECAAF06216B90F894146ACF8146CAE8CBBC4"
# the shell and its core functions: zsh's LICENCE (MIT-Modern-Variant); some completion functions are GPL:
# Completion/Unix/Command/_darcs (2.0 or later), Linux/Command/_qdbus, openSUSE/Command/_zypper and _osc (GPLv2)
LICENSE="MIT-Modern-Variant AND GPL-2.0-or-later AND GPL-2.0-only"
DEPS="ncurses"
build() {
  local alt=/system/etc/android-linux-tools m
  # configure's run tests cannot run in a cross build and would take their pessimistic answers (no 64-bit integer
  # type, no named FIFOs, ...): the answers for aarch64 bionic. rlim_t: Termux packages/zsh's values.
  configure_std --disable-dynamic --enable-multibyte --with-term-lib=ncursesw --disable-gdbm --disable-pcre \
    --disable-cap --enable-function-subdirs --enable-site-fndir=no \
    --enable-fndir="$alt/share/zsh/functions" --enable-scriptdir="$alt/share/zsh/scripts" \
    zsh_cv_long_is_64_bit=yes zsh_cv_printf_has_lld=yes zsh_cv_func_realpath_accepts_null=yes \
    zsh_cv_func_tgetent_accepts_null=yes zsh_cv_func_tgetent_zero_success=no zsh_cv_rlim_t_is_longer=no \
    zsh_cv_type_rlim_t_is_unsigned=yes zsh_cv_getcwd_malloc=yes zsh_cv_sys_fifo=yes zsh_cv_sys_lseek=yes \
    zsh_cv_sys_link=yes zsh_cv_sys_path_dev_fd=/proc/self/fd ac_cv_have_dev_ptmx=yes
  grep -q '^#define ZSH_64_BIT_TYPE\|^#define LONG_IS_64_BIT' config.h
  grep -q '^#define HAVE_FIFOS 1' config.h
  # every module that is not linked in by default, except: zsh/net/tcp and zsh/zftp (they resolve host names,
  # which a static program cannot do through netd), zsh/newuser (the setup menu for users without startup
  # files), zsh/example; zsh/db/gdbm, zsh/pcre and zsh/cap need libraries that are not built (disabled above)
  for m in $(sed -n 's/^name=\([^ ]*\) .*link=no .*/\1/p' config.modules); do
    case "$m" in
      zsh/net/tcp|zsh/zftp|zsh/newuser|zsh/example|zsh/db/gdbm|zsh/pcre|zsh/cap) ;;
      *) sed -i "s|^name=$m \(.*\)link=no |name=$m \1link=static |" config.modules ;;
    esac
  done
  make -j"$JOBS"
  install_bin Src/zsh zsh
  # function library and scripts as "make install" puts them (functions of the modules linked in only)
  local d="$B/destdir/$NAME"
  rm -rf "$d"
  make DESTDIR="$d" install.fns
  rm -rf "$OUT/data/rt/zsh"
  mkdir -p "$OUT/data/rt/zsh/share"
  cp -a "$d$alt/share/zsh" "$OUT/data/rt/zsh/share/zsh"
  [ -z "$(find "$OUT/data/rt/zsh" ! -type f ! -type d)" ]
}
