# Android Linux tools

A root module that adds Linux userspace tools (netfilter, iproute2, WireGuard/AmneziaWG, Wi-Fi (iw), tracing
and debugging (strace, ltrace, fatrace, gdbserver, lldb-server, eu-stack), packet capture, BPF tracing (bpftool,
bpftrace with its tool scripts, the bcc libbpf-tools, eCapture), reverse engineering (rizin), ELF tools (GNU binutils,
elfutils, patchelf), device trees (dtc), EROFS, SquashFS, ext4 and F2FS tools, Android platform tools (adb, fastboot,
sparse and super image tools), git, ripgrep, fd, fzf, ncdu, picocom, an NFS mount helper, util-linux programs
(nsenter, unshare, losetup, dmesg, ...), nmap, OpenSSL, an SSH client and server (dropbear), DNS and network
diagnostics, storage benchmarks (fio), compression, editors, shells)
to rooted aarch64 Android phones. Every
program is compiled from upstream source with the Android NDK for bionic (`aarch64-linux-android`, API 35).
The module does not depend on any particular device. It runs nothing at boot (no `post-fs-data.sh`,
`service.sh` or other boot script) and changes nothing on the device except the files the root manager
mounts from its `system/` tree.

- Repository: <https://git.digtvbg.com/ivangotoy/android-linux-tools> (Forgejo), mirrored to
  <https://github.com/ivangotoy/android-linux-tools>.
- Module id `android-linux-tools`, module directory `/data/adb/modules/android-linux-tools`.
- Version `v2.M-rN`, versionCode `major*100000 + minor*1000 + N` (`v2.6-r1` = `206001`), set in `ndk/build.conf`.
- One ZIP (see "One ZIP"); tool list in "Contents".

## Install

- In the root manager app: Modules, Install from storage, pick the ZIP. Then reboot.
- Command line, as root: `ksud module install /sdcard/Download/android-linux-tools-v2.6-r1.zip` (KernelSU).
  Magisk (`magisk --install-module ZIP`) and APatch (`apd module install ZIP`) have the same module interface.
- Upgrading: install the new ZIP over the old one and reboot. The installer recognises wrappers of this
  module (also of v1/v2.0/v2.1) and never renames them as device binaries. No other module is touched.
- The ZIP has the standard Magisk `META-INF/com/google/android/update-binary`; KernelSU and APatch use their own
  installer and run the same `customize.sh`. It uses only `ui_print`, `set_perm` and `set_perm_recursive` (with
  fallbacks if they are missing) and no manager-specific command (`ndk/scripts/check.py` enforces that).

Root managers: KernelSU (with a metamodule such as NoMount or meta-overlayfs), Magisk and APatch; how each
mounts the module's files is in `ndk/REFERENCES.md`, "Runtime layout".

## Runtime layout

`/data/adb` is `0700 root`, so nothing a tool needs at run time is read from the module directory. Every
runtime file is in the module's `system/` tree, which the root manager mounts over `/system`:

| Module path | Device path | Contents |
|---|---|---|
| `system/bin/` | `/system/bin` | wrappers and `alt-list` (names after the `-ng` rule) |
| `system/etc/android-linux-tools/libexec/` | `$ALTDIR/libexec` | every ELF program |
| `system/etc/android-linux-tools/share/terminfo/` | `$ALTDIR/share/terminfo` | terminfo (compiled-in default of ncurses) |
| `system/etc/android-linux-tools/etc/ssl/cert.pem` | `$ALTDIR/etc/ssl/cert.pem` | Mozilla CA bundle (curl, OpenSSL default) |
| `system/etc/android-linux-tools/etc/ssl/openssl.cnf` | `$ALTDIR/etc/ssl/openssl.cnf` | default configuration of the `openssl` CLI |
| `system/etc/android-linux-tools/share/nmap/` | `$ALTDIR/share/nmap` | nmap data files, NSE scripts and nselib (compiled-in data directory) |
| `system/etc/android-linux-tools/share/ltrace/` | `$ALTDIR/share/ltrace` | ltrace prototype files (`libc.so.conf`, `syscalls.conf`, ...) |
| `system/etc/android-linux-tools/share/bpftrace/tools/` | `$ALTDIR/share/bpftrace/tools` | bpftrace's upstream tool scripts (`tools/*.bt`) |
| `system/etc/android-linux-tools/share/git-core/` | `$ALTDIR/share/git-core` | git templates (`templates/`), git's shell-script commands and their libraries, `mergetools/` |
| `system/etc/android-linux-tools/etc/gitconfig` | `$ALTDIR/etc/gitconfig` | git's system-wide configuration: aliases that run the script commands |
| `system/etc/android-linux-tools/share/rizin/` | `$ALTDIR/share/rizin` | rizin data files (sdb databases, magic, themes, ...; compiled-in data directory) |
| `system/etc/android-linux-tools/etc/netconfig` | `$ALTDIR/etc/netconfig` | libtirpc's transport database for `mount.nfs` |
| `system/etc/android-linux-tools/etc/alt-tools.map` | `$ALTDIR/etc/alt-tools.map` | rename map written by `customize.sh`, read by `alt-list` |
| `system/etc/android-linux-tools/share/android-linux-tools/` | `$ALTSHARE` | `dns-servers`, `origins.txt`, `MANIFEST.json`, `phone-test.sh` |
| `module.prop`, `customize.sh`, `META-INF/`, `share/licenses/` | `/data/adb/modules/android-linux-tools` | module metadata and licences only |

`ALTDIR=/system/etc/android-linux-tools`, `ALTSHARE=$ALTDIR/share/android-linux-tools`. A wrapper is a small
`#!/system/bin/sh` script that sets `ALTDIR`, `TERMINFO` and (if unset) `TMPDIR=/data/local/tmp` and execs
`$ALTDIR/libexec/<program>`; it contains no `$MODDIR` or `/data/adb` path. `customize.sh` sets everything
root:root with SELinux context `u:object_r:system_file:s0`: `0755` for directories, programs and scripts, `0644`
for data. `/system/etc` exists on every device, so no new top-level `/system` directory is needed; sources in
`ndk/REFERENCES.md`, "Runtime layout".

## Non-root use

Because wrappers and runtime files are under `/system` (readable and executable by every uid), the tools
also run without root (`adb shell`, Termux, apps), with the permissions of the calling user. Operations that need root or capabilities (nft, ipset, conntrack, `bpftool prog list`, creating links with
`ip-ng`/`awg`, tcpdump capture, ...) still need `su`.

## Never shadowing device binaries: the `-ng` rule and `alt-list`

1. Some tools always ship with an `-ng` suffix, because the upstream tool is wanted next to the stock Android
   one: `ip-ng tc-ng ss-ng ethtool-ng blkid-ng e2fsck-ng mke2fs-ng tune2fs-ng resize2fs-ng fsck.f2fs-ng
   dump.f2fs-ng traceroute-ng arping-ng tracepath-ng`. For example, `tc-ng` parses CAKE options and the stock
   `tc` does not.
