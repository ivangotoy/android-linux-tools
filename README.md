# Android Linux tools

A root module that adds Linux userspace tools (netfilter, iproute2, WireGuard/AmneziaWG, tracing, packet
capture, DNS and network diagnostics, compression, editors, shells) to rooted aarch64 Android phones. Every
program is compiled from upstream source with the Android NDK for bionic (`aarch64-linux-android`, API 35).
The module does not depend on any particular device. It runs nothing at boot (no `post-fs-data.sh`,
`service.sh` or other boot script) and changes nothing on the device except the files the root manager
mounts from its `system/` tree.

- Repository: <https://git.digtvbg.com/ivangotoy/android-linux-tools> (Forgejo), mirrored to
  <https://github.com/ivangotoy/android-linux-tools>.
- Module id `android-linux-tools`, module directory `/data/adb/modules/android-linux-tools`.
- Version `v2.M-rN`, versionCode `major*100000 + minor*1000 + N` (`v2.2-r2` = `202002`), set in `ndk/build.conf`.
- Two ZIPs (flavours `lite` and `full`, see "Flavours"); tool list in "Contents".

## Install

- In the root manager app: Modules, Install from storage, pick the ZIP. Then reboot.
- Command line, as root: `ksud module install /sdcard/Download/android-linux-tools-v2.2-r2.zip` (KernelSU).
  Magisk (`magisk --install-module ZIP`) and APatch (`apd module install ZIP`) have the same module interface.
- Upgrading: install the new ZIP over the old one and reboot. The installer recognises wrappers of this
  module (also of v1/v2.0/v2.1 and of the `prototype-tools` prototype) and never renames them as device binaries.
- If the prototype module `prototype-tools` is installed, the installer creates its `remove` file and the manager
  deletes it on the next reboot. No other module is touched.
- The ZIP has the standard Magisk `META-INF/com/google/android/update-binary`; KernelSU and APatch use their own
  installer and run the same `customize.sh`. It uses only `ui_print`, `set_perm` and `set_perm_recursive` (with
  fallbacks if they are missing) and no manager-specific command (`ndk/scripts/check.py` enforces that).

Root managers: KernelSU (with a metamodule such as NoMount or meta-overlayfs), Magisk and APatch; the details are in
`ndk/REFERENCES.md`, "Runtime layout".

## Runtime layout

`/data/adb` is `0700 root`, so nothing a tool needs at run time is read from the module directory. Every
runtime file is in the module's `system/` tree, which the root manager mounts over `/system`:

