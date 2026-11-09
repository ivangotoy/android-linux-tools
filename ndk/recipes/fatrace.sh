# fatrace: system-wide file access events (fanotify)
VERSION=0.19.1
URL=https://github.com/martinpitt/fatrace/archive/refs/tags/$VERSION.tar.gz
TARBALL=fatrace-$VERSION.tar.gz
SHA256=fd8f143f4e162d36c8ae29c51b32d315415447829c81091e3bb86b326051c77c
CHECKSUM_SOURCE="tag $VERSION (tag object febf47e0570108dff0894661ae8c39a8db97ad25, GitHub-verified signature) -> commit 62bd8e6d7ad7f112b37a8d5fe3dbb88c13b34844; GitHub tag archive, sha256 recorded at pin time"
LICENSE=GPL-3.0-or-later
build() {
  # bionic has no <sys/fanotify.h>: the uapi header plus syscall wrappers for fanotify_init, fanotify_mark and
  # open_by_handle_at (FAN_REPORT_FID mode), and glibc's struct file_handle
  mkdir -p compat/sys
  cat > compat/sys/fanotify.h <<'H'
#pragma once
#include <linux/fanotify.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <unistd.h>
struct file_handle {
  unsigned int handle_bytes;
  int handle_type;
  unsigned char f_handle[];
};
static inline int fanotify_init(unsigned int flags, unsigned int event_f_flags) {
  return syscall(__NR_fanotify_init, flags, event_f_flags);
}
static inline int fanotify_mark(int fd, unsigned int flags, uint64_t mask, int dirfd, const char *path) {
  return syscall(__NR_fanotify_mark, fd, flags, mask, dirfd, path);
}
static inline int open_by_handle_at(int mount_fd, struct file_handle *handle, int flags) {
  return syscall(__NR_open_by_handle_at, mount_fd, handle, flags);
}
H
  make CC="$CC" CFLAGS="$CFLAGS $CPPFLAGS -I$PWD/compat -Wall" LDFLAGS="$LDFLAGS" fatrace
  install_bin fatrace fatrace
}
