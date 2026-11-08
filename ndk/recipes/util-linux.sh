VERSION=2.42.4
URL=https://www.kernel.org/pub/linux/utils/util-linux/v2.42/util-linux-$VERSION.tar.xz
SHA256=fbd62a100ab7bb8746ba0661255c3c48185b1e9021507c624da01fbc696330ec
CHECKSUM_SOURCE="kernel.org sha256sums.asc in the same directory (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE="GPL-2.0-or-later AND LGPL-2.1-or-later"
DEPS="libcap-ng"
build() {
  # no --disable-all-programs: findmnt has no --enable switch and would stay disabled; only the five
  # programs below (and the libraries they need) are built by make
  # bionic has no <sys/fanotify.h> (no fanotify_init/fanotify_mark wrappers): disable libmount's fanotify monitor
  ac_cv_type_struct_fanotify_event_info_header=no configure_std \
    --without-python --without-systemd --without-udev --without-ncursesw --without-ncurses --without-tinfo \
    --without-readline --without-libmagic --without-selinux --without-audit --without-cryptsetup \
    --without-btrfs --without-econf --disable-makeinstall-chown --disable-makeinstall-setuid \
    --disable-liblastlog2 --disable-pam-lastlog2 --with-cap-ng
  make -j"$JOBS" setpriv lsblk blkid findmnt lscpu LDFLAGS="$LT_LDFLAGS"
  local p
  for p in setpriv lsblk blkid findmnt lscpu; do install_bin "$p" "$p"; done
}
