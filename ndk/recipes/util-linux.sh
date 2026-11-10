VERSION=2.42.4
URL=https://www.kernel.org/pub/linux/utils/util-linux/v2.42/util-linux-$VERSION.tar.xz
SHA256=fbd62a100ab7bb8746ba0661255c3c48185b1e9021507c624da01fbc696330ec
CHECKSUM_SOURCE="kernel.org sha256sums.asc in the same directory (kernel.org checksum autosigner B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1)"
LICENSE="GPL-2.0-or-later AND LGPL-2.1-or-later"
DEPS="libcap-ng"
build() {
  # no --disable-all-programs: findmnt has no --enable switch and would stay disabled; only the
  # programs below (and the libraries they need) are built by make
  # script needs openpty(): configure looks for it in libutil only; bionic has it in libc: an empty libutil.a
  mkdir -p compat
  $AR rc compat/libutil.a
  export LDFLAGS="$LDFLAGS -L$PWD/compat"
  LT_LDFLAGS="$LT_LDFLAGS -L$PWD/compat"
  # bionic has no <sys/fanotify.h> (no fanotify_init/fanotify_mark wrappers): disable libmount's fanotify monitor
  ac_cv_type_struct_fanotify_event_info_header=no configure_std \
    --without-python --without-systemd --without-udev --without-ncursesw --without-ncurses --without-tinfo \
    --without-readline --without-libmagic --without-selinux --without-audit --without-cryptsetup \
    --without-btrfs --without-econf --disable-makeinstall-chown --disable-makeinstall-setuid \
    --disable-liblastlog2 --disable-pam-lastlog2 --with-cap-ng
  local p progs="setpriv lsblk blkid findmnt lscpu nsenter unshare lsns losetup dmesg wipefs fallocate zramctl taskset chrt ionice prlimit rfkill hexdump script"
  make -j"$JOBS" $progs LDFLAGS="$LT_LDFLAGS"
  for p in $progs; do install_bin "$p" "$p"; done
  # libuuid (header and static library) for nfs-utils
  make -j"$JOBS" libuuid.la
  mkdir -p "$PKGDIR/include/uuid" "$PKGDIR/lib"
  cp libuuid/src/uuid.h "$PKGDIR/include/uuid/"
  cp .libs/libuuid.a "$PKGDIR/lib/"
}