2. Every other wrapper is checked at install time. `customize.sh` looks for each name in `/system/bin
   /system/xbin /system_ext/bin /product/bin /vendor/bin /vendor/xbin /odm/bin /apex/*/bin`. If the device
   already has that name, the wrapper is renamed to `<name>-ng` (or `<name>-ng-ng` if that is also taken) and
   the installer prints the rename. Files of this module are recognised by the `ALTDIR=` (v2.2+) or `MODDIR=`
   (older versions) line in their first 400 bytes, so an upgrade never renames a wrapper because
   of the previous version's copy (`check.py` requires that marker in every wrapper).
3. `alt-list` prints the installed command names and marks the renamed ones; `alt-list -r` prints only the
   renames; `alt-list -m` prints the map (`tool installed-name device-path-or--`).

The set of command names can therefore differ between phones (for example `curl` becomes `curl-ng` on a
phone that ships a `curl`). Use `alt-list` to see what a phone has.

## One ZIP

Since v2.3-r1 the module is a single ZIP, `android-linux-tools-<ver>.zip`, with every tool (including bpftool, built without
LLVM, and bpftrace with its statically linked LLVM/clang). Up to v2.2-r2 there were two flavours,
`android-linux-tools-<ver>.zip` (`lite`) and `android-linux-tools-full-<ver>.zip` (`full`); since v2.1 they had
the same programs and differed only in metadata (up to v2.0 the full flavour added the Alpine bpftool with
libLLVM, about 172 MB). The module id is unchanged, so the ZIP installs over either flavour like any upgrade;
`module.prop` and `MANIFEST.json` no longer have a `flavour` field.

## Contents (v2.6-r1)

246 commands plus `alt-list`, 230 ELF programs; there is no `lib/` directory. Sizes are of the stripped
`$ALTDIR/libexec/` programs. Linkage `dynamic` = PIE against the system `libc.so`/`libm.so`/`libdl.so`
(`libz.so` for curl, nmap, dropbear, ltrace, fio, git and the android-tools programs) only, every third-party library
linked in statically. Three more programs are in `libexec` without a command of their own: `mtr-packet`, `sadc`
(started by `sar`) and `git-remote-http`/`git-remote-https` (started by `git`). Generated from
`dist/MANIFEST-v2.json` of the v2.6-r1 build.

| ZIP | Bytes | Unpacked |
|---|---|---|
| `android-linux-tools-v2.6-r1.zip` | 173393118 | 418.8 MB |

