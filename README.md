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
