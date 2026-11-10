# git with the https/http transport (git-remote-http, libcurl of the curl recipe with mbedTLS and the bundled CA
# file). Runtime layout, all compiled in as paths under /system/etc/android-linux-tools:
#   libexec/                     exec path: git, git-remote-http, git-remote-https
#   share/git-core/templates/    templates for git init/clone
#   share/git-core/git-*         the shell-script commands and their libraries (plain files), started through the
#   etc/gitconfig                aliases of the system-wide configuration (ndk/module/git/gitconfig)
VERSION=2.56.1
URL=https://www.kernel.org/pub/software/scm/git/git-$VERSION.tar.xz
SHA256=f0b0bf89264b9bd2e1c640363e7529643989da76281600473c50745cd34a607f
CHECKSUM_SOURCE="kernel.org sha256sums.asc in the same directory (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE="GPL-2.0-only AND LGPL-2.1-or-later AND BSD-3-Clause AND MIT"
DEPS="curl"
# resolves host names (getaddrinfo, in git and in libcurl): link against the system libc for netd DNS
LINKAGE=dynamic
build() {
  local alt=/system/etc/android-linux-tools
  local gc=$alt/share/git-core
  # plain Makefile build (no configure). No gettext, Perl, Python, Tcl/Tk; no expat (WebDAV push); SHA-1/SHA-256
  # from git's bundled implementations (no OpenSSL); the optional Rust parts off; pthreads are in bionic's libc
  local mk=(prefix=/usr gitexecdir="$alt/libexec" template_dir="$gc/templates" sysconfdir="$alt/etc"
            CC="$CC" AR="$AR" HOSTCC=gcc CFLAGS="$CFLAGS $CPPFLAGS" LDFLAGS="$LDFLAGS" PTHREAD_LIBS=
            NO_GETTEXT=1 NO_PERL=1 NO_PYTHON=1 NO_TCLTK=1 NO_EXPAT=1 NO_OPENSSL=1 NO_RUST=1 NO_INSTALL_HARDLINKS=1
            DEFAULT_PAGER=less DEFAULT_EDITOR=nano
            CURL_CONFIG="$DEPROOT/bin/curl-config" CURL_CFLAGS="-I$DEPROOT/include"
            CURL_LDFLAGS="-L$DEPROOT/lib -lcurl -lmbedtls -lmbedx509 -lmbedcrypto -lz")
  # SHELL_PATH is both the shell that runs the build's scripts (the builder's /bin/sh) and the shell compiled into
  # git for hooks, aliases and "!" commands: only the compiled-in one is the device's /system/bin/sh
  sed -i 's|^SHELL_PATH_CQ = .*|SHELL_PATH_CQ = "/system/bin/sh"|' Makefile
  grep -q '^SHELL_PATH_CQ = "/system/bin/sh"$' Makefile
  make -j"$JOBS" "${mk[@]}" all
  install_bin git git
  install_bin git-remote-http git-remote-http
  # upstream installs git-remote-https as a link to git-remote-http
  install_bin git-remote-http git-remote-https
  # runtime data: templates, script commands (sourced libraries by their full path), system gitconfig
  local t="$OUT/data/rt/git" s
  rm -rf "$t"
  mkdir -p "$t/share/git-core/mergetools" "$t/etc"
  (cd templates/blt && find . -type f | sort) | while read -r s; do
    mkdir -p "$t/share/git-core/templates/$(dirname "$s")"
    sed '1s|^#!/bin/sh$|#!/system/bin/sh|' "templates/blt/$s" > "$t/share/git-core/templates/$s"
  done
  for s in git-submodule git-mergetool git-difftool--helper git-merge-octopus git-merge-one-file git-merge-resolve \
           git-request-pull git-filter-branch git-quiltimport git-sh-setup git-sh-i18n git-mergetool--lib; do
    sed -e "s|^\\. git-sh-setup\$|. $gc/git-sh-setup|" -e "s|^\\. git-mergetool--lib\$|. $gc/git-mergetool--lib|" \
        -e "s|\\\$(git --exec-path)/|$gc/|g" "$s" > "$t/share/git-core/$s"
    ! grep -n -e '^\. git-' -e 'git --exec-path' "$t/share/git-core/$s"
  done
  cp mergetools/* "$t/share/git-core/mergetools/"
  cp "$SRCROOT/ndk/module/git/gitconfig" "$t/etc/gitconfig"
  # licence texts of the bundled code: sha1dc (MIT), compat/regex and others are covered by COPYING/LGPL-2.1
  cp LGPL-2.1 LICENSE.LGPL-2.1
  cp sha1dc/LICENSE.txt LICENSE.sha1dc
}