| Module path | Device path | Contents |
|---|---|---|
| `system/bin/` | `/system/bin` | wrappers and `alt-list` (names after the `-ng` rule) |
| `system/etc/android-linux-tools/libexec/` | `$ALTDIR/libexec` | every ELF program |
| `system/etc/android-linux-tools/share/terminfo/` | `$ALTDIR/share/terminfo` | terminfo (compiled-in default of ncurses) |
| `system/etc/android-linux-tools/etc/ssl/cert.pem` | `$ALTDIR/etc/ssl/cert.pem` | Mozilla CA bundle (curl, OpenSSL default) |
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
also run without root, with the permissions of the calling user. Tested: uid 2000 from a real `adb shell` and
through `phone-test.sh` (see "Testing"); Termux and apps use the same files but are not tested separately.
Operations that need root or capabilities (nft, ipset, conntrack, `bpftool prog list`, creating links with
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
   (older versions, `prototype-tools`) line in their first 400 bytes, so an upgrade never renames a wrapper because
   of the previous version's copy (`check.py` requires that marker in every wrapper).
3. `alt-list` prints the installed command names and marks the renamed ones; `alt-list -r` prints only the
   renames; `alt-list -m` prints the map (`tool installed-name device-path-or--`).

The set of command names can therefore differ between phones (for example `curl` becomes `curl-ng` on a
phone that ships a `curl`). Use `alt-list` to see what a phone has.

## Flavours

| ZIP | Contents |
|---|---|
| `android-linux-tools-<ver>.zip` | flavour `lite` |
| `android-linux-tools-full-<ver>.zip` | flavour `full` |

Since v2.1 both flavours contain the same programs and wrappers (including bpftool, built without LLVM). They
differ only in the `flavour=` key and description of `module.prop`, the `flavour` field of `MANIFEST.json`
and the NOTICE header. Both use the same module id and versionCode, so installing one replaces the other.
(Up to v2.0 the full flavour added the Alpine bpftool with libLLVM, about 172 MB.)

## Contents (v2.2-r2)

66 commands plus `alt-list`, 61 ELF programs; there is no `lib/` directory. Sizes are of the stripped
`$ALTDIR/libexec/` programs. Linkage `dynamic` = PIE against the system `libc.so`/`libm.so`/`libdl.so`
(`libz.so` for curl) only, every third-party library linked in statically. Generated from
`dist/MANIFEST-v2.json` of the v2.2-r2 build.

| ZIP | Bytes | Unpacked |
|---|---|---|
| `android-linux-tools-v2.2-r2.zip` | 26140651 | 53.6 MB |

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
| `dig` | bind | 9.20.30 | dynamic | 8159 | MPL-2.0 |
| `host` | bind | 9.20.30 | dynamic | 8126 | MPL-2.0 |
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
| `alt-list` | (module script) | | | | MIT |

`$ALTSHARE/MANIFEST.json` (and `dist/MANIFEST-v2.json`) records per tool the recipe, upstream version, source
URL and sha256, how the checksum was verified, licence, patches, dependencies, linkage and DNS method;
`$ALTSHARE/origins.txt` has one line per tool for `phone-test.sh`.

## Build and runtime details

- Toolchain: Android NDK r30 (LTS, 30.0.16248370) from dl.google.com, verified with Google's published SHA-1
  and a pinned SHA-256, in a Debian trixie-slim image pinned by digest (packages from snapshot.debian.org).
- Target `aarch64-linux-android35`. API 35 (Android 15) is the floor: the oldest tested phone runs Android 15,
  so bionic functions up to API 35 are used directly. `ndk/lib/api-site.py` generates a `CONFIG_SITE` that
  marks every bionic function introduced after API 35 as unavailable (the static `libc.a` contains them, so
  configure link tests would otherwise find them).
- Linkage rule: fully static (`-static`, NDK `libc.a`) unless the tool resolves host names. Static bionic has no
  netd client, so `getaddrinfo()` in a static binary cannot reach Android's resolver. Dynamic: nft, ipset, wg,
  bridge, ip-ng, tc-ng, ss-ng, mount.cifs, iperf3, tcpdump, curl, dig, host, mtr, socat, rsync, traceroute-ng,
  arping-ng, tracepath-ng, ncat, iftop, wg-quick, awg, awg-quick. Everything else is static.
- DNS: no resolv.conf is read or written. Dynamic tools resolve names through bionic/netd. `drill` (ldns) talks
  to a DNS server directly; without `@server` its wrapper adds `@<first DNS server of the active default
  network>` from `$ALTSHARE/dns-servers` (`dumpsys connectivity`, `getprop net.dns1/net.dns2` fallback; never a
  public resolver). `dig` and `host` (BIND) get the same servers through `ALT_DNS_SERVERS`, which their wrapper
  exports and a small dighost.c patch uses when neither `@server` (host: the server argument) nor a resolv.conf
  names one.
- TLS/CA: curl uses mbedTLS 3.6 LTS with the Mozilla bundle from curl.se (pinned by sha256) as
  `$ALTDIR/etc/ssl/cert.pem`; the wrapper also passes `--capath /system/etc/security/cacerts` (or the conscrypt
  apex store) when present. mbedTLS loads every file of the directory, which works with Android's old-style
  hash names. BIND (dig, host) uses OpenSSL 3.5 LTS (static) with `$ALTDIR/etc/ssl/cert.pem` as its default CA
  file (`dig +tls`).
- bpftool: built without LLVM and libbfd, so there is no JIT disassembly and no skeleton features.
- WireGuard/AmneziaWG: `wg`, `awg` and the upstream Android `wg-quick`/`awg-quick` (`src/wg-quick/android.c`, a
  C program: no bash needed; it drives the stock `ip`, `iptables`, `ndc` and the netd DnsResolver over binder).
  awg-quick is patched to use the kernel `amneziawg` link type when the kernel has it, before falling back to
  userspace amneziawg-go, as upstream linux.bash does.
- Per-tool sources surveyed, patches and the reasons for each recipe's approach: `ndk/REFERENCES.md`.

## Building

```
./build-ndk.sh                 # build the image, all recipes, stage + check + zip both flavours into dist/
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
  which is what actually bounds the compilers. Network access is needed for the image and the source downloads.
- Everything else (NDK, autotools, meson, python, zip) is inside the image. Scratch space is `.work/ndk/`
  (`dl/` sources, `build/` trees and logs, `out/` binaries, `stage/`). Output: `dist/android-linux-tools-<ver>.zip`,
  `dist/android-linux-tools-full-<ver>.zip`, their `.sha256` files, `dist/MANIFEST-v2.json` and
  `dist/phone-test.sh`.
- Files: `build-ndk.sh` (host entry point), `ndk/Dockerfile` (builder image), `ndk/build.sh` (driver),
  `ndk/lib/env.sh` (cross environment), `ndk/build.conf` (`V2_VERSION`, `MODULE_RELEASE`, `SOURCE_DATE_EPOCH`),
  `ndk/recipes.list` (build order), `ndk/recipes/<name>.sh`, `ndk/patches/<name>/*.patch`, `ndk/tools.tsv`
  (wrapper name, recipe, program, fixed arguments, DNS flag; in module order), `ndk/module/` (`customize.sh`,
  `alt-list`, `dns-servers`, `META-INF/`), `ndk/package.sh` and `ndk/scripts/` (`stage.py`, `check.py`,
  `manifest.py`, `layout_test.py`, `common.py`), `phone-test.sh`.
- Recipes: `VERSION`, `URL`, `SHA256`, `CHECKSUM_SOURCE` (signature key fingerprint or the published checksum
  the sha256 was verified against when pinning), `LICENSE`, `DEPS`, optional `LINKAGE=dynamic`, `EXTRA_SRCS`
  (e.g. bash's official patch series) and a `build()` function. Each recipe builds against a private sysroot
  with only its declared dependencies and is cached by a hash of recipe, patches, environment and dependency
  hashes. A failed recipe stops the build before packaging.
- Patches are applied in order; each starts with a header saying why and citing its source (termux-packages,
  buildroot, or written for this module).
- Reproducible: two `./build-ndk.sh --clean` runs give byte-identical binaries, ZIPs and MANIFEST
  (`SOURCE_DATE_EPOCH`, `-ffile-prefix-map`, sorted ZIP entries, fixed mtimes, `zip -X -D` in TZ=UTC).

## Testing

Host checks (`ndk/package.sh`, every build, no aarch64 code is executed):
- `ndk/scripts/check.py`, per flavour: every program is AArch64 in `$ALTDIR/libexec` (no ELF elsewhere, no
  `lib/`); static programs are `statically linked` with no `DT_NEEDED`; dynamic ones are PIE with interpreter
  `/system/bin/linker64`, `DT_NEEDED` only libc/libm/libdl/liblog/libz, no RUNPATH and an Android note of API
  35; no builder or home paths and no `/data/adb` path in any ELF; every wrapper's target exists, its `ALTDIR`
  marker is in the first 400 bytes and it has no `$MODDIR`/`/data/adb` path; `sh -n` and `bash --posix -n` on
  every script; no boot scripts; no manager-specific commands in `customize.sh`; `module.prop` fields; terminfo
  and CA bundle present; every version pattern of `phone-test.sh` found in the program's ELF strings.
- `ndk/package.sh`: `unzip -t`, `zip -T`, no host paths and no `.work`/`__pycache__` entries in the ZIPs.
- `ndk/scripts/layout_test.py`, per ZIP: unzips it under a simulated `data/adb/modules/android-linux-tools`
  (0700), runs its `customize.sh` with `set_perm` stubs and checks, as a non-root user would see it, that every
  `$ALTDIR` path of every wrapper exists and is readable (programs: executable) through every directory, that
  nothing refers to `/data/adb`, and owner, label and mode of every file under `system/`. Also usable on the
  host: `python3 -I ndk/scripts/layout_test.py ZIP NEW-EMPTY-DIR`.

Phone test: `sh /system/etc/android-linux-tools/share/android-linux-tools/phone-test.sh` (also
`dist/phone-test.sh`).
- As root it runs every check: installed tools (from `alt-list -m`) and that renamed ones do not shadow device
  binaries, origins (all `ndk`, no musl loader), no v2.1 runtime leftovers in the module directory, version
  banners, functional tests (nft, ipset, conntrack, `nfct timeout list`, `wg show`, `bridge link`,
  `tc-ng qdisc`, `ethtool-ng lo`, getfacl, `mount.cifs -h`, `bpftool prog list`, an `amneziawg` link when the
  kernel has that link type, zstd/xz/lz4 round trips, jq, sqlite3, bash, a tmux session, lsblk, findmnt) and DNS without resolv.conf (`curl -sI https://example.com`, `drill example.com`, `dig +short
  example.com`, `host example.com`).
- It then repeats the non-root checks as uid 2000: first with the module's `setpriv --reuid=2000 --regid=2000
  --groups=3003,3009` (inet and readproc, as a real adb shell has; without inet netd refuses DNS), else
  `su 2000 -c`, `su shell -c` or `su -s /system/bin/sh 2000 -c`; SKIP if none gives uid 2000. `setpriv`/`su`
  keep root's SELinux domain, so this tests file permissions; running the script from `adb shell` also tests
  the `shell` domain.
- As a non-root user (`adb shell`, Termux) or with `--nonroot` it runs only the non-root checks: every wrapper
  resolves in `PATH`, has no `/data/adb` path and its `$ALTDIR/libexec` target is readable and executable; the
  runtime data is readable; versions of dig, drill, curl, jq, htop, tmux, nano, less, awg and bpftool; the DNS
  checks.
- Kernel features are read from `/proc/config.gz`; a missing feature is a SKIP, not a failure. The script
  cleans up everything it creates and ends with `TOTAL pass=N fail=M`.

Tested devices (v2.2-r1, root manager KernelSU with NoMount; root run plus the uid 2000 run, 0 failures; the
skips are kernel features the device lacks):

| Device | Android | Kernel | Result |
|---|---|---|---|

## Releases

- Releases are published on Forgejo (<https://git.digtvbg.com/ivangotoy/android-linux-tools/releases>) with
  both ZIPs and their `.sha256` files as assets. A release tag is never moved; a fix gets a new `-rN`.
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

## Licences

The repository's own code (build scripts, recipes, staging and check scripts, and the module's own scripts:
the wrappers, `alt-list`, `customize.sh`, `dns-servers` and `phone-test.sh`) is MIT licensed, see `LICENSE`
(Copyright (c) 2026 Ivan Angelov). The ZIPs ship it as `share/licenses/android-linux-tools/LICENSE`.

The bundled third-party tools keep their upstream licences. Their SPDX identifiers are listed in
`share/licenses/NOTICE.txt` inside the module and in `MANIFEST.json`; the licence files each package ships
are in `share/licenses/ndk/<package>/`, next to the patches applied to it. The patches in `ndk/patches/` (and
those copies) keep the terms of their upstream authors. The source of every bundled tool is the upstream
tarball named, with its sha256, in its recipe and in `MANIFEST.json`, plus the patches in `ndk/patches/`.
