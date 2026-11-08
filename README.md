# Android Linux tools

A root module that adds Linux userspace tools (netfilter, iproute2, tracing, network diagnostics,
compression, editors, shells) to rooted aarch64 Android phones. The binaries are unmodified
Alpine Linux aarch64 (musl) packages. Only their ELF interpreter and RUNPATH are changed with
`patchelf`, so they load the bundled musl from the module directory. The module does not depend
on any particular device. It runs nothing at boot (there is no `post-fs-data.sh` or `service.sh`),
and it does not change device state except through the files mounted under `system/`.

- Module id: `android-linux-tools`. Install path: `/data/adb/modules/android-linux-tools`,
  which is the same under Magisk, KernelSU (with or without a metamodule) and APatch.
- Version: `<alpine-branch>-rN`, for example `v3.24-r1`. versionCode is `major*10000 + minor*100 + N`,
  for example `32401`.
- Layout: ELF programs are in `libexec/`. Shared libraries and `ld-musl-aarch64.so.1` are in `lib/`.
  Small `#!/system/bin/sh` wrappers are in `system/bin/`. Terminfo is in `share/terminfo`, and the CA
  bundle is `etc/ssl/cert.pem`.

## v2: native Android (bionic) builds with the NDK

v2 (`v2.M-rN`, versionCode `major*100000 + minor*1000 + N`, e.g. `201001` for `v2.1-r1`, above every v1 code)
keeps the module id, name, the `-ng` rule and both flavours of v1, but compiles the tools from upstream source
with the Android NDK instead of shipping Alpine/musl binaries. Since v2.1 every tool is an NDK build: the ZIPs
contain no Alpine/musl binary, no musl loader or libraries and no resolv.conf overlay, and use
`ndk/module/customize.sh` (v1's `module/customize.sh` without the musl and resolv.conf code). v2.0 was a hybrid
that kept the v1 Alpine binary for unported tools; `ALLOW_ALPINE=1` in `ndk/build.conf` re-enables that fallback. `share/android-linux-tools/MANIFEST.json` (and `dist/MANIFEST-v2.json`)
records per tool its origin (`ndk` or `alpine`), upstream version, source sha256, linkage and patches;
`share/android-linux-tools/origins.txt` is the same in one line per tool for `phone-test.sh`.

- Toolchain: Android NDK r30 (LTS, 30.0.16248370) from dl.google.com, verified with Google's published SHA-1
  and a pinned SHA-256, in a Debian trixie-slim image pinned by digest (packages from snapshot.debian.org).
- Target: `aarch64-linux-android35`. API 35 (Android 15) is the floor: the oldest of the phones this
  is built for runs Android 15 (the others run 16 and 17), so bionic functions up to API 35 are used
  directly instead of compatibility fallbacks.
- Linkage rule: fully static (`-static`, NDK `libc.a`) unless the tool resolves host names. Static bionic has
  no netd client, so `getaddrinfo()` in a static binary cannot reach Android's resolver. Tools that call the
  libc resolver are PIEs linked against the system `libc.so`/`libm.so`/`libdl.so` (`libz.so` for curl) only,
  with every third-party library linked in statically: no `$MODDIR/lib`, no RUNPATH.
  Dynamic: nft, ipset, wg, wg-quick, awg, awg-quick, ip-ng, tc-ng, ss-ng, bridge, tcpdump, curl, dig, host, mtr,
  socat, iperf3, rsync, ncat, iftop, mount.cifs, traceroute-ng, arping-ng, tracepath-ng. Everything else is static.
- DNS: NDK tools resolve names through bionic/netd, so they need no resolv.conf. `drill` (ldns) is a DNS query
  tool that talks to a server directly; when no `@server` is given its wrapper adds `@<first DNS server of the
  active default network>` from `share/android-linux-tools/dns-servers` (dumpsys connectivity, getprop fallback).
  `dig` and `host` (BIND) get the same servers through `ALT_DNS_SERVERS`, which their wrapper exports and a
  small dighost.c patch uses when neither `@server` (host: the server argument) nor a resolv.conf names one.
  The v1 resolv.conf overlay and `resolv-refresh` were only shipped while Alpine network tools remained (v2.0-r1:
  dig, host, mount.cifs); v2.1 ships neither.
- TLS/CA: curl uses mbedTLS 3.6 LTS with the Mozilla bundle from curl.se (pinned by sha256) as
  `etc/ssl/cert.pem`; the wrapper also passes `--capath /system/etc/security/cacerts` (or the conscrypt apex
  store) when present. mbedTLS loads every file of the directory, which works with Android's old-style hash names.
- BIND (dig, host) uses OpenSSL 3.5 LTS (static) with `etc/ssl/cert.pem` as its default CA file (`dig +tls`).
- bpftool: both flavours ship the NDK bpftool (no LLVM: no JIT disassembly, no skeleton features). v2.0's full
  flavour kept the v1 Alpine bpftool with libLLVM (about 172 MB); since v2.1 lite and full contain the same
  tools and differ only in `flavour=` and the description, so either ZIP can be installed.
- WireGuard/AmneziaWG: `wg`, `awg` (amneziawg-tools 3.1.20260812) and the upstream Android `wg-quick`/`awg-quick`
  (`src/wg-quick/android.c`, a C program: no bash needed; it drives the stock `ip`, `iptables`, `ndc` and the
  netd DnsResolver over binder). awg-quick is patched to use the kernel `amneziawg` link type (e.g. a custom
  kernel's built-in AmneziaWG) before falling back to userspace amneziawg-go, as upstream linux.bash does.
- New in v2: `ethtool-ng` (always `-ng`), `drill`, `wg-quick`, `awg`, `awg-quick`. Ported in v2.1: `nfct`,
  `dig`, `host`, `mount.cifs`, and bpftool in the full flavour. Reasons and sources per tool: `ndk/REFERENCES.md`.

### v2.1 contents

Both flavours contain the same 66 NDK tools (plus `alt-list`); there is no `lib/` directory. Sizes are of the stripped `libexec/` programs; `Linkage` dynamic = PIE against the system `libc.so`/`libm.so`/`libdl.so` (`libz.so` for curl) only. Generated from `dist/MANIFEST-v2.json`.

| ZIP | Bytes | Unpacked |
|---|---|---|
| `android-linux-tools-v2.1-r1.zip` | 26070503 | 53.5 MB |
| `android-linux-tools-full-v2.1-r1.zip` | 26070596 | 53.5 MB |

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
| `alt-list` | (module script) | | | | |

### Builder

```
./build-ndk.sh                 # build the image, all recipes, stage + check + zip both flavours into dist/
./build-ndk.sh --clean         # same after deleting .work/ndk/{build,out,stage} and the v2 files in dist/ (downloads kept)
./build-ndk.sh --clean-all     # also delete downloaded sources and Alpine apks
./build-ndk.sh curl strace     # only these recipes (and their dependencies), no packaging
./build-ndk.sh --image-only    # only build the container image
JOBS=8 MEM=12G ./build-ndk.sh  # make -j and memory limit (defaults)
```

- The host needs only docker (docker group, no `--privileged`; the container runs as the calling user with all
  capabilities dropped) and systemd. The run is wrapped in `systemd-run --user --scope -p MemoryMax=12G
  -p MemorySwapMax=0`; because the container itself runs under dockerd, the same limit is also passed as
  `docker run --memory 12G --memory-swap 12G`, which is what actually bounds the compilers.
- Everything else (NDK, autotools, meson, python, zip, patchelf) is inside the image. Scratch space is
  `.work/ndk/` (`dl/` sources, `build/` trees and logs, `out/` binaries, `stage/`, `alpine/` v1 apks).
- `ndk/Dockerfile` builder image; `ndk/build.sh` driver; `ndk/lib/env.sh` cross environment;
  `ndk/lib/api-site.py` generates a `CONFIG_SITE` that marks every bionic function introduced after API 35 as
  unavailable (the static `libc.a` contains them, so configure link tests would otherwise find them).
- `ndk/recipes/<name>.sh`: `VERSION`, `URL`, `SHA256`, `CHECKSUM_SOURCE` (signature key fingerprint or the
  published checksum the sha256 was verified against when pinning), `LICENSE`, `DEPS`, optional `LINKAGE=dynamic`,
  `EXTRA_SRCS` (e.g. bash's official patch series) and a `build()` function. `ndk/recipes.list` is the build order.
- `ndk/patches/<name>/*.patch` are applied in order; each starts with a header saying why and citing its source
  (termux-packages, buildroot, or written for this module). `ndk/REFERENCES.md` records, per tool, the sources
  surveyed (AOSP, termux-packages, Alpine, buildroot, OpenWrt, LineageOS, GitHub ports), what they do and why the
  recipe's approach was chosen.
- Each recipe builds against a private sysroot with only its declared dependencies, and is cached by a hash of
  recipe, patches, environment and dependency hashes.
- `ndk/tools.tsv` maps wrapper names to NDK binaries; every other name of `config/tools.tsv` uses the v1 Alpine
  binary, fetched and verified by the unchanged v1 `scripts/fetch.py` from `alpine.lock.json`.
- `ndk/package.sh` stages, checks and zips both flavours (`ndk/scripts/stage.py`, `check.py`, `manifest.py`).
  The host checks run no aarch64 code: AArch64 machine; NDK static binaries `statically linked` with no
  `DT_NEEDED`; NDK dynamic binaries PIE with interpreter `/system/bin/linker64`, `DT_NEEDED` only libc/libm/libdl/
  liblog/libz, no RUNPATH and an Android note of API 35; Alpine binaries with the v1 musl interpreter, RUNPATH and
  library closure; no builder or home paths in any ELF or ZIP; `sh -n` and `bash --posix -n` on every script;
  version patterns of `phone-test.sh` found in the ELF strings.
- Reproducible: two `./build-ndk.sh --clean` runs give byte-identical binaries, ZIPs and MANIFEST
  (SOURCE_DATE_EPOCH from `config/build.conf`, `-ffile-prefix-map`, sorted ZIP entries, fixed mtimes).
- Release settings: `ndk/build.conf` (`V2_VERSION`, `MODULE_RELEASE`).

### Phone test (v2)

`phone-test.sh` prints `ORIGIN <tool> <installed-name> <ndk|alpine> <version> <linkage>` for every tool and
checks that all origins are `ndk` and that no musl loader is installed. The DNS section needs no resolv.conf:
`curl -sI https://example.com`, `drill example.com`, `dig +short example.com` and `host example.com` are run
with their origin in the label. New checks in v2.1: versions of nfct, wg-quick, awg, awg-quick; `nfct timeout
list`; `mount.cifs -h`; `bpftool prog list`; and, if the kernel has the `amneziawg` link type, `ip-ng link add
awgt0 type amneziawg`, `awg show awgt0` and the delete (SKIP otherwise). The resolv.conf overlay is only
checked when the build still ships `resolv-refresh`.

The sections below describe v1 (Alpine). Since v2.1 no Alpine binary is left in the v2 ZIPs, so the v1 DNS overlay
and musl details below apply only to the v1 ZIPs built by `./build.sh`.

## Flavours

Both flavours use the same module id and versionCode, so only one can be installed at a time.
Installing one replaces the other.

| ZIP | Contents |
|---|---|
| `android-linux-tools-<ver>.zip` (lite) | Everything except bpftool. About 46 MB unpacked. |
| `android-linux-tools-full-<ver>.zip` (full) | Lite plus `bpftool` and `libLLVM` (about 172 MB for libLLVM alone). About 222 MB unpacked. |

Alpine's `bpftool` has a hard `DT_NEEDED` on `libLLVM.so.*`, which it uses for JIT disassembly.
musl resolves all symbols at load time, so bpftool cannot start without libLLVM. For that reason
the lite flavour leaves bpftool out instead of shipping a broken binary. The `flavour=` key in
`module.prop` and the module description show which flavour is installed.

## Tools

| Command | Alpine package | Version | Licence (SPDX) | DNS refresh | Flavour |
|---|---|---|---|---|---|
| `nft` | nftables | 1.1.6-r1 | GPL-2.0-or-later |  | both |
| `ipset` | ipset | 7.24-r0 | GPL-2.0-only |  | both |
| `conntrack` | conntrack-tools | 1.4.9-r0 | GPL-2.0-or-later |  | both |
| `nfct` | conntrack-tools | 1.4.9-r0 | GPL-2.0-or-later |  | both |
| `wg` | wireguard-tools-wg | 1.0.20260223-r0 | GPL-2.0-only | yes | both |
| `bridge` | iproute2 | 7.0.0-r0 | GPL-2.0-or-later |  | both |
| `ip-ng` | iproute2-minimal | 7.0.0-r0 | GPL-2.0-or-later |  | both |
| `tc-ng` | iproute2-tc | 7.0.0-r0 | GPL-2.0-or-later |  | both |
| `ss-ng` | iproute2-ss | 7.0.0-r0 | GPL-2.0-or-later | yes | both |
| `bpftool` | bpftool | 7.1.5-r0 | GPL-2.0-only |  | full only |
| `getfacl` | acl | 2.3.2-r1 | LGPL-2.1-or-later AND GPL-2.0-or-later |  | both |
| `setfacl` | acl | 2.3.2-r1 | LGPL-2.1-or-later AND GPL-2.0-or-later |  | both |
| `mount.cifs` | cifs-utils | 7.5-r1 | GPL-3.0-or-later | yes | both |
| `iperf3` | iperf3 | 3.20-r0 | BSD-3-Clause-LBNL | yes | both |
| `tcpdump` | tcpdump | 4.99.6-r1 | BSD-3-Clause | yes | both |
| `strace` | strace | 6.19-r1 | BSD-3-Clause |  | both |
| `capsh` | libcap-utils | 2.78-r0 | BSD-3-Clause OR GPL-2.0-only |  | both |
| `getpcaps` | libcap-utils | 2.78-r0 | BSD-3-Clause OR GPL-2.0-only |  | both |
| `setpriv` | setpriv | 2.42.3-r1 | GPL-2.0-or-later |  | both |
| `lsblk` | lsblk | 2.42.3-r1 | GPL-2.0-or-later |  | both |
| `blkid-ng` | blkid | 2.42.3-r1 | LGPL-1.0-only |  | both |
| `findmnt` | findmnt | 2.42.3-r1 | GPL-2.0-or-later |  | both |
| `lscpu` | lscpu | 2.42.3-r1 | GPL-2.0-or-later |  | both |
| `curl` | curl | 8.23.0-r0 | curl | yes | both |
| `dig` | bind-tools | 9.20.30-r0 | MPL-2.0 | yes | both |
| `host` | bind-tools | 9.20.30-r0 | MPL-2.0 | yes | both |
| `mtr` | mtr | 0.96-r2 | GPL-2.0-only | yes | both |
| `socat` | socat | 1.8.1.3-r0 | GPL-2.0-only WITH OpenSSL-Exception | yes | both |
| `htop` | htop | 3.5.3-r0 | GPL-2.0-or-later |  | both |
| `iostat` | sysstat | 12.7.8-r0 | GPL-2.0-or-later |  | both |
| `pidstat` | sysstat | 12.7.8-r0 | GPL-2.0-or-later |  | both |
| `mpstat` | sysstat | 12.7.8-r0 | GPL-2.0-or-later |  | both |
| `sqlite3` | sqlite | 3.53.4-r0 | blessing |  | both |
| `rsync` | rsync | 3.5.2-r1 | GPL-3.0-or-later | yes | both |
| `zstd` | zstd | 1.5.7-r2 | BSD-3-Clause OR GPL-2.0-or-later |  | both |
| `unzstd` | zstd | 1.5.7-r2 | BSD-3-Clause OR GPL-2.0-or-later |  | both |
| `zstdcat` | zstd | 1.5.7-r2 | BSD-3-Clause OR GPL-2.0-or-later |  | both |
| `xz` | xz | 5.8.4-r0 | GPL-2.0-or-later AND 0BSD AND Public-Domain AND LGPL-2.1-or-later |  | both |
| `unxz` | xz | 5.8.4-r0 | GPL-2.0-or-later AND 0BSD AND Public-Domain AND LGPL-2.1-or-later |  | both |
| `xzcat` | xz | 5.8.4-r0 | GPL-2.0-or-later AND 0BSD AND Public-Domain AND LGPL-2.1-or-later |  | both |
| `lz4` | lz4 | 1.10.0-r1 | BSD-2-Clause AND GPL-2.0-or-later |  | both |
| `unlz4` | lz4 | 1.10.0-r1 | BSD-2-Clause AND GPL-2.0-or-later |  | both |
| `lz4cat` | lz4 | 1.10.0-r1 | BSD-2-Clause AND GPL-2.0-or-later |  | both |
| `e2fsck-ng` | e2fsprogs | 1.47.4-r0 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |  | both |
| `mke2fs-ng` | e2fsprogs | 1.47.4-r0 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |  | both |
| `tune2fs-ng` | e2fsprogs-extra | 1.47.4-r0 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |  | both |
| `resize2fs-ng` | e2fsprogs-extra | 1.47.4-r0 | GPL-2.0-or-later AND LGPL-2.0-or-later AND BSD-3-Clause AND MIT |  | both |
| `fsck.f2fs-ng` | f2fs-tools | 1.16.0-r4 | GPL-2.0-or-later OR LGPL-2.1-or-later |  | both |
| `dump.f2fs-ng` | f2fs-tools | 1.16.0-r4 | GPL-2.0-or-later OR LGPL-2.1-or-later |  | both |
| `traceroute-ng` | traceroute | 2.1.6-r0 | GPL-2.0-or-later | yes | both |
| `arping-ng` | iputils-arping | 20250605-r2 | BSD-3-Clause AND GPL-2.0-or-later | yes | both |
| `tracepath-ng` | iputils-tracepath | 20250605-r2 | BSD-3-Clause AND GPL-2.0-or-later | yes | both |
| `tmux` | tmux | 3.7c-r0 | ISC |  | both |
| `nano` | nano | 9.3-r0 | GPL-3.0-or-later |  | both |
| `less` | less | 702-r0 | GPL-3.0-or-later OR BSD-2-Clause |  | both |
| `jq` | jq | 1.8.2-r0 | MIT |  | both |
| `bash` | bash | 5.3.9-r1 | GPL-3.0-or-later |  | both |
| `ncat` | nmap-ncat | 7.99-r0 | custom | yes | both |
| `iftop` | iftop | 1.0_pre4-r0 | GPL-2.0-or-later | yes | both |
| `tree` | tree | 2.3.2-r0 | GPL-2.0-or-later |  | both |
| `pv` | pv | 1.10.5-r0 | Artistic-2.0 |  | both |
| `alt-list` | (module script) | | | | both |

The versions are those pinned in `alpine.lock.json`. Per-file origins and the sha256 of every apk are
in `dist/MANIFEST.json` and, inside the module, in `share/android-linux-tools/MANIFEST.json`.

## Never shadowing device binaries: the `-ng` rule

1. Some tools always ship with an `-ng` suffix, because the upstream tool is wanted next to the stock
   Android one: `ip-ng tc-ng ss-ng blkid-ng e2fsck-ng mke2fs-ng tune2fs-ng resize2fs-ng
   fsck.f2fs-ng dump.f2fs-ng traceroute-ng arping-ng tracepath-ng`. These names never change.
   For example, `tc-ng` can parse CAKE options and the stock `tc` cannot.
2. Every other wrapper is checked on the device at install time. `customize.sh` looks for each name in
   `/system/bin /system/xbin /system_ext/bin /product/bin /vendor/bin /vendor/xbin /odm/bin /apex/*/bin`.
   If the device already has that name, the wrapper is renamed to `<name>-ng`, or `<name>-ng-ng` if
   `<name>-ng` is also taken. The installer prints each rename. Wrappers left by this module or by the
   old `prototype-tools` prototype are not counted as device binaries.
3. `alt-list` prints the installed command names and marks the renamed ones. `alt-list -r` prints only
   the renames, and `alt-list -m` prints a machine-readable map (`tool installed-name device-path`).

Because of this, the set of command names can differ between phones. Use `alt-list` to see what a
given phone has.

## DNS

Android has no `/etc/resolv.conf` and no resolver listening on `127.0.0.1:53` or `::1:53`. Bionic resolves
names through netd. musl, c-ares (used by curl) and BIND (used by dig and host) read `/etc/resolv.conf`,
so without that file they fail. The prototype hit this: curl returned rc=6 and dig returned rc=9.

- At install time, if the device has no `/system/etc/resolv.conf`, the module adds
  `system/etc/resolv.conf` as a symlink to `/data/adb/modules/android-linux-tools/etc/resolv.conf`.
  If the device does ship one, the module leaves it alone.
- These wrappers call `share/android-linux-tools/resolv-refresh` before they run: curl, dig, host, mtr,
  socat, ncat, traceroute-ng, tracepath-ng, arping-ng, rsync, iperf3, wg, ss-ng, tcpdump, iftop and
  mount.cifs. The script runs only when the caller is root, and does nothing for other users.
  It writes `etc/resolv.conf` from the `DnsAddresses` of the active default network, read from
  `dumpsys connectivity`. Other networks and Private DNS servers are ignored, and IPv6 addresses keep
  their `%scope`. If that finds nothing, it falls back to `getprop net.dns1/net.dns2`.
- The result is cached for 30 s (set `ALT_DNS_TTL` to change it, or `ALT_DNS_FORCE=1` to bypass the cache).
- If no DNS server is found, the existing file is left unchanged and the tool reports the lookup error
  itself. No public resolver is ever written.
- Bionic and Android apps are not affected: bionic's `libc.so` contains no reference to
  `resolv.conf`. This was checked with `strings` on an Android `libc.so`, and `phone-test.sh`
  also checks it with `ping example.com`. The file only changes when a network tool runs as root,
  so other musl/glibc programs that read `/etc/resolv.conf` may see servers from an earlier network.

## Install

- In the Magisk, KernelSU or APatch manager app: Modules, then Install from storage, then pick the ZIP.
- Command line, as root:
  - KernelSU: `ksud module install /sdcard/Download/android-linux-tools-v3.24-r1.zip`
  - Magisk: `magisk --install-module /sdcard/Download/android-linux-tools-v3.24-r1.zip`
  - APatch: `apd module install /sdcard/Download/android-linux-tools-v3.24-r1.zip`
- Reboot. If the prototype `prototype-tools` is installed, the installer creates its `remove` file, and the
  manager deletes it on that reboot. No other module is touched.
- The ZIP contains the standard `META-INF/com/google/android/update-binary` for Magisk. KernelSU and
  APatch use their own installer and call the same `customize.sh`. That script uses only `ui_print`,
  `set_perm` and `set_perm_recursive`, and defines fallbacks for them if they are missing.

## Phone test

Run `sh /data/adb/modules/android-linux-tools/share/android-linux-tools/phone-test.sh` as root. The
same script is also in `dist/phone-test.sh`. It checks:

- every installed tool, with names taken from `alt-list -m`
- that renamed tools do not shadow the device binaries
- version banners
- functional tests: nft table add/list/delete, ipset create/add/list/destroy, `conntrack -C`,
  `wg show all`, `bridge link`, `tc-ng qdisc show dev lo`, getfacl, the DNS overlay,
  `curl -sI https://example.com`, `dig +short example.com`, round trips for zstd, xz, lz4, jq, sqlite3,
  bash and tmux

Kernel features are checked in `/proc/config.gz` first. If that file is missing, kernel errors such as
"Protocol not supported" count as SKIP. bpftool on the lite flavour is also a SKIP. The script cleans
up everything it creates and ends with `TOTAL pass=N fail=M`.

## Rebuilding

The build needs bash, python3, patchelf, readelf (binutils), file, zip, unzip and coreutils on any
x86_64 or aarch64 Linux host. No aarch64 code is run on the host.

```
./build.sh                 # build both flavours from alpine.lock.json
./build.sh --clean         # same, after deleting all caches (.work) and dist/
./build.sh --update-lock   # re-resolve from config/build.conf (ALPINE_BRANCH=latest-stable or vX.Y) and rewrite alpine.lock.json
```

- `config/build.conf` sets the Alpine branch (`latest-stable` or a pinned `vX.Y`), the mirror,
  `MODULE_RELEASE` (the N in `-rN`) and `SOURCE_DATE_EPOCH`.
- `config/tools.tsv` lists the tools: wrapper name, Alpine package, path inside the apk, libexec name,
  fixed arguments, and flags (`dns` = refresh resolv.conf, `full` = full flavour only).
- `alpine.lock.json` records the resolved branch and, for every package, its version, size, sha256,
  APKINDEX `C:` checksum, licence, origin and aports commit.
- Downloaded apks are treated as untrusted data. Each one is checked for size, the lockfile sha256, the
  APKINDEX `Q1` control checksum and the `.PKGINFO` `datahash` of its data segment. It is then
  extracted into its own directory with Python's `tarfile` `data` filter and never executed.
  The APKINDEX signature itself is not verified; it is fetched over HTTPS.
- Host checks, per flavour (`.work/json/host_checks-*.json`):
  - every libexec ELF is AArch64 with interpreter `/data/adb/modules/android-linux-tools/lib/ld-musl-aarch64.so.1`
    and the matching RUNPATH
  - the `DT_NEEDED` closure is fully present in `lib/`
  - `sh -n` and `bash --posix -n` pass for every script
  - every version pattern in `phone-test.sh` is checked against the binary's ELF strings, including
    printf formats filled in with the binary's own name and version
  - `unzip -t` and `zip -T` pass
  - the ZIP contains no host paths
- The build is reproducible: file modes and mtimes are fixed (`SOURCE_DATE_EPOCH`), entries are sorted,
  and the ZIP is written with `zip -r -y -X -D` in TZ=UTC. With the same lockfile, the same `patchelf`
  and the same `zip`, two builds give byte-identical ZIPs.
- Alpine removes superseded package versions from stable branches. When that happens, an old lockfile
  can no longer be downloaded, and `./build.sh --update-lock` is needed (then bump `MODULE_RELEASE`).

## Licences

Every bundled package keeps its own licence. The SPDX licence of each package is listed in
`share/licenses/NOTICE.txt` inside the module and in `dist/MANIFEST.json`. Licence files that the
packages ship themselves are copied to `share/licenses/alpine/`. Several packages are GPL or LGPL
(bash, iproute2, nftables, util-linux, strace, tcpdump, e2fsprogs and others). Their complete
corresponding source is the Alpine aports tree at the pinned branch,
<https://gitlab.alpinelinux.org/alpine/aports/-/tree/3.24-stable>, at the per-package `aports_commit`
recorded in `alpine.lock.json`. Each APKBUILD there names the upstream source tarball and Alpine's
patches. The build scripts in this repository are by Ivan Angelov.