| Command | Recipe | Version | Linkage | libexec (KB) | Licence (SPDX) |
|---|---|---|---|---|---|
| `nft` | nftables | 1.1.7 | dynamic | 938 | GPL-2.0-only |
| `ipset` | ipset | 7.24 | dynamic | 156 | GPL-2.0-only |
| `conntrack` | conntrack-tools | 1.4.9 | static | 438 | GPL-2.0-or-later |
| `nfct` | conntrack-tools | 1.4.9 | static | 277 | GPL-2.0-or-later |
| `wg` | wireguard-tools | 1.0.20260223 | dynamic | 78 | GPL-2.0-only |
| `bridge` | iproute2 | 7.3.0 | dynamic | 112 | GPL-2.0-or-later |
| `ip-ng` | iproute2 | 7.3.0 | dynamic | 599 (=ip) | GPL-2.0-or-later |
| `tc-ng` | iproute2 | 7.3.0 | dynamic | 451 (=tc) | GPL-2.0-or-later |
| `ss-ng` | iproute2 | 7.3.0 | dynamic | 107 (=ss) | GPL-2.0-or-later |
| `bpftool` | bpftool | 7.8.1 | static | 1020 | GPL-2.0-only OR BSD-2-Clause |
| `bpftrace` | bpftrace | 0.27.1 | static | 83930 | Apache-2.0 AND (LGPL-2.1-only OR BSD-2-Clause) |
| `getfacl` | acl | 2.4.0 | static | 294 | LGPL-2.1-or-later AND GPL-2.0-or-later |
| `setfacl` | acl | 2.4.0 | static | 345 | LGPL-2.1-or-later AND GPL-2.0-or-later |
| `mount.cifs` | cifs-utils | 7.9 | dynamic | 60 | GPL-3.0-or-later |
| `iperf3` | iperf3 | 3.22 | dynamic | 127 | BSD-3-Clause-LBNL |
| `tcpdump` | tcpdump | 4.99.7 | dynamic | 1239 | BSD-3-Clause |
| `strace` | strace | 7.3 | static | 1601 | LGPL-2.1-or-later |
| `capsh` | libcap | 2.78 | static | 937 | BSD-3-Clause OR GPL-2.0-only |
| `getpcaps` | libcap | 2.78 | static | 893 | BSD-3-Clause OR GPL-2.0-only |
| `setpriv` | util-linux | 2.42.4 | static | 337 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `lsblk` | util-linux | 2.42.4 | static | 1142 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `blkid-ng` | util-linux | 2.42.4 | static | 849 (=blkid) | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `findmnt` | util-linux | 2.42.4 | static | 1081 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `lscpu` | util-linux | 2.42.4 | static | 781 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `curl` | curl | 8.23.0 | dynamic | 1392 | curl |
| `dig` | bind | 9.20.30 | dynamic | 8161 | MPL-2.0 |
| `host` | bind | 9.20.30 | dynamic | 8128 | MPL-2.0 |
| `mtr` | mtr | 0.96 | dynamic | 213 | GPL-2.0-only |
| `socat` | socat | 1.8.1.3 | dynamic | 317 | GPL-2.0-only WITH OpenSSL-Exception |
| `htop` | htop | 3.5.3 | static | 1093 | GPL-2.0-or-later |
| `iostat` | sysstat | 12.8.0 | static | 359 | GPL-2.0-or-later |
| `pidstat` | sysstat | 12.8.0 | static | 405 | GPL-2.0-or-later |
| `mpstat` | sysstat | 12.8.0 | static | 345 | GPL-2.0-or-later |
| `sqlite3` | sqlite | 3.54.1 | static | 2062 | blessing |
| `rsync` | rsync | 3.5.2 | dynamic | 563 | GPL-3.0-or-later |
| `zstd` | zstd | 1.5.7 | static | 879 | BSD-3-Clause OR GPL-2.0-only |
| `unzstd` | zstd | 1.5.7 | static | 879 (=zstd `-d`) | BSD-3-Clause OR GPL-2.0-only |
| `zstdcat` | zstd | 1.5.7 | static | 879 (=zstd `-dcf`) | BSD-3-Clause OR GPL-2.0-only |
| `xz` | xz | 5.8.4 | static | 803 | 0BSD AND GPL-2.0-or-later |
| `unxz` | xz | 5.8.4 | static | 803 (=xz `-d`) | 0BSD AND GPL-2.0-or-later |
| `xzcat` | xz | 5.8.4 | static | 803 (=xz `-dc`) | 0BSD AND GPL-2.0-or-later |
| `lz4` | lz4 | 1.11.0 | static | 450 | BSD-2-Clause AND GPL-2.0-or-later |
| `unlz4` | lz4 | 1.11.0 | static | 450 (=lz4 `-d`) | BSD-2-Clause AND GPL-2.0-or-later |
| `lz4cat` | lz4 | 1.11.0 | static | 450 (=lz4 `-dc`) | BSD-2-Clause AND GPL-2.0-or-later |
| `e2fsck-ng` | e2fsprogs | 1.47.4 | static | 887 (=e2fsck) | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `mke2fs-ng` | e2fsprogs | 1.47.4 | static | 715 (=mke2fs) | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `tune2fs-ng` | e2fsprogs | 1.47.4 | static | 707 (=tune2fs) | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `resize2fs-ng` | e2fsprogs | 1.47.4 | static | 563 (=resize2fs) | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `fsck.f2fs-ng` | f2fs-tools | 1.17.0 | static | 648 (=fsck.f2fs) | GPL-2.0-or-later OR LGPL-2.1-or-later |
| `dump.f2fs-ng` | f2fs-tools | 1.17.0 | static | 648 (=dump.f2fs) | GPL-2.0-or-later OR LGPL-2.1-or-later |
| `traceroute-ng` | traceroute | 2.1.6 | dynamic | 62 (=traceroute) | GPL-2.0-or-later |
| `arping-ng` | iputils | 20250605 | dynamic | 17 (=arping) | BSD-3-Clause AND GPL-2.0-or-later |
| `tracepath-ng` | iputils | 20250605 | dynamic | 13 (=tracepath) | BSD-3-Clause AND GPL-2.0-or-later |
| `tmux` | tmux | 3.8 | static | 2014 | ISC |
| `nano` | nano | 9.3 | static | 1330 | GPL-3.0-or-later |
| `less` | less | 710 | static | 619 | GPL-3.0-or-later OR BSD-2-Clause |
| `jq` | jq | 1.8.2 | static | 1144 | MIT |
| `bash` | bash | 5.3.20 | static | 1972 | GPL-3.0-or-later |
| `ncat` | nmap | 7.993 | dynamic | 153 | LicenseRef-NPSL |
| `iftop` | iftop | 1.0pre4 | dynamic | 426 | GPL-2.0-or-later |
| `tree` | tree | 2.3.2 | static | 369 | GPL-2.0-or-later |
| `pv` | pv | 1.12.7 | static | 433 | Artistic-2.0 |
| `wg-quick` | wireguard-tools | 1.0.20260223 | dynamic | 29 | GPL-2.0-only |
| `awg` | amneziawg-tools | 3.1.20260812 | dynamic | 96 | GPL-2.0-only |
| `awg-quick` | amneziawg-tools | 3.1.20260812 | dynamic | 29 | GPL-2.0-only |
| `drill` | ldns | 1.9.2 | static | 515 | BSD-3-Clause |
| `ethtool-ng` | ethtool | 7.2 | static | 544 (=ethtool) | GPL-2.0-only |
| `nmap` | nmap | 7.993 | dynamic | 9377 | LicenseRef-NPSL |
| `nping` | nmap | 7.993 | dynamic | 4990 | LicenseRef-NPSL |
| `openssl` | openssl | 3.5.9 | dynamic | 5414 | Apache-2.0 |
| `dropbear` | dropbear | 2026.94 | dynamic | 287 | MIT AND BSD-3-Clause AND Unlicense AND LicenseRef-PublicDomain |
| `dbclient` | dropbear | 2026.94 | dynamic | 270 | MIT AND BSD-3-Clause AND Unlicense AND LicenseRef-PublicDomain |
| `ssh` | dropbear | 2026.94 | dynamic | 270 (=dbclient) | MIT AND BSD-3-Clause AND Unlicense AND LicenseRef-PublicDomain |
| `scp` | dropbear | 2026.94 | dynamic | 26 | MIT AND BSD-3-Clause AND Unlicense AND LicenseRef-PublicDomain |
| `dropbearkey` | dropbear | 2026.94 | dynamic | 110 | MIT AND BSD-3-Clause AND Unlicense AND LicenseRef-PublicDomain |
| `dropbearconvert` | dropbear | 2026.94 | dynamic | 105 | MIT AND BSD-3-Clause AND Unlicense AND LicenseRef-PublicDomain |
| `iw` | iw | 6.17 | static | 587 | ISC |
| `gdbserver` | gdbserver | 18.1 | dynamic | 611 | GPL-3.0-or-later |
| `ltrace` | ltrace | 0.8.1 | dynamic | 415 | GPL-2.0-or-later |
| `fio` | fio | 3.43 | dynamic | 1626 | GPL-2.0-only |
| `eu-stack` | elfutils | 0.197 | static | 901 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-readelf` | elfutils | 0.197 | static | 988 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-nm` | elfutils | 0.197 | static | 793 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-unstrip` | elfutils | 0.197 | static | 901 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-addr2line` | elfutils | 0.197 | static | 881 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `objdump` | binutils | 2.47 | static | 3064 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `nm` | binutils | 2.47 | static | 1602 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `addr2line` | binutils | 2.47 | static | 1585 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `readelf` | binutils | 2.47 | static | 1010 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `strings` | binutils | 2.47 | static | 1499 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `patchelf` | patchelf | 0.19.3 | static | 811 | GPL-3.0-or-later |
| `dtc` | dtc | 1.8.1 | static | 370 | GPL-2.0-or-later AND (GPL-2.0-or-later OR BSD-2-Clause) |
| `fdtdump` | dtc | 1.8.1 | static | 255 | GPL-2.0-or-later AND (GPL-2.0-or-later OR BSD-2-Clause) |
| `fdtget` | dtc | 1.8.1 | static | 260 | GPL-2.0-or-later AND (GPL-2.0-or-later OR BSD-2-Clause) |
| `fdtput` | dtc | 1.8.1 | static | 266 | GPL-2.0-or-later AND (GPL-2.0-or-later OR BSD-2-Clause) |
| `fdtoverlay` | dtc | 1.8.1 | static | 272 | GPL-2.0-or-later AND (GPL-2.0-or-later OR BSD-2-Clause) |
| `mkfs.erofs` | erofs-utils | 1.9.4 | static | 1159 | MIT AND (GPL-2.0-or-later OR MIT) |
| `fsck.erofs` | erofs-utils | 1.9.4 | static | 883 | MIT AND (GPL-2.0-or-later OR MIT) |
| `dump.erofs` | erofs-utils | 1.9.4 | static | 894 | MIT AND (GPL-2.0-or-later OR MIT) |
| `mksquashfs` | squashfs-tools | 4.7.5 | static | 1270 | GPL-2.0-or-later |
| `unsquashfs` | squashfs-tools | 4.7.5 | static | 1091 | GPL-2.0-or-later |
| `fatrace` | fatrace | 0.19.1 | static | 321 | GPL-3.0-or-later |
| `ecapture` | ecapture | 2.10.0 | static | 19181 | Apache-2.0 AND (MIT OR GPL-2.0-only) AND BSD-3-Clause AND MIT AND MPL-2.0 AND LicenseRef-ecapture_decryptor |
| `nsenter-ng` | util-linux | 2.42.4 | static | 318 (=nsenter) | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `unshare-ng` | util-linux | 2.42.4 | static | 330 (=unshare) | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `lsns` | util-linux | 2.42.4 | static | 1037 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `losetup` | util-linux | 2.42.4 | static | 746 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `dmesg` | util-linux | 2.42.4 | static | 386 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `wipefs` | util-linux | 2.42.4 | static | 862 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `fallocate` | util-linux | 2.42.4 | static | 262 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `zramctl` | util-linux | 2.42.4 | static | 722 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `taskset` | util-linux | 2.42.4 | static | 273 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `chrt` | util-linux | 2.42.4 | static | 272 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `ionice` | util-linux | 2.42.4 | static | 260 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `prlimit` | util-linux | 2.42.4 | static | 695 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `rfkill` | util-linux | 2.42.4 | static | 683 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `hexdump` | util-linux | 2.42.4 | static | 324 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `script` | util-linux | 2.42.4 | static | 320 | GPL-2.0-or-later AND LGPL-2.1-or-later |
| `getcap` | libcap | 2.78 | static | 917 | BSD-3-Clause OR GPL-2.0-only |
| `setcap` | libcap | 2.78 | static | 897 | BSD-3-Clause OR GPL-2.0-only |
| `pscap` | libcap-ng | 0.9.6 | static | 309 | LGPL-2.1-or-later |
| `netcap` | libcap-ng | 0.9.6 | static | 351 | LGPL-2.1-or-later |
| `filecap` | libcap-ng | 0.9.6 | static | 304 | LGPL-2.1-or-later |
| `debugfs` | e2fsprogs | 1.47.4 | static | 811 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `dumpe2fs` | e2fsprogs | 1.47.4 | static | 542 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `e2image` | e2fsprogs | 1.47.4 | static | 534 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `filefrag` | e2fsprogs | 1.47.4 | static | 256 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |
| `mkfs.f2fs` | f2fs-tools | 1.17.0 | static | 407 | GPL-2.0-or-later OR LGPL-2.1-or-later |
| `resize.f2fs` | f2fs-tools | 1.17.0 | static | 648 | GPL-2.0-or-later OR LGPL-2.1-or-later |
| `sload.f2fs` | f2fs-tools | 1.17.0 | static | 648 | GPL-2.0-or-later OR LGPL-2.1-or-later |
| `f2fs_io` | f2fs-tools | 1.17.0 | static | 299 | GPL-2.0-or-later OR LGPL-2.1-or-later |
| `nstat` | iproute2 | 7.3.0 | dynamic | 21 | GPL-2.0-or-later |
| `ifstat` | iproute2 | 7.3.0 | dynamic | 37 | GPL-2.0-or-later |
| `lnstat` | iproute2 | 7.3.0 | dynamic | 17 | GPL-2.0-or-later |
| `genl` | iproute2 | 7.3.0 | dynamic | 27 | GPL-2.0-or-later |
| `devlink` | iproute2 | 7.3.0 | dynamic | 166 | GPL-2.0-or-later |
| `rtmon` | iproute2 | 7.3.0 | dynamic | 14 | GPL-2.0-or-later |
| `nslookup` | bind | 9.20.30 | dynamic | 8131 | MPL-2.0 |
| `delv` | bind | 9.20.30 | dynamic | 8324 | MPL-2.0 |
| `nsupdate` | bind | 9.20.30 | dynamic | 8099 | MPL-2.0 |
| `objcopy` | binutils | 2.47 | static | 1725 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `strip` | binutils | 2.47 | static | 1524 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `size` | binutils | 2.47 | static | 1496 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `ar` | binutils | 2.47 | static | 1524 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `c++filt` | binutils | 2.47 | static | 350 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `elfedit` | binutils | 2.47 | static | 274 | GPL-3.0-or-later AND LGPL-2.1-or-later |
| `eu-strip` | elfutils | 0.197 | static | 753 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-elflint` | elfutils | 0.197 | static | 790 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-elfcmp` | elfutils | 0.197 | static | 707 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-size` | elfutils | 0.197 | static | 355 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `eu-elfclassify` | elfutils | 0.197 | static | 402 | (LGPL-3.0-or-later OR GPL-2.0-or-later) AND GPL-3.0-or-later AND LGPL-2.0-or-later AND LGPL-2.1-or-later |
| `sqldiff` | sqlite | 3.54.1 | static | 1376 | blessing |
| `sqlite3_rsync` | sqlite | 3.54.1 | static | 1375 | blessing |
| `sar` | sysstat | 12.8.0 | static | 448 | GPL-2.0-or-later |
| `sqfstar` | squashfs-tools | 4.7.5 | static | 1270 | GPL-2.0-or-later |
| `sqfscat` | squashfs-tools | 4.7.5 | static | 1091 | GPL-2.0-or-later |
| `procan` | socat | 1.8.1.3 | dynamic | 36 | GPL-2.0-only WITH OpenSSL-Exception |
| `filan` | socat | 1.8.1.3 | dynamic | 48 | GPL-2.0-only WITH OpenSSL-Exception |
| `bashreadline` | libbpf-tools | 0.37.0 | static | 706 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `bindsnoop` | libbpf-tools | 0.37.0 | static | 731 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `biolatency` | libbpf-tools | 0.37.0 | static | 725 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `biopattern` | libbpf-tools | 0.37.0 | static | 702 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `biosnoop` | libbpf-tools | 0.37.0 | static | 730 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `biostacks` | libbpf-tools | 0.37.0 | static | 693 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `biotop` | libbpf-tools | 0.37.0 | static | 725 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `bitesize` | libbpf-tools | 0.37.0 | static | 706 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `cachestat` | libbpf-tools | 0.37.0 | static | 704 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `capable` | libbpf-tools | 0.37.0 | static | 722 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `cpudist` | libbpf-tools | 0.37.0 | static | 732 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `cpufreq` | libbpf-tools | 0.37.0 | static | 674 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `drsnoop` | libbpf-tools | 0.37.0 | static | 709 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `execsnoop` | libbpf-tools | 0.37.0 | static | 779 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `exitsnoop` | libbpf-tools | 0.37.0 | static | 732 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `filelife` | libbpf-tools | 0.37.0 | static | 748 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `filetop` | libbpf-tools | 0.37.0 | static | 729 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `fsdist` | libbpf-tools | 0.37.0 | static | 721 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `fsslower` | libbpf-tools | 0.37.0 | static | 729 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `funclatency` | libbpf-tools | 0.37.0 | static | 716 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `futexctn` | libbpf-tools | 0.37.0 | static | 714 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `gethostlatency` | libbpf-tools | 0.37.0 | static | 707 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `hardirqs` | libbpf-tools | 0.37.0 | static | 707 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `javagc` | libbpf-tools | 0.37.0 | static | 709 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `klockstat` | libbpf-tools | 0.37.0 | static | 909 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `ksnoop` | libbpf-tools | 0.37.0 | static | 705 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `llcstat` | libbpf-tools | 0.37.0 | static | 674 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `mdflush` | libbpf-tools | 0.37.0 | static | 711 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `memleak` | libbpf-tools | 0.37.0 | static | 755 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `mountsnoop` | libbpf-tools | 0.37.0 | static | 758 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `numamove` | libbpf-tools | 0.37.0 | static | 702 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `offcputime` | libbpf-tools | 0.37.0 | static | 717 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `oomkill` | libbpf-tools | 0.37.0 | static | 735 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `opensnoop` | libbpf-tools | 0.37.0 | static | 759 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `profile` | libbpf-tools | 0.37.0 | static | 691 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `readahead` | libbpf-tools | 0.37.0 | static | 681 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `runqlat` | libbpf-tools | 0.37.0 | static | 737 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `runqlen` | libbpf-tools | 0.37.0 | static | 728 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `runqslower` | libbpf-tools | 0.37.0 | static | 738 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `sigsnoop` | libbpf-tools | 0.37.0 | static | 735 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `slabratetop` | libbpf-tools | 0.37.0 | static | 707 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `softirqs` | libbpf-tools | 0.37.0 | static | 703 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `solisten` | libbpf-tools | 0.37.0 | static | 724 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `statsnoop` | libbpf-tools | 0.37.0 | static | 698 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `syncsnoop` | libbpf-tools | 0.37.0 | static | 680 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `syscount` | libbpf-tools | 0.37.0 | static | 732 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcpconnect` | libbpf-tools | 0.37.0 | static | 707 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcpconnlat` | libbpf-tools | 0.37.0 | static | 697 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcplife` | libbpf-tools | 0.37.0 | static | 738 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcppktlat` | libbpf-tools | 0.37.0 | static | 739 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcprtt` | libbpf-tools | 0.37.0 | static | 737 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcpstates` | libbpf-tools | 0.37.0 | static | 723 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcpsynbl` | libbpf-tools | 0.37.0 | static | 716 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcptop` | libbpf-tools | 0.37.0 | static | 720 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `tcptracer` | libbpf-tools | 0.37.0 | static | 755 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `vfsstat` | libbpf-tools | 0.37.0 | static | 707 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `wakeuptime` | libbpf-tools | 0.37.0 | static | 701 | (LGPL-2.1-only OR BSD-2-Clause) AND Apache-2.0 |
| `lldb-server` | lldb-server | 23.1.5 | static | 12731 | Apache-2.0 WITH LLVM-exception |
| `rg` | ripgrep | 15.2.0 | dynamic | 4304 | Unlicense OR MIT |
| `fd` | fd | 10.5.2 | dynamic | 2940 | MIT OR Apache-2.0 |
| `fzf` | fzf | 0.75.0 | static | 5328 | MIT AND BSD-3-Clause AND Apache-2.0 |
| `ncdu` | ncdu | 1.22 | static | 866 | MIT |
| `picocom` | picocom | 2024-07 | static | 333 | GPL-2.0-or-later |
| `mount.nfs` | nfs-utils | 2.9.2 | dynamic | 132 | GPL-2.0-or-later |
| `mount.nfs4` | nfs-utils | 2.9.2 | dynamic | 132 | GPL-2.0-or-later |
| `umount.nfs` | nfs-utils | 2.9.2 | dynamic | 132 | GPL-2.0-or-later |
| `umount.nfs4` | nfs-utils | 2.9.2 | dynamic | 132 | GPL-2.0-or-later |
| `git` | git | 2.56.1 | dynamic | 3744 | GPL-2.0-only AND LGPL-2.1-or-later AND BSD-3-Clause AND MIT |
| `git-upload-pack` | git | 2.56.1 | dynamic | 3744 (=git `upload-pack`) | GPL-2.0-only AND LGPL-2.1-or-later AND BSD-3-Clause AND MIT |
| `git-receive-pack` | git | 2.56.1 | dynamic | 3744 (=git `receive-pack`) | GPL-2.0-only AND LGPL-2.1-or-later AND BSD-3-Clause AND MIT |
| `git-upload-archive` | git | 2.56.1 | dynamic | 3744 (=git `upload-archive`) | GPL-2.0-only AND LGPL-2.1-or-later AND BSD-3-Clause AND MIT |
| `rizin` | rizin | 0.9.1 | static | 53170 | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-bin` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-bin`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-asm` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-asm`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-hash` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-hash`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-diff` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-diff`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-find` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-find`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-gg` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-gg`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-ax` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-ax`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-run` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-run`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-sign` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-sign`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `rz-ar` | rizin | 0.9.1 | static | 53170 (=rizin `--blob-main=rz-ar`) | LGPL-3.0-only AND GPL-2.0-or-later AND GPL-3.0-or-later AND LGPL-2.1-or-later AND Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND MIT AND NCSA AND CC0-1.0 |
| `adb` | android-tools | 37.0.0p1 | dynamic | 5146 | Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT AND OpenSSL AND LGPL-2.1-or-later |
| `fastboot` | android-tools | 37.0.0p1 | dynamic | 1230 | Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT AND OpenSSL AND LGPL-2.1-or-later |
| `simg2img` | android-tools | 37.0.0p1 | dynamic | 67 | Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT AND OpenSSL AND LGPL-2.1-or-later |
| `img2simg` | android-tools | 37.0.0p1 | dynamic | 68 | Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT AND OpenSSL AND LGPL-2.1-or-later |
| `lpunpack` | android-tools | 37.0.0p1 | dynamic | 344 | Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT AND OpenSSL AND LGPL-2.1-or-later |
| `lpmake` | android-tools | 37.0.0p1 | dynamic | 389 | Apache-2.0 AND BSD-2-Clause AND BSD-3-Clause AND ISC AND MIT AND OpenSSL AND LGPL-2.1-or-later |
| `alt-list` | (module script) | | | | MIT |

`$ALTSHARE/MANIFEST.json` (and `dist/MANIFEST-v2.json`) records per tool the recipe, upstream version, source
URL and sha256, how the checksum was verified, licence, patches, dependencies, linkage and DNS method;
`$ALTSHARE/origins.txt` has one line per tool (origin, version, linkage).

## Build and runtime details

- Toolchain: Android NDK r30 (LTS, 30.0.16248370) from dl.google.com, verified with Google's published SHA-1
  and a pinned SHA-256, in a Debian trixie-slim image pinned by digest (packages from snapshot.debian.org). The
  image also has Go 1.27.3 (dl.google.com, pinned size and SHA-256) for eCapture and fzf, `bc` for eCapture's kernel
  headers, Rust 1.99.1 (static.rust-lang.org: `rustc`, `cargo` and the `aarch64-linux-android` standard library, pinned
  sizes and SHA-256) for ripgrep and fd, and the builder's own libelf/zlib headers for the native bpftool that
  generates the libbpf-tools skeletons.
- Target `aarch64-linux-android35`. API 35 (Android 15) is the floor, so bionic functions up to API 35 are used directly. `ndk/lib/api-site.py` generates a `CONFIG_SITE` that
  marks every bionic function introduced after API 35 as unavailable (the static `libc.a` contains them, so
  configure link tests would otherwise find them).
- Linkage rule: fully static (`-static`, NDK `libc.a`) unless the tool resolves host names. Static bionic has no
  netd client, so `getaddrinfo()` in a static binary cannot reach Android's resolver. Dynamic: nft, ipset, wg,
  bridge, ip-ng, tc-ng, ss-ng, mount.cifs, iperf3, tcpdump, curl, dig, host, mtr, socat, rsync, traceroute-ng,
  arping-ng, tracepath-ng, ncat, iftop, wg-quick, awg, awg-quick, nmap, nping, openssl, dropbear, dbclient/ssh, scp,
  dropbearkey, dropbearconvert, gdbserver, ltrace, fio, nstat, ifstat, lnstat, genl, devlink, rtmon, nslookup, delv,
  nsupdate, procan, filan, rg, fd, mount.nfs (and its three other names), git, adb, fastboot, simg2img, img2simg,
  lpunpack, lpmake. Everything else is static. C++ programs (nmap, nping, gdbserver, lldb-server, the android-tools
  programs) link the NDK libc++ statically.
- DNS: no resolv.conf is read or written. Dynamic tools resolve names through bionic/netd. `drill` (ldns) talks
  to a DNS server directly; without `@server` its wrapper adds `@<first DNS server of the active default
  network>` from `$ALTSHARE/dns-servers` (`dumpsys connectivity`, `getprop net.dns1/net.dns2` fallback; never a
  public resolver). `dig` and `host` (BIND) get the same servers through `ALT_DNS_SERVERS`, which their wrapper
  exports and a small dighost.c patch uses when neither `@server` (host: the server argument) nor a resolv.conf
  names one. `nslookup`, `delv` and `nsupdate` (BIND) have the same wrapper; for `delv` and `nsupdate` BIND's
  resolv.conf reader takes `ALT_DNS_SERVERS` in place of its localhost fallback (`delv @server` and nsupdate's
  `server` command still win).
- TLS/CA: curl uses mbedTLS 3.6 LTS with the Mozilla bundle from curl.se (pinned by sha256) as
  `$ALTDIR/etc/ssl/cert.pem`; the wrapper also passes `--capath /system/etc/security/cacerts` (or the conscrypt
  apex store) when present. mbedTLS loads every file of the directory, which works with Android's old-style
  hash names. BIND (dig, host), nmap and the `openssl` CLI use OpenSSL 3.5 LTS (static) with
  `$ALTDIR/etc/ssl/cert.pem` as the default CA file (`dig +tls`; `openssl s_client` verifies against it by default)
  and `$ALTDIR/etc/ssl/openssl.cnf` as the default configuration (`OPENSSL_CONF` overrides it).
- nmap: built with NSE (nmap's bundled Lua), OpenSSL and zlib, without libssh2. Its data directory is compiled in
  as `$ALTDIR/share/nmap`, so no `--datadir` is needed. Host names resolve through netd; nmap's own reverse-DNS
  resolver uses the active network's DNS servers (`ALT_DNS_SERVERS`, exported by the wrapper as for dig/host)
  because Android has no resolv.conf. `ncat` is built as before, without OpenSSL and Lua.
- dropbear: nothing starts it. Host keys, the pid file and `authorized_keys` (for every user) are in `/data/local/dropbear/`; as root without `-r` the `dropbear` wrapper creates that directory (mode 700) and passes `-R`, so host keys are generated on the first connection.
  Only public-key authentication is built in (no password login: Android has no shadow/crypt); the login shell
  is `/system/bin/sh` and the session `PATH` is bionic's default (`/product/bin:...:/system/bin:...`).
  `dbclient` (also installed as `ssh`) and `scp` keep `known_hosts` and the default identity `id_dropbear` in
  `$HOME/.ssh`, or in `/data/local/dropbear` when `HOME` is unset, `/` or not writable; `scp` runs the module's
  `dbclient`. Client password and keyboard-interactive authentication read the password from the terminal.
- iw uses libnl 3.12 (static). gdbserver is GNU gdb 18.1's (no in-process agent). ltrace is upstream 0.8.1 with
  its aarch64 backend and the bionic linker's library list; its prototype files are in `$ALTDIR/share/ltrace`.
  fio is built without SysV shared memory (bionic has none), so it runs jobs as threads.
- bpftool: built without LLVM and libbfd, so there is no JIT disassembly and no skeleton features.
- bpftrace tool scripts: run them with `bpftrace /system/etc/android-linux-tools/share/bpftrace/tools/<name>.bt`.
- bpftrace: LLVM/clang 23.1.5 (BPF backend only) linked statically, plus bcc's symbol helpers, the libbpf
  commit bpftrace pins, libelf, liblzma and libpcap. Its stdlib and headers are embedded, so it needs no
  files besides the program; kprobe, tracepoint and uprobe probes need a kernel with BTF
  (`/sys/kernel/btf/vmlinux`), BPF events and tracefs. Built without libdw (no DWARF-typed uprobe arguments),
  blazesym and libbfd disassembly.
  - Kernels without `CONFIG_FUNCTION_TRACER` have no `$TRACEFS/available_filter_functions`; bpftrace then warns
    and refuses `kprobe:` probes with "No matches". Upstream's bypass for that case is `--unsafe`
    (`bpftrace --unsafe -e 'kprobe:do_sys_openat2 { @c = count(); }'`): the name is not checked against the
    list, wildcards do not expand, and the kernel still rejects blacklisted functions. `--unsafe` also allows
    `system()` and other destructive builtins, so the wrapper does not add it.
  - Without `CONFIG_FTRACE_SYSCALLS` there is no `tracepoint:syscalls:*`; `tracepoint:raw_syscalls:sys_enter`
    and `sys_exit` (the syscall number is `args.id`) still work.
- eCapture 2.10.0 (`ecapture`): as upstream's Android release, the BPF objects of the Android modules (`tls` for
  OpenSSL/BoringSSL, `gotls`, `bash`) twice: CO-RE (used when the kernel has BTF) and non-CO-RE, compiled against
  arm64 kernel headers (used otherwise; `--btf=1`/`--btf=2` force one set); Go and cgo with the NDK clang, libpcap from the libpcap recipe,
  linked fully static. It needs root.
- ELF tools: GNU binutils 2.47 `objdump`, `nm`, `addr2line`, `readelf`, `strings` (aarch64 ELF target); elfutils
  0.197 `eu-stack`, `eu-readelf`, `eu-nm`, `eu-unstrip`, `eu-addr2line` (zlib only: no zstd-compressed sections or
  bzip2/xz-compressed files; no debuginfod, no C++ demangling); patchelf 0.19.3. On devices that ship `readelf`, `strings`, `nm` and so on,
  the installer renames the binutils wrappers to `<name>-ng`.
- Filesystem images: erofs-utils 1.9.4 (`mkfs.erofs`, `fsck.erofs`, `dump.erofs`; lz4/lz4hc, lzma, deflate, zstd;
  single-threaded, no FUSE) and squashfs-tools 4.7.5 (`mksquashfs`, `unsquashfs`; gzip, xz, lz4, zstd), with the
  zstd, xz and lz4 libraries of those recipes and the NDK zlib. dtc 1.8.1 with `fdtdump`, `fdtget`, `fdtput`,
  `fdtoverlay` (no YAML output). fatrace 0.19.1 reports file access events system-wide (fanotify, root).
- util-linux 2.42.4 also provides `nsenter-ng`, `unshare-ng`, `lsns`, `losetup`, `dmesg`, `wipefs`, `fallocate`,
  `zramctl`, `taskset`, `chrt`, `ionice`, `prlimit`, `rfkill`, `hexdump` and `script`; libcap `getcap`/`setcap`;
  libcap-ng `pscap`, `netcap`, `filecap`; e2fsprogs `debugfs`, `dumpe2fs`, `e2image`, `filefrag`; f2fs-tools
  `mkfs.f2fs`, `resize.f2fs`, `sload.f2fs` (no SELinux labelling), `f2fs_io`; iproute2 `nstat`, `ifstat`, `lnstat`,
  `genl`, `devlink`, `rtmon`; binutils `objcopy`, `strip`, `size`, `ar`, `c++filt`, `elfedit`; elfutils `eu-strip`,
  `eu-elflint`, `eu-elfcmp`, `eu-size`, `eu-elfclassify`; sqlite `sqldiff` and `sqlite3_rsync`; sysstat `sar` (its
  collector `sadc` is in `$ALTDIR/libexec`; daily files default to `/data/local/var/log/sa`); squashfs-tools
  `sqfstar`, `sqfscat`; socat `procan`, `filan`. Names that a device already has (`dmesg`, `losetup`, `hexdump`,
  `taskset`, `strip`, ...) are renamed to `<name>-ng` by the installer; `nsenter-ng` and `unshare-ng` always carry
  the suffix.
- bcc libbpf-tools 0.37.0: the 57 CO-RE tools of upstream's `libbpf-tools/` (`execsnoop`, `opensnoop`, `tcpconnect`,
  `biolatency`, `runqlat`, `offcputime`, `profile`, ...), each a static program with its BPF object embedded. They
  need root and a kernel with BTF (`/sys/kernel/btf/vmlinux`). Upstream's alias names are not installed: use
  `fsdist -t ext4` / `fsslower -t f2fs` (and so on) and `sigsnoop -k`.
- lldb-server: from LLVM 23.1.5 (the release bpftrace's LLVM is built from), static, for remote debugging with
  lldb (`lldb-server platform --listen '*:5039' --server` or `lldb-server gdbserver :5039 -- program`).
- rizin 0.9.1: upstream's Android configuration, one static program with the bundled capstone, tree-sitter and
  compression libraries; `rz-bin`, `rz-asm`, `rz-hash`, `rz-diff`, `rz-find`, `rz-gg`, `rz-ax`, `rz-run`, `rz-sign`
  and `rz-ar` are commands that start it as that program. Data files are in `$ALTDIR/share/rizin`.
- android-tools 37.0.0p1: `adb`, `fastboot`, `simg2img`, `img2simg`, `lpunpack`, `lpmake` from the AOSP sources in
  the nmeum/android-tools CMake packaging, with its bundled libusb (usbfs, no udev), fmt and BoringSSL, and
  protobuf 3.21.12, brotli, PCRE2, lz4 and zstd from this tree. `adb` keeps its key pair in `$HOME/.android`; the
  wrapper sets `HOME=/data/local/tmp` when `HOME` is unset or not writable. No mDNS discovery.
- git 2.56.1: with the https/http transport (libcurl with mbedTLS, CA file `$ALTDIR/etc/ssl/cert.pem`); ssh
  remotes use the `ssh` command in `PATH` (the module's dbclient). No Perl, Python or Tcl/Tk parts (`git add -p`
  is built in; no `git svn`, `git send-email`, gitk) and no WebDAV push. `git submodule`, `git mergetool`,
  `git request-pull`, `git filter-branch` and `git quiltimport` are shell scripts in `$ALTDIR/share/git-core`,
  started through aliases in `$ALTDIR/etc/gitconfig` with the module's bash. Pager `less`, default editor `nano`
  (`GIT_EDITOR`/`core.editor` override it). `git-upload-pack`, `git-receive-pack` and `git-upload-archive` are
  commands for serving a repository over ssh.
- ripgrep 15.2.0 (`rg`) and fd 10.5.2: built with cargo from their `Cargo.lock`; fd uses the system allocator
  (no bundled jemalloc), ripgrep is built without the optional PCRE2 engine. fzf 0.75.0 (Go, static). ncdu 1.22
  (the C line) with the module's terminfo. picocom 2024-07 (serial terminal; custom baud rates, flock locking).
- mount.nfs (nfs-utils 2.9.2, libtirpc 1.3.8): the NFS mount helper under its four upstream names (`mount.nfs`,
  `mount.nfs4`, `umount.nfs`, `umount.nfs4`), for kernels with the NFS client. NFSv4: `mount.nfs4 server:/export
  /mnt/point -o vers=4.2`. No GSS/Kerberos, no idmapd, no statd (NFSv3 mounts need `-o nolock`).
- WireGuard/AmneziaWG: `wg`, `awg` and the upstream Android `wg-quick`/`awg-quick` (`src/wg-quick/android.c`, a
  C program: no bash needed; it drives the stock `ip`, `iptables`, `ndc` and the netd DnsResolver over binder).
  awg-quick is patched to use the kernel `amneziawg` link type when the kernel has it, before falling back to
  userspace amneziawg-go, as upstream linux.bash does.
- Per-tool sources surveyed, patches and the reasons for each recipe's approach: `ndk/REFERENCES.md`.

## Building

```
./build-ndk.sh                 # build the image, all recipes, stage + check + zip the module into dist/
./build-ndk.sh --clean         # same after deleting .work/ndk/{build,out,stage} and the v2 files in dist/ (downloads kept)
./build-ndk.sh --clean-all     # like --clean and also delete the downloaded sources (.work/ndk/dl)
./build-ndk.sh curl strace     # only these recipes (and their dependencies), no packaging
./build-ndk.sh --image-only    # only build the container image
./build-ndk.sh --shell         # open a shell in the builder container
JOBS=8 MEM=12G ./build-ndk.sh  # make -j and memory limit (defaults)
```

- The host needs only docker (no `--privileged`; the container runs as the calling user with all capabilities
  dropped and `/src` read-only) and systemd. The run is wrapped in `systemd-run --user --scope
  -p MemoryMax=$MEM -p MemorySwapMax=0`, and the same limit is passed as `docker run --memory/--memory-swap`,
  which is what actually bounds the compilers. Network access is needed for the image and the source downloads
  (including the Go modules of eCapture and fzf, kept in `.work/ndk/dl/go-mod`, and the Rust crates of ripgrep
  and fd, kept in `.work/ndk/dl/cargo-home`; a rebuild with those caches runs offline).
- Everything else (NDK, autotools, meson, python, zip) is inside the image. Scratch space is `.work/ndk/`
  (`dl/` sources, `build/` trees and logs, `out/` binaries, `stage/`). Output: `dist/android-linux-tools-<ver>.zip`,
  its `.sha256` file, `dist/MANIFEST-v2.json` and `dist/phone-test.sh`.
- Files: `build-ndk.sh` (host entry point), `ndk/Dockerfile` (builder image), `ndk/build.sh` (driver),
  `ndk/lib/env.sh` (cross environment), `ndk/build.conf` (`V2_VERSION`, `MODULE_RELEASE`, `SOURCE_DATE_EPOCH`),
  `ndk/recipes.list` (build order), `ndk/recipes/<name>.sh`, `ndk/patches/<name>/*.patch`, `ndk/tools.tsv`
  (wrapper name, recipe, program, fixed arguments, DNS flag; in module order), `ndk/module/` (`customize.sh`,
  `alt-list`, `dns-servers`, `openssl.cnf`, `git/gitconfig`, `META-INF/`), `ndk/package.sh` and `ndk/scripts/` (`stage.py`, `check.py`,
  `manifest.py`, `layout_test.py`, `common.py`), `phone-test.sh` (self-check script).
- Recipes: `VERSION`, `URL`, `SHA256`, `CHECKSUM_SOURCE` (signature key fingerprint or the published checksum
  the sha256 was verified against when pinning), `LICENSE`, `DEPS`, optional `LINKAGE=dynamic`, `EXTRA_SRCS`
  (e.g. bash's official patch series) and a `build()` function. Runtime data of a program (nmap's,
  ltrace's, bpftrace's tool scripts, git's templates and scripts, rizin's data files) goes to `/work/out/data/rt/<recipe>/<path under $ALTDIR>` and is merged into the runtime tree. Each recipe builds against a private sysroot
  with only its declared dependencies and is cached by a hash of recipe, patches, environment and dependency
  hashes. A failed recipe stops the build before packaging.
- Patches are applied in order; each starts with a header saying why and citing its source (termux-packages,
  buildroot, or written for this module).
- Reproducible: two `./build-ndk.sh --clean` runs give byte-identical binaries, ZIP and MANIFEST
  (`SOURCE_DATE_EPOCH`, `-ffile-prefix-map`, sorted ZIP entries, fixed mtimes, `zip -X -D` in TZ=UTC), except
  `ecapture`: upstream's go-bindata step records the build-time mtimes of the BPF objects in the embedded asset.

## Releases

- Releases are published on Forgejo (<https://git.digtvbg.com/ivangotoy/android-linux-tools/releases>) with
  the ZIP and its `.sha256` file as assets (one ZIP from v2.3-r1; releases up to v2.2-r2 have both flavour ZIPs). A release tag is
  never moved; a fix gets a new `-rN`.
- Git refs reach GitHub through the Forgejo push mirror. `.forgejo/workflows/github-release.yml` runs when a
  `v*` tag is pushed, waits for that tag's Forgejo release to be published, and `ci/github-release.py` copies it to
  <https://github.com/ivangotoy/android-linux-tools/releases>: it waits for the mirrored tag at the same commit,
  creates the GitHub release on it, uploads every Forgejo asset and byte-verifies each upload. It never creates
  or moves a tag and never deletes anything. It can be re-run by hand (workflow_dispatch with the tag).

## History

- v1 (`v3.24-r1`, versionCode 32401): unmodified Alpine Linux aarch64 (musl) packages with a bundled musl
  loader and a resolv.conf overlay. Its builder was removed after v2.2-r1 (see git history).
- v2.0: NDK builds, hybrid with Alpine binaries for unported tools.
- v2.1: every tool is an NDK build; no musl runtime, no resolv.conf overlay.
- v2.2: runtime files under `/system/etc/android-linux-tools`, so the tools work for non-root users.
- v2.2-r2: same programs as v2.2-r1; adds the MIT `LICENSE` and drops the dead Alpine build code.
- v2.3-r1: adds bpftrace 0.27.1; the builder image gains `g++` and `xxd`; one ZIP instead of the lite/full
  flavours.
- v2.3-r2: same programs as v2.3-r1; removes device details from docs and shipped files; the installer no
  longer handles the old prototype module.
- v2.4-r1: adds nmap and nping (with NSE), the openssl CLI, dropbear (dropbear, dbclient/ssh, scp, dropbearkey,
  dropbearconvert), iw (with libnl), gdbserver, ltrace and fio.
- v2.5-r1: adds eCapture, the elfutils programs eu-stack, eu-readelf, eu-nm, eu-unstrip and eu-addr2line, GNU
  binutils objdump, nm, addr2line, readelf and strings, patchelf, dtc (with fdtdump, fdtget, fdtput, fdtoverlay),
  erofs-utils, squashfs-tools, fatrace and bpftrace's tool scripts; the builder image gains Go and `bc`.
- v2.6-r1: adds the bcc libbpf-tools, lldb-server, rizin, android-tools (adb, fastboot, simg2img, img2simg,
  lpunpack, lpmake), git, ripgrep, fd, fzf, ncdu, picocom and mount.nfs, and more programs of sources already
  built: util-linux (nsenter-ng, unshare-ng, lsns, losetup, dmesg, wipefs, fallocate, zramctl, taskset, chrt,
  ionice, prlimit, rfkill, hexdump, script), libcap (getcap, setcap), libcap-ng (pscap, netcap, filecap), e2fsprogs
  (debugfs, dumpe2fs, e2image, filefrag), f2fs-tools (mkfs.f2fs, resize.f2fs, sload.f2fs, f2fs_io), iproute2 (nstat,
  ifstat, lnstat, genl, devlink, rtmon), BIND (nslookup, delv, nsupdate), binutils (objcopy, strip, size, ar,
  c++filt, elfedit), elfutils (eu-strip, eu-elflint, eu-elfcmp, eu-size, eu-elfclassify), sqlite (sqldiff,
  sqlite3_rsync), sysstat (sar), squashfs-tools (sqfstar, sqfscat) and socat (procan, filan); the builder image
  gains Rust and the builder's libelf/zlib headers.

## Licences

The repository's own code (build scripts, recipes, staging and check scripts, and the module's own scripts:
the wrappers, `alt-list`, `customize.sh`, `dns-servers`, `openssl.cnf` and `phone-test.sh`) is MIT licensed, see `LICENSE`
(Copyright (c) 2026 Ivan Angelov). The ZIP ships it as `share/licenses/android-linux-tools/LICENSE`.

The bundled third-party tools keep their upstream licences. Their SPDX identifiers are listed in
`share/licenses/NOTICE.txt` inside the module and in `MANIFEST.json`; the licence files each package ships
are in `share/licenses/ndk/<package>/`, next to the patches applied to it. The patches in `ndk/patches/` (and
those copies) keep the terms of their upstream authors. The source of every bundled tool is the upstream
tarball named, with its sha256, in its recipe and in `MANIFEST.json`, plus the patches in `ndk/patches/`.
