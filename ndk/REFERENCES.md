# NDK build references

Per tool: how other projects build it for Android/bionic (or for other cross targets), and what this
repository's recipe does and why.

How to read this file:
- "Sources checked" lists what the survey looked at (URL or repository path, commit hash or date as observed
  when it was surveyed on 2026-11-08) and what each source does. "absent" means the project has no package for
  the tool.
- "Chosen approach" is what `ndk/recipes/<name>.sh` actually does. Configure flags are given in addition to the
  common ones from `ndk/lib/env.sh` (`--host=aarch64-linux-android --build=x86_64-pc-linux-gnu --prefix=/usr
  --sysconfdir=/etc --localstatedir=/var --disable-shared --enable-static --disable-nls`). Patches are in
  `ndk/patches/<name>/`; their headers explain each change and where it came from.
- "Why" gives the reason. Where the survey recommended something else, the difference is noted.
- `[I]` = inferred by the survey, not verified. `[U]` = unverified.

Builder facts (`ndk/Dockerfile`, `ndk/lib/env.sh`):
- Android NDK r30 (LTS), Pkg.Revision 30.0.16248370, `android-ndk-r30-linux.zip` SHA-1
  `5107f898313790e449e87eee2183d9a20602dee9`, as published on developer.android.com/ndk/downloads and in
  dl.google.com/android/repository/repository2-3.xml (the Dockerfile also checks the size and a SHA-256 recorded
  at pin time).
- Debian trixie-slim base pinned by digest, packages from snapshot.debian.org `20261101T000000Z`.
  A second layer after the NDK adds `g++` and `xxd` from the same snapshot (LLVM native tablegen, bpftrace stdlib embedding).
- Target `aarch64-linux-android`, API 35, compiler `aarch64-linux-android35-clang`, `llvm-ar`/`ld.lld`.
- CFLAGS `-O2 -g0 -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2 -ffunction-sections -fdata-sections` plus
  `-ffile-prefix-map` for the build paths; LDFLAGS `-Wl,--gc-sections -Wl,--build-id=sha1`; `pkgconf --static`
  with `PKG_CONFIG_LIBDIR` limited to the build prefix.

## Cross-cutting decisions

- **Per-recipe sysroot:** each recipe builds against a private prefix that contains only its declared (transitive)
  dependencies (`ndk/build.sh` `mk_sysroot`). A first version used one shared prefix, and two clean builds then
  differed: mtr's configure auto-detected libcap when libcap happened to be built earlier. With the private sysroots
  two `./build-ndk.sh --clean` runs give byte-identical binaries and ZIP.

### API level 35
- API 35 is Android 15, the oldest Android version on the target phones (Android 15 to 17). A lower floor only hides newer bionic functions and
  forces fallbacks (API 29 needed a curl workaround for `memset_explicit`, API 34).
- From API 33 bionic has `backtrace()`; in a static link `backtrace_symbols()` needs `dladdr()`
  from libdl, so the htop recipe hides `execinfo.h` (crash-handler backtraces are not needed).
- Static binaries carry the NDK's newest Android note (37) because r30 ships `crtbegin_static.o`
  only for its newest level; they are compiled against API-35 headers.

### Static vs dynamic linkage
The default is fully static (`-static`, NDK `libc.a`; for libtool `-all-static`). A static binary cannot use
Android's DNS, though, because static bionic has no netd client (verified in the sources below):
- bionic `libc/bionic/NetdClient.cpp` contains `#ifdef LIBC_STATIC #error NetdClient.cpp should NOT be included in
  static libc builds.`. This file is the one that dlopen()s `libnetd_client.so` and installs
  `netdClientInitDnsOpenProxy`.
- bionic `libc/bionic/NetdClientDispatch.cpp`: the default dispatch is `fallBackDnsOpenProxy() { return -1; }`.
- bionic `libc/dns/net/getaddrinfo.c` `android_getaddrinfo_proxy()` calls
  `fdopen(__netdClientDispatch.dnsOpenProxy(), "r+")`. When that returns NULL the result is `EAI_SYSTEM`, and the
  caller falls back to the in-process resolver. That resolver ignores resolv.conf (`res_init.c`: `#ifndef
  ANDROID_CHANGES /* IGNORE resolv.conf in Android */`). It takes nameservers only from
  `_resolv_populate_res_for_net()` (res_cache.c), which only netd fills in. Lookups therefore fail, and only
  `/system/etc/hosts` works.
- `gethostbyaddr`/`getnameinfo` behave the same way (gethnamaddr.c, around lines 794/897, use `dnsOpenProxy`).
- The strings in NDK r30 `libc.a` confirm this: `android_getaddrinfo_proxy`, `__netdClientDispatch`,
  `/system/etc/hosts` are present, and there is no dnsproxyd path.
- netd `client/NetdClient.cpp` `dns_open_proxy()` connects to `/dev/socket/dnsproxyd`
  (AF_UNIX, SOCK_STREAM).
- Survey heads: platform/bionic 731631f3 (2025-03-26), platform/system/netd e11b8688 (2025-03-24).
- Independent confirmation: https://github.com/osm0sis/android-busybox-ndk patch `050-b-xconnect-dietlibc.patch`
  (2019), "static compilation issues with bionic's getaddrinfo() returning only null instead of opening the
  expected connection to /dev/socket/dnsproxyd". Also `050-c-dietlibc-dnscruft.patch` (last commit a02f8962,
  2021-05-06), "bionic libc's property_get and __sys_property_get fail for statically compiled binaries".

The rule applied:
- Any binary that calls the libc resolver is built `LINKAGE=dynamic`. Calls were checked with `llvm-nm` on the
  unstripped binaries, for `getaddrinfo`, `gethostbyname2`, `gethostbyaddr` and `getnameinfo`.
- A dynamic binary is a PIE that links only the system bionic `libc.so`/`libm.so`/`libdl.so` (API 35 stubs),
  plus `libz.so` for curl. Every third-party library is linked statically from the build prefix. There is no
  `$MODDIR/lib` and no RUNPATH.
- Dynamic (v2.2): nft, ipset, wg, wg-quick, awg, awg-quick, ip, tc, ss, bridge, mount.cifs, iperf3, tcpdump,
  curl, dig, host, mtr, socat, rsync, traceroute, arping, tracepath, ncat, iftop.
- Static: everything else (for example conntrack, nfct, drill, mtr-packet, strace, bpftool, bpftrace).
- Option (B) of the survey was rejected: a static binary with a `--wrap=getaddrinfo` shim speaking the dnsproxyd
  protocol would be new code with no upstream reference to cite.

### CONFIG_SITE generated from the NDK headers
- `ndk/build.sh` runs `ndk/lib/api-site.py` on `$SYSROOT/usr/include`. For every function declared with
  `__INTRODUCED_IN(N)` where N > API (35), it writes `ac_cv_func_X=no` and `ac_cv_have_decl_X=no`, and `env.sh` exports
  the result as `CONFIG_SITE`.
- This is needed because a static link sees the whole `libc.a`, so autoconf's link-only `AC_CHECK_FUNCS` "finds"
  functions that the API-35 headers hide. Example: `memset_explicit` (API 34) broke curl.
- Examples hidden at API 35: `qsort_r`/`sig2str` (36), `sched_setattr`/`free_sized` (37). The survey was done at
  the earlier API 29 floor, where `renameat2`/`statx`/`memfd_create` (30), `preadv2` (33) and
  `copy_file_range`/`close_range` (34) were hidden as well; per-tool notes below that say "at 29" or "post-29"
  come from that survey.

### DNS without resolv.conf
- Dynamic tools resolve with `getaddrinfo`, which goes through bionic `libc.so` to netd (dnsproxyd).
- drill talks to a DNS server directly and never calls the libc resolver. Its flag in `ndk/tools.tsv` is `dns`.
  When the user gives no `@server`, the generated wrapper (`ndk/scripts/stage.py`) adds `@<first server>`. The
  server comes from `$ALTDIR/share/android-linux-tools/dns-servers`, which reads the `DnsAddresses` of the
  "Active default network" from `dumpsys connectivity`, falls back to `getprop net.dns1/net.dns2`, and never prints
  a public resolver. Nothing reads or writes resolv.conf.
- BIND's dig and host (v2.1) read `/etc/resolv.conf` and otherwise fall back to `::1`/`127.0.0.1`. Their flag
  in `ndk/tools.tsv` is `dnsenv`: the wrapper exports `ALT_DNS_SERVERS` (all servers from `dns-servers`, space
  separated) unless already set, and `ndk/patches/bind/0002-dighost-android-dns-servers.patch` makes
  `setup_system()` use that list when neither `@server` / host's server argument nor a resolv.conf gave one.
  Server names given as `@dns.google` (or as host's server argument) are resolved with `getaddrinfo`, so both
  are dynamic (netd).
- The v1 resolv.conf overlay (`resolv-refresh`) was only needed by the Alpine (musl) tools. Since v2.1 no
  Alpine tool remains, and since v2.2-r2 the Alpine build code is gone from the repository; `ndk/scripts/check.py`
  fails if `resolv-refresh`, a `lib/` directory or musl/resolv.conf handling in `customize.sh` appears.

### CA store for curl
- Android's `/system/etc/security/cacerts` names files by `openssl x509 -subject_hash_old` (MD5) as `<hash>.<n>`.
  AOSP platform/system/ca-certificates was at 45c7f199 (2025-02-10) with 149 files.
- OpenSSL 3 `by_dir.c` looks up only the SHA-1 "new" hash (`X509_NAME_hash_ex`), so it never finds those names.
  BoringSSL tries both hashes, which is why AOSP curl can use `--with-ca-path`.
- mbedTLS `mbedtls_x509_crt_parse_path()` loads every regular file in the directory regardless of name. That
  ignoring the trailing `-text` dump in each file causes no error is [I] in the survey.
- So curl is built with mbedTLS. The wrapper passes `--cacert $ALTDIR/etc/ssl/cert.pem` (the bundled Mozilla
  bundle) and `--capath /system/etc/security/cacerts`. It uses `/apex/com.android.conscrypt/cacerts` only if the
  system directory is missing.
- The survey suggested preferring the apex directory first. The wrapper prefers the system directory.

### Runtime layout: /system/etc/android-linux-tools (v2.2)
Problem (Android 15, KernelSU with the NoMount metamodule): `/data/adb` is `0700 root`, so for
adb shell (uid 2000), Termux and apps every wrapper failed when it exec'd `$MODDIR/libexec/<tool>`:
`/system/bin/dig[11]: /data/adb/modules/android-linux-tools/libexec/dig: inaccessible or not found`. The wrapper
itself, a new file in the module's `system/bin`, ran fine as uid 2000: what the manager mounts from `system/`
is readable by every uid; what the wrapper read directly from `/data/adb` was not. v2.1's phone test ran
everything as root and missed it.

Chosen approach: everything a wrapper uses at run time is in the module's `system/etc/android-linux-tools/`,
which is `ALTDIR=/system/etc/android-linux-tools` on the device: `libexec/` (every ELF), `share/terminfo/`,
`etc/ssl/cert.pem`, `etc/alt-tools.map`, and `share/android-linux-tools/` (dns-servers, origins.txt,
MANIFEST.json, phone-test.sh). Wrappers set `ALTDIR`, not `MODDIR`. The compiled-in paths move as well: ncurses
`--with-default-terminfo-dir`/`--with-terminfo-dirs`, curl `--with-ca-bundle`, OpenSSL `--openssldir`. Only the
module metadata (`module.prop`, `customize.sh`, `META-INF`) and `share/licenses/` stay in the module root.
`customize.sh` sets everything root:root with `u:object_r:system_file:s0` (the label of stock `/system/bin`
programs), `0755` for directories, programs and scripts and `0644` for data.

| Source | What it says / does |
|---|---|
| Magisk developer guide, https://topjohnwu.github.io/Magisk/guides.html | "new files in the module's `system` will be added to the real `/system`"; `set_perm`/`set_perm_recursive` default context `u:object_r:system_file:s0` |
| KernelSU module guide, https://kernelsu.org/guide/module.html | the module's `system` directory is overlaid on `/system`; same `set_perm`/`set_perm_recursive` and default context |
| KernelSU metamodule guide, https://kernelsu.org/guide/metamodule.html | since KernelSU 3.0 a metamodule mounts `system/` (overlayfs or magic mount); must honour `skip_mount` |
| meta-overlayfs README, https://github.com/KernelSU-Modules-Repo/meta-overlayfs | mounts each enabled module's `system/` (and vendor, product, ...) as an overlayfs layer: new subdirectories merge into the lower `/system/etc` |
| NoMount, https://github.com/maxsteeel/nomount (read at bf1847f, 2026-10-22) | README: VFS path injection that can "inject entirely new files into existing system directories". `module/metamount.sh` adds one rule per file/symlink of `system/` (`find -L ... -type f -o -type l`); `kernel/src/nomount.c` `nm_init_prealloc_inode()` gives a virtual directory with no real counterpart `S_IFDIR \| 0755` root:root and a file the mode/uid/gid of the module file, and forwards xattrs (the SELinux label) to the module file |
| APatch module guide, https://apatch.dev/apm-guide.html | `system/` overlaid on `/system` with OverlayFS; same `set_perm` functions and default context |

Why `/system/etc/<id>`: `/system/etc` exists on every device and every manager/metamodule above can add a new
subdirectory under an existing directory (Magisk and magic mount: new files of `system/` are added; overlayfs:
merge; NoMount: per-file rules plus synthesized directories), so no new top-level `/system` directory is needed.
A subdirectory of `/system/bin` would also work but would sit next to the wrappers in a `PATH` directory and in
the rename loop of `customize.sh`. `/system/etc` is where Android keeps non-`PATH` system files, and the
`etc/`, `share/` and `libexec/` names inside keep the v2.1 relative layout. The only `/data/adb` path left is
`$MODDIR` in `phone-test.sh` (root checks of `module.prop` and old-layout leftovers, and the v1 resolv.conf check,
which runs only if a module still ships `resolv-refresh`).

Checks: `ndk/scripts/check.py` fails on `$MODDIR` or `/data/adb` in a wrapper, `/data/adb` in an NDK ELF, an ELF
outside `$ALTDIR/libexec`, or a v2.1 runtime path in the module root. `ndk/scripts/layout_test.py` (run by
`ndk/package.sh` on the ZIP) unzips it under a simulated `data/adb/modules/android-linux-tools` (0700), runs
its `customize.sh` with `set_perm` stubs, and checks the view of a non-root user: every `$ALTDIR` path in every
wrapper exists and is readable (programs: executable) by "other" through every directory, nothing refers to
`/data/adb`, and owner, label and mode of every file under `system/`. Run against the v2.1 ZIP it reports 274
errors. On the phone, `phone-test.sh` run as root repeats the non-root checks as uid 2000 (`su 2000 -c`,
`su shell -c`, `su -s /system/bin/sh 2000 -c`, or the module's `setpriv --reuid=2000`); `su`/`setpriv` keep
the root SELinux domain, so that run tests file permissions, not the `shell` domain policy (run the script from
`adb shell` for that).

### Source verification
- Every recipe pins `SHA256` and records in `CHECKSUM_SOURCE` how that value was verified: a detached signature
  with the signer's key fingerprint, or an upstream-published checksum.
- Where upstream publishes neither, the line says so and names the cross-check (ipset, mtr).
- The fingerprints are repeated per tool below.

## Netfilter

### libmnl 1.0.5
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/libmnl | New. Branch android17-release 9607f96e (2026-02-11), "Initial import of libmnl" 91824f4c (2026-01-29), METADATA libmnl-1.0.5. Android.bp cc_library_shared, no patches |
| Termux packages/libmnl | 1.0.5, no patches (84f916dd, 2025-09-10) |
| LineageOS android_external_libmnl | absent |
| Alpine main/libmnl | 1.0.5 `--enable-static`; musl patch touches examples only |
| buildroot package/libmnl | 1.0.5; patches add a CAN example only |
| OpenWrt package/libs/libmnl | 1.0.5; docs Makefile patch only |
| der-exp/android_external_libmnl | cf6610f8 (2026-09-24): Android.bp + config.h, no source changes |
| CHIZI-0618/AndroidIPsetBuild, akashaProxy/ipset-Android | plain `./configure --host=aarch64-linux-android --enable-static --disable-shared`, no patches |

Chosen approach: `configure_std` with no extra flags, then `make` and `install_lib` into the prefix (static `.a`
and `.pc`). No patches. CHECKSUM_SOURCE: netfilter.org `.sig`, Netfilter Core Team key
`37D964ACC04981C75500FB9BD55D978A8A1420E4` (signed 2022-04-05, key expired 2024-10).

Why: AOSP compiles the same 1.0.5 sources unmodified against bionic. All distro patches touch only examples or
docs. `--enable-static` is required because configure.ac uses `AC_DISABLE_STATIC`.

### libnftnl 1.3.2
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/libnftnl | absent |
| Termux packages/libnftnl | 1.3.2 (dd9a0a8a, 2026-09-01); no patches; `-Wl,-undefined-version` for the shared lib's version script |
| LineageOS | absent |
| Alpine (925c34ed), buildroot (261a30b2), OpenWrt (706052b2) | 1.3.2, no patches |
| der-exp/android_external_libnftnl | 5333a0c3 (2026-09-24); Soong static lib + android/config.h, no source patches |

Chosen approach: `configure_std` with no extra flags, then `install_lib`. No patches. CHECKSUM_SOURCE:
netfilter.org `.sig`, key `8C5F7146A1757A65E2422A94D70D1A666ACF2B21`.

Why: Nothing is missing from bionic at API 29, and der-exp builds it unmodified. Termux's `-undefined-version`
only affects the shared library, which is not built.

### nftables 1.1.7 (nft, with bundled mini-gmp)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/nftables | absent |
| Termux (HEAD e14ba437, 2026-11-08) | absent (only libnftnl and libmnl are packaged) |
| LineageOS android_external_nftables | absent |
| Alpine main/nftables (925c34ed) | 1.1.7-r1; `--with-json --with-cli=readline`, systemd patch only |
| buildroot package/nftables (261a30b2) | 1.1.7; `--with-mini-gmp` without gmp, `--without-cli`, `--without-json`; no patches |
| OpenWrt package/network/utils/nftables (706052b2) | 1.1.7; `--with-mini-gmp --without-cli --disable-man-doc`; no patches |
| der-exp/android_external_nftables | 1.1.7 + bionic patch, last commit c02ce4ce (2026-09-24). Soong build for DerpFest/lineage-23.2, NDK r29 at API 34. The only bionic port found |
| CHIZI-0618 / xireiki AndroidNFtablesBuild | nftables 1.0.6.1 with musl-cross, not bionic; not relevant |

mini-gmp:
- mini-gmp ships inside the nftables tarball (`src/mini-gmp.c`, `include/mini-gmp.h`) and is selected with
  `--with-mini-gmp`.
- buildroot (without gmp) and OpenWrt use it; Alpine uses system gmp.
- der-exp builds it as `libnftables_minigmp` without changes.
- No bionic issue.

Chosen approach:
- `configure_std --with-mini-gmp --without-cli --without-json --without-xtables --disable-man-doc
  --disable-python`, then `make LDFLAGS="$LT_LDFLAGS"`. `LINKAGE=dynamic`: nft resolves host and service names.
  libmnl and libnftnl are linked statically.
- Patch `0001-bionic-headers-funopen.patch`, written for this repo. It touches include/headers.h, src/exthdr.c,
  src/libnftables.c and src/proto.c:
  - Includes bionic `<netinet/ip.h>`/`<netinet/tcp.h>` first, uses the kernel `struct ipv6hdr`, and renames nft's
    `TCP_FLAG_*` enumerators to avoid the clash with `<linux/tcp.h>`.
  - Uses a private glibc-layout `ip6_rthdr0` with `ip6r0_addr[]`.
  - Uses `funopen()` instead of `fopencookie()` (bionic has no `fopencookie()`).
  - Adds `#ifndef` definitions of `IGMP_V1/V2_MEMBERSHIP_REPORT` and `IGMP_V2_LEAVE_GROUP`.
  - Every change is guarded by `__ANDROID__`.
- CHECKSUM_SOURCE: netfilter.org `.sig`, key `8C5F7146A1757A65E2422A94D70D1A666ACF2B21`.

Why:
- No packaged bionic build of nft exists. The configure flags follow buildroot/OpenWrt: no readline, no jansson,
  no libgmp.
- Compared with der-exp commit b1520ae2ddb3818957d59391d4f7132c309e506e ("bionic compatibility:
  ipv6hdr/ip_auth_hdr/TCP_FLAG_*, ip6_rthdr0, IGMP_V*, funopen instead of fopencookie",
  https://github.com/der-exp/android_external_nftables/commit/b1520ae2ddb3818957d59391d4f7132c309e506e), this
  repo's patch fixes the same set of problems in the same four files. It was written independently against the
  autotools build at API 29 and uses `__ANDROID__` guards. der-exp used `__BIONIC__` guards with Soong at API 34.
- `fopencookie()` has no declaration in the NDK r30 headers and no definition in `libc.a` (checked with grep
  and nm), as the survey recorded; the patch therefore uses `funopen()` unconditionally on `__ANDROID__`.
- `getprotobyname_r`/`getservbyport_r` are already handled upstream through `AC_CHECK_DECLS`.
- The survey recommended a static build. The recipe links dynamically because of the DNS rule.

### ipset 7.24
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS | absent |
| Termux root-packages/ipset | 7.24 (796d6d77, 2025-09-21); `--with-kmod=no`, `-Wl,--undefined-version`, no patches |
| Alpine main/ipset | 7.24; basename-include.patch (`<libgen.h>`), symlink.patch |
| buildroot package/ipset | 7.24; `--with-kmod=no`, no patches |
| OpenWrt package/network/utils/ipset | 7.24; libgen.h patch |
| CHIZI-0618/AndroidIPsetBuild | 48e056df (2025-07-31); GitHub Actions, NDK r27c, API 30, static, no patches |
| akashaProxy/ipset-Android | 492f07f4 (2025-10-14); NDK r26b, API 33, dynamic, ships libmnl.so |
| nikakvo/ipset_arm64 | found by search (pushed 2026-11-01); not evaluated |

Chosen approach: `configure_std --with-kmod=no`, then `make LDFLAGS="$LT_LDFLAGS"`. `LINKAGE=dynamic`: it resolves
host names with `gethostbyname2`. libmnl is static. No patches. CHECKSUM_SOURCE: no upstream signature for 7.24
(ipset.netfilter.org was unreachable at pin time), and upstream publishes only a sha512, so the sha512 was
cross-checked against Alpine aports 3.24-stable main/ipset/APKBUILD.

Why: 7.24 already includes `<libgen.h>`, so the Alpine/OpenWrt basename patch is obsolete. Set-type modules
(dlopen) are off by default, so every set type is compiled in. The version-script issue only applies to the
shared lib.

### libnfnetlink 1.0.2
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/libnfnetlink | a376eb32 (2021-06-02); Android.bp cc_library_shared, no Android source patches |
| Termux root-packages/libnfnetlink | 1.0.2 (7ee69d5c, 2025-09-21); fix-libnetfilter-queue.patch (include guard `_NFNETLINK_H` -> `_UAPI_NFNETLINK_H`) |
| LineageOS | stale (cm-13.0 / lineage-15.0 staging) |
| Alpine, buildroot, OpenWrt | 1.0.2, no patches |

Chosen approach: `configure_std`, `install_lib`. No patches. CHECKSUM_SOURCE: netfilter.org `.sig`, key
`37D964ACC04981C75500FB9BD55D978A8A1420E4` (signed 2022-04-05, key expired 2024-10).

Why: Termux's guard patch is only needed when one translation unit includes both the kernel
`<linux/netfilter/nfnetlink.h>` and libnfnetlink's private copy. That happens with libnetfilter_queue, not on the
conntrack path (checked by grep).

### libnetfilter_conntrack 1.1.1
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/libnetfilter_conntrack | 683fe2e7 (2024-11-21); old version (imported 2017); no bionic source patches |
| Termux | absent |
| LineageOS | stale (lineage-15.0, 771a11ba) |
| Alpine | 1.1.1 `--enable-static`, no patches |
| buildroot | 1.0.9 + upstream commit 21ee35dd (`<netinet/in.h>` before kernel ICMP headers, musl) |
| OpenWrt | 1.1.1, no patches |

Chosen approach: `configure_std`, `install_lib`. No patches. CHECKSUM_SOURCE: netfilter.org `.sig`, key
`8C5F7146A1757A65E2422A94D70D1A666ACF2B21`.

Why: buildroot's musl fix is already in 1.1.1, AOSP builds an older version unmodified, and nothing is missing at
API 29.

### libnetfilter_cttimeout 1.0.1 and libnetfilter_cthelper 1.0.1 (libraries for nfct)
Sources checked:
| Source | Observed |
|---|---|
| Other distributions | not surveyed separately: small autotools libraries of the same family as libnetfilter_conntrack (built here the same way) |
| netfilter.org | 1.0.1 is the latest release of both (directory listings, 2026-11-08) |

Chosen approach: `configure_std`, `make`, `install_lib` (static archives + `.pc`), the same as
libnetfilter_conntrack. No patches. CHECKSUM_SOURCE: netfilter.org `.sig`, key
`37D964ACC04981C75500FB9BD55D978A8A1420E4` (the older Netfilter Core Team key that signed both 1.0.1 releases;
gpg reports it expired, the signatures are good).

Why: nfct's `timeout` and `helper` subsystems are built only with these libraries; Alpine's nfct has both.

### conntrack-tools 1.4.9 (conntrack, nfct)
Sources checked:
| Source | Observed |
|---|---|
| AOSP, Termux, LineageOS | absent |
| Alpine main/conntrack-tools | 1.4.9; `-D_GNU_SOURCE` + libtirpc, cthelper/cttimeout on; no patches |
| buildroot | 1.4.8; no patches |
| OpenWrt packages net/conntrack-tools (7eef26d5, 2026-11-07) | 1.4.8; `--with-libtirpc`; no patches |
| GitHub search "conntrack android ndk" | nothing found (rate-limited) |

Chosen approach:
- `ac_cv_header_rpc_rpc_msg_h=yes LIBNETFILTER_QUEUE_CFLAGS=" " LIBNETFILTER_QUEUE_LIBS=" " configure_std
  --enable-cthelper --enable-cttimeout --disable-systemd`.
- `make -C extensions`, then `make -C src conntrack nfct LDFLAGS="$LT_LDFLAGS"`. conntrackd is not built.
- Static: neither tool does name resolution. libmnl, libnfnetlink, libnetfilter_conntrack, libnetfilter_cttimeout
  and libnetfilter_cthelper are linked in.
- No patches. CHECKSUM_SOURCE: netfilter.org `.sig`, key `8C5F7146A1757A65E2422A94D70D1A666ACF2B21`.

Why:
- configure.ac line 52 checks `rpc/rpc_msg.h` unconditionally and otherwise requires libtirpc. Bionic has no
  `<rpc/>`, and RPC is used only by conntrackd's cthelper RPC helper, which is not built.
- `--enable-cthelper` also requires libnetfilter_queue, which only conntrackd links; presetting both
  `LIBNETFILTER_QUEUE_*` variables skips that pkg-config probe instead of building an unused library.
- nfct (v2.1): `timeout` and `helper` subsystems as in Alpine. `nfct helper add` looks for conntrackd's
  userspace helper objects with `dlopen()`; they are not shipped (v1's Alpine nfct shipped none either), and in
  the static binary `dlopen()` is the NDK libdl.a stub, so that one command reports the helper as not found.
  `nfct timeout ...` and `nfct helper list/get/delete/flush` are pure netlink.

## WireGuard and iproute2

### wireguard-tools 1.0.20260223 (wg, wg-quick)
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS | absent |
| Termux packages/wireguard-tools | 1.0.20260223 (29174fae, 2026-09-27); `make -C src WITH_WGQUICK=no`, then compiles `src/wg-quick/android.c` with `-DWG_CONFIG_SEARCH_PATHS=...` and installs it as `wg-quick` (android.c.patch is for wg-quick only) |
| Alpine | 1.0.20260223; `make -C src`; wg-quick patch only |
| buildroot, OpenWrt | 1.0.20260223, `make -C src`, no patches |
| Upstream | ships src/wg-quick/android.c (the Android wg-quick: "a shell script written in C"); wireguard-android builds the same file as libwg-quick.so for its root/kernel backend |

Chosen approach: `make -C src wg PLATFORM=linux`; then `wg-quick` = `$CC $CFLAGS -std=gnu11 -o wg-quick
src/wg-quick/android.c $LDFLAGS -ldl` with upstream's default config search paths (`/data/misc/wireguard`,
`/data/data/com.wireguard.android/files`). `LINKAGE=dynamic`: wg resolves endpoint host names with
`getaddrinfo`, and wg-quick `dlopen()`s `libbinder_ndk.so`. No patches. CHECKSUM_SOURCE: cgit signed snapshot
`.asc` over the uncompressed tar, Jason A. Donenfeld key `AB9942E6D4A4CFC3412620A749FC7012A5DE03AE`. The same
sha256 appears in the signed announcement (lists.zx2c4.com 2026-February/009514).

Why: wg has its own netlink code and no external libs. genkey falls back to `syscall(__NR_getrandom)` on bionic.
wg-quick (v2.1, for parity with awg-quick) is the upstream Android variant, not linux.bash: it needs no bash,
runs `ip`, `iptables`/`ip6tables`, `ndc` and `wg` through `system()`/`popen()` (PATH, so the stock Android `ip`
and the module's `wg` wrapper), and sets the tunnel's DNS through the netd DnsResolver binder service. Checked
against AOSP main for Android 15-17 (2026-11-08):
- packages/modules/DnsResolver `binder/android/net/IDnsResolver.aidl`: `setResolverConfiguration` is method 2 and
  `createNetworkCache` method 7, which are the transaction codes android.c uses (`FIRST_CALL_TRANSACTION + 2/+7`);
  `ResolverParamsParcel` fields 1-12 are in the order android.c writes them (later fields keep their defaults).
- system/netd `server/NdcDispatcher.cpp`: `network create <id> vpn <secure>`, `network interface add`,
  `network users add`, `network route add`, `network destroy`, `interface setcfg`, `interface setmtu`,
  `interface ipv6 <if> enable` all exist; `resolver setnetdns` does not, but android.c uses it only when
  `libbinder_ndk.so` cannot be loaded (never on Android 10+). `server/Android.bp` still builds `ndc`.
- The wg-quick for `wg` and the awg-quick for `awg` differ only in names (see amneziawg-tools).

### amneziawg-tools 3.1.20260812 (awg, awg-quick)
Sources checked:
| Source | Observed |
|---|---|
| Upstream github.com/amnezia-vpn/amneziawg-tools tag v3.1.20260812 (commit ee0f0a9a) | fork of wireguard-tools: `src/` with `WG_GENL_NAME "amneziawg"`, `make -C src` builds `wg` installed as `awg`; Android wg-quick is `src/wg-quick/android.c` (C, not bash), renamed to `awg`/`amneziawg`/`org.amnezia.awg` |
| amnezia-vpn/amneziawg-openwrt amneziawg-tools/Makefile | v1.0.20240213; `make -C src PLATFORM=linux`, installs `src/wg` as `/usr/bin/awg`; no wg-quick |
| AOSP, LineageOS, Termux (packages/amneziawg-tools), OpenWrt openwrt/packages | absent |
| Alpine community/amneziawg-tools | not read (gitlab raw returned HTTP 403 to the survey) |

Chosen approach:
- `make -C src wg PLATFORM=linux`, installed as `awg`; `awg-quick` = `src/wg-quick/android.c` compiled like
  wg-quick above (default search paths `/data/misc/amneziawg`, `/data/data/org.amnezia.awg/files`).
- `LINKAGE=dynamic` (endpoint `getaddrinfo`; `dlopen("libbinder_ndk.so")`).
- `ndk/patches/amneziawg-tools/0001-awg-quick-prefer-kernel-module.patch`: upstream android.c runs userspace
  `amneziawg-go` whenever the config has any AmneziaWG parameter (Jc, Jmin, Jmax, S1-S4, H1-H4, I1-I5), and only
  plain configs use `ip link add <if> type amneziawg`. The patch tries the kernel link type first and falls back
  to amneziawg-go only when that fails and `/sys/module/amneziawg` is absent, which is what upstream's own
  `linux.bash` `add_if()` does. Without it a kernel with built-in AmneziaWG (a custom kernel) would never be
  used for obfuscated configs, and amneziawg-go is not shipped.
- CHECKSUM_SOURCE: no signed tarball or published checksum upstream; the GitHub tag archive for v3.1.20260812
  (tag ref resolved to commit `ee0f0a9aa34ff0a0da4b3433b9512781cfe02843` via the GitHub API) is pinned by sha256.

Why: the task's brief named `src/wg-quick/android.bash`; upstream ships no such file at this tag. The Android
variant is `android.c` (also in wireguard-tools), which needs neither bash nor ip-ng: it calls the stock `ip`,
`iptables`, `ndc` and the module's `awg`. Notes: it calls `awg` by name, so it needs the `awg` wrapper under that
name (not renamed to `awg-ng`); it re-executes itself through `su -p -c` when not root.

### iproute2 7.3.0 (ip, tc, ss, bridge)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/iproute2 | c6cfbd7d (2025-03-26), METADATA v4.14.1 (stale). Android.bp: `-DNO_SHARED_LIBS`, `-Dstrdupa(__S)=...`, `-fcommon`, generated static-syms.h |
| Termux packages/iproute2 | 7.3.0, commit e187f140fbaf3539de31549c1fed8211a2ac94d2 (2026-11-01). 6 patches; dynamic with libandroid-glob/libandroid-support |
| LineageOS | stale (cm-14.1 / lineage-15.0 staging) |
| Alpine | 7.3.0, no patches |
| buildroot | 7.3.0; `--libbpf_force`, `SHARED_LIBS=n` when static |
| OpenWrt | 7.3.0; 17 patches (optional deps, tiny variants) |
| fulvius31/ip-neigh-sdk30 | reimplements `ip neigh` only; not relevant |

Chosen approach:
- `./configure --prefix=/usr --libbpf_force off --color auto`, then remove `HAVE_ELF`, `HAVE_SELINUX`, `HAVE_CAP`,
  `HAVE_BERKELEY_DB` and `HAVE_TIRPC` from config.mk.
- `make SUBDIRS="lib ip tc misc bridge" SHARED_LIBS=n CCOPTS="$CFLAGS" LDFLAGS="$LDFLAGS"`.
- `LINKAGE=dynamic`: ip, ss and the others resolve names. libmnl is static.
- `SHARED_LIBS=n` makes upstream generate `static-syms.h`, so link types, qdiscs, filters and actions are linked in
  instead of being looked up with `dlopen(NULL)`/`dlsym`.
- Patch `0001-bionic-compat-from-termux.patch`, adapted from Termux `in_addr_t`, `IN6_IS_ADDR_UNSPECIFIED`, `rindex`
  and `strdupa` patches at e187f140 and rebased to 7.3.0:
  - `in_addr_t` typedef in include/uapi/linux/in6.h, because iproute2's uapi copy shadows bionic's.
  - An array-based `IN6_IS_ADDR_UNSPECIFIED` in lib/utils.c.
  - `index`/`rindex` -> `strchr`/`strrchr` in tc/m_ct.c and tc/f_flower.c.
  - A `strdupa` definition via `alloca` in bridge/vni.c, ip/iplink_bond.c, ip/iproute_lwtunnel.c,
    lib/bpf_legacy.c and lib/color.c.
  - Two parts written for this repo: a termios-based `getpass()` in ip/ipseg6.c (Termux gets it from its patched
    NDK sysroot, ndk-patches/30/unistd.h.patch, via libandroid-support), and a rename of `bpf()` in
    include/bpf_util.h to avoid a duplicate symbol with bionic's undeclared `libc.a` stub.
- CHECKSUM_SOURCE: kernel.org `.sign` over the uncompressed tar (Stephen Hemminger key
  `110B8614708F62B83DD19F23F028172EC6AEB2B3`) and `sha256sums.asc` (kernel.org checksum autosigner
  `B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1`).

Why:
- Termux's `sethostent.patch` (API < 28 only) and libandroid-glob (`glob` since API 28) are not needed at 29.
  Termux's `Makefile.patch` only moves paths into the Termux prefix.
- The survey judged `in_addr_t.patch` "likely obsolete, try without". The recipe keeps it, because the uapi
  `in6.h` shadowing is real (see the patch header).
- The survey proposed strdupa as an AOSP-style `-D` flag. The recipe uses the patch form instead.
- `SUBDIRS` is restricted so netem's host tools are not built with the cross compiler.

## Packet capture

### libpcap 1.10.7
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/libpcap | dd978ad5 (2025-01-13) "Upgrade libpcap to libpcap-1.10.5"; `sdk_version: "29"`; checked-in config.h; only Android addition is pcap-netfilter-linux-android.c (for netd) |
| Termux packages/libpcap (e14ba437) | 1.11.0; `--with-pcap=linux --without-libnl`; fix-path-etc-ethers.patch (prefix only) |
| LineageOS | stale (cm-12.0-caf, cm-14.0 staging) |
| Alpine (925c34ed), buildroot (261a30b2) | 1.11.0, no patches |
| OpenWrt (706052b2) | 1.10.7 (CMake); patches not bionic-related |
| GitHub alvisisme/android-tcpdump, eakteam/tcpdump-android | stale (2022, 2018), not used |

Chosen approach: `configure_std --with-pcap=linux --without-libnl --disable-dbus --disable-rdma --disable-bluetooth
--disable-usb --disable-netmap --without-dpdk --disable-remote`, then `install_lib`. bison and flex come from the
container. No patches. CHECKSUM_SOURCE: tcpdump.org `.sig`, The Tcpdump Group key
`1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D`. tcpdump.org publishes no sha256; the pinned value matches OpenWrt's.

Why: 1.10.7 is the "stable" release on tcpdump.org (2026-09-05, security fixes). 1.11.0 (2026-09-13) is labelled
"testing" there, even though Termux, Alpine and buildroot already ship it. AOSP builds unmodified upstream 1.10.x
at API 29. Termux's ethers path patch is prefix-only.

### tcpdump 4.99.7
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/tcpdump | f27d554c (2025-01-13) "Upgrade tcpdump to tcpdump-4.99.5"; BoringSSL for ESP; no Android source patches |
| Termux root-packages/tcpdump (e14ba437) | 4.99.7; `ac_cv_linux_vers=3.4` (obsolete in 4.99.7); configure.patch is prefix-only |
| LineageOS | stale |
| Alpine (CMake), buildroot, OpenWrt | 4.99.7; OpenWrt `--without-cap-ng --without-crypto`; no bionic patches |
| GitHub android-tcpdump repos | unmaintained, not used |

Chosen approach: `configure_std --without-crypto --without-cap-ng --without-smi --disable-local-libpcap`, then
`make`. `LINKAGE=dynamic` so that reverse lookups without `-n` (`gethostbyaddr`) reach netd. libpcap is static.
No patches. CHECKSUM_SOURCE: tcpdump.org `.sig`, key `1F166A5742ABB9E0249A8D30E089DEF1D9C15D0D`.

Why: libcrypto is only needed for ESP decryption, and Android has no libcap-ng. The survey found static
acceptable for capture (numeric output after a failed lookup [I]). The recipe follows the DNS rule instead so
that name output works. The survey also listed `--disable-smb`, which the recipe does not pass.

## TLS and HTTP

### mbedtls 3.6.7
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/mbedtls | cabda535 (2024-12-19), v3.5.2; no Android source patches |
| Termux packages/mbedtls (e14ba437) | 3.6.7; shared; enables `MBEDTLS_THREADING_C/PTHREAD`; CMake install-dir patch only |
| Alpine | 4.1.1 |
| buildroot, OpenWrt | 3.6.7; buildroot static via `-DUSE_STATIC_MBEDTLS_LIBRARY=ON`; OpenWrt patches not relevant to clang/aarch64 |
| LineageOS | absent |

Chosen approach:
- CMake/Ninja with the NDK `android.toolchain.cmake`: `-DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29
  -DCMAKE_BUILD_TYPE=Release -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF -DUSE_SHARED_MBEDTLS_LIBRARY=OFF
  -DUSE_STATIC_MBEDTLS_LIBRARY=ON -DMBEDTLS_FATAL_WARNINGS=OFF`.
- Installed into the prefix with the `.pc` prefix rewritten.
- Default `mbedtls_config.h`: `MBEDTLS_FS_IO` is on, which `--capath` needs. No patches.
- CHECKSUM_SOURCE: sha256 published in the GitHub release (`mbedtls-3.6.7-sha256sum.txt`).

Why:
- 3.6 is the LTS branch. With 4.x, crypto moves to TF-PSA-Crypto, and the survey did not verify that curl 8.23's
  `-lmbedtls -lmbedx509 -lmbedcrypto` link line still works with it.
- The survey suggested setting `MBEDTLS_THREADING_C/PTHREAD` as Termux and buildroot do. The recipe keeps the
  default config, since curl does not share an mbedTLS context across threads [I].

### cacert 2026-11-05 (Mozilla CA bundle)
Sources checked:
| Source | Observed |
|---|---|
| curl.se/ca/cacert.pem | "Certificate data from Mozilla as of: Thu Nov 5 04:12:01 2026 GMT"; `cacert.pem.sha256` published |
| Termux packages/ca-certificates (e14ba437) | 1:2026.11.05 from https://curl.se/ca/cacert-2026-11-05.pem, same sha256 |
| AOSP platform/system/ca-certificates (45c7f199, 2025-02-10) | Android's own store, 149 `subject_hash_old` files |
| AOSP external/conscrypt apex/ca-certificates | `cacerts_apex`; Conscrypt prefers /apex/com.android.conscrypt/cacerts |

Chosen approach: download the immutable dated copy https://curl.se/ca/cacert-2026-11-05.pem (sha256
`427c0642...97285`) and install it as `data/cacert.pem`. stage.py places it at `$ALTDIR/etc/ssl/cert.pem`
(module `system/etc/android-linux-tools/etc/ssl/cert.pem`).
CHECKSUM_SOURCE: https://curl.se/ca/cacert.pem.sha256 (the same file as cacert.pem on 2026-11-05).

Why: the Mozilla bundle does not depend on the device. The Android store reflects the device's trust settings,
but user-disabled CAs are not honoured by a plain capath read [I]. Shipping both gives a working default on every
Android version.

### curl 8.23.0
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/curl | e9292a2a (2025-03-26) curl 8.12.1; BoringSSL, `--with-ca-path=/system/etc/security/cacerts`, shared libs; local-configure.patch |
| Termux packages/libcurl (e14ba437) | 8.23.0; OpenSSL + nghttp2/3 + ngtcp2 + libssh2; `--disable-ares`; `ac_cv_func_getpwuid=yes` (Termux toolchain issue #15889); no source patches |
| LineageOS | stale (lineage-16.0, 2019) |
| Alpine | 8.23.0; OpenSSL, c-ares |
| buildroot | 8.23.0; `--with-mbedtls=` option; no patches |
| OpenWrt packages net/curl (7eef26d5) | 8.23.0; `--disable-ares --without-ca-path --with-ca-bundle=`; mbedTLS selectable |
| curl docs/INSTALL.md "# Android" (curl-8_23_0) | NDK `aarch64-linux-android29-clang`, `--host aarch64-linux-android --disable-shared` |
| GitHub static-curl projects | musl/Linux, not Android; not used |

Chosen approach:
- `configure_std --with-mbedtls=$DEPROOT --with-zlib --without-libpsl --without-libidn2 --without-nghttp2
  --without-brotli --without-zstd --without-libssh2 --without-librtmp --disable-ldap --disable-ldaps
  --enable-threaded-resolver --disable-ares --disable-manual --disable-docs
  --with-ca-bundle=/system/etc/android-linux-tools/etc/ssl/cert.pem --without-ca-path --without-ca-fallback`
  (v2.1: `/data/adb/modules/android-linux-tools/etc/ssl/cert.pem`, unreadable for non-root users).
- `make LDFLAGS="$LT_LDFLAGS"`.
- `LINKAGE=dynamic`: system `libc.so`/`libm.so`/`libdl.so` plus the system `libz.so`; mbedTLS static.
- No patches.
- CHECKSUM_SOURCE: `.asc`, Daniel Stenberg key `27EDEAF22F3ABCEB50DB9A125CC908FDB71E12C2`.

Why:
- Without c-ares, the threaded resolver calls the system `getaddrinfo()`, so DNS works only through netd, which
  rules out static.
- mbedTLS loads Android's hash-named CA files, which OpenSSL 3 cannot. The wrapper adds `--cacert` + `--capath`
  (see the CA store section).
- The survey proposed `--with-ca-path=/system/etc/security/cacerts --with-ca-embed=` and the `.tar.gz` (the only
  file with a curl.se-published sha256). The recipe uses a compiled-in bundle path plus wrapper arguments, and the
  `.tar.xz` verified by its `.asc`; Termux, buildroot and OpenWrt pin the same xz sha256.

## DNS

### ldns 1.9.2 (drill)
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS, buildroot | absent |
| Termux packages/ldns (e14ba437) | 1.9.2; `--with-ssl --disable-gost --with-drill`; fix-hardcoded-paths.patch (resolv.conf/hosts -> $PREFIX); depends on `resolv-conf`, a static `nameserver 8.8.8.8/8.8.4.4` file; no getprop logic |
| Alpine (925c34ed) | 1.9.2 `--with-drill --with-examples --disable-dane-verify` |
| OpenWrt packages libs/ldns (7eef26d5) | 1.9.2 `--with-drill --with-ssl` |
| Upstream github.com/NLnetLabs/ldns | 2867a37d (2026-10-06); no Android nameserver fallback |
| GitHub search "ldns drill android" | no results |

Chosen approach: `configure_std --without-ssl --with-drill --without-examples --without-pyldns --without-pyldnsx
--disable-dane --disable-gost --disable-ecdsa --disable-ed25519 --disable-ed448 --disable-sha2 --disable-dsa`, then
`make LDFLAGS="$LT_LDFLAGS"`. Static. The wrapper adds `@<server>` from `dns-servers` when the user gives none (see
"DNS without resolv.conf"). No patches. CHECKSUM_SOURCE: `.sha256` published by NLnet Labs.

Why:
- drill sends its own UDP/TCP queries and never calls the libc resolver, so the static-netd problem does not
  apply. `@<IP>` needs no resolv.conf.
- Termux's patch only changes prefix paths, and its static public-resolver file was not wanted.
- DNSSEC validation (`-S`, `-k`) needs SSL and is left out. The `-D` DO bit still works.
- The survey also listed `--without-p5-dns-ldns --disable-ldns-config`, which the recipe does not pass.
- The survey's option (b), a source patch reading getprop, was rejected. The server lookup lives in the wrapper.

### libuv 1.53.0 (library for BIND)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/libuv | present (listing of platform/external, 2026-11-08) |
| Termux packages/libuv | 1.53.0; `PLATFORM=android`, `-landroid-spawn`, autogen; patches: io_uring wrappers return ENOSYS on Android, no FICLONE/statx (seccomp) |
| buildroot, OpenWrt, Alpine | shared library builds [U] |

Chosen approach: CMake with the NDK toolchain file (as for mbedtls), `-DLIBUV_BUILD_SHARED=OFF
-DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF`; only `libuv.a` and the headers are kept, plus a written
`libuv.pc` (the static-only install has just `libuv-static.pc`; BIND asks for `libuv`). No patches.
CHECKSUM_SOURCE: `.sign`, Santiago Gimeno key `612F0EAD9401622379DF4402F28C3C8DA33C03BE`.

Why: 1.53.0's `src/unix/linux.c` already returns 0 from `uv__use_io_uring()` for `__ANDROID_API__` ("blocked by
seccomp") and uses statx only from API 30, so Termux's two patches are not needed at API 35. libandroid-spawn
is only needed below API 28 (`posix_spawn`).

### liburcu 0.15.7 (library for BIND)
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS | absent |
| Termux packages/liburcu | 0.15.7; default configure; disable-tests.patch only |
| OpenWrt, buildroot, Alpine | default configure [U] |

Chosen approach: `configure_std --disable-numa`; only `include/` and `src/` are built and installed. No patches.
CHECKSUM_SOURCE: `.asc`, Mathieu Desnoyers key `2A0B4ED915F2D3FA45F5B16217280A9781186ACF` (and the published
`.sha256`).

Why: `include/urcu/syscall-compat.h` already handles `__ANDROID__`. BIND's default flavour (`liburcu`, the
membarrier one) is used; Termux's `--with-liburcu=qsbr` needs `--enable-developer` and a qsbr shutdown patch.

### OpenSSL 3.5.9 (libcrypto/libssl for BIND)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/openssl | present (AOSP itself uses BoringSSL) |
| Termux packages/openssl | 3.6.5; `./Configure android-arm64 shared zlib-dynamic no-ssl no-hw no-srp no-tests enable-tls1_3`, `-DNO_SYSLOG` |
| Upstream | 3.5 is the current LTS branch (3.5.9 released 2026-09-29) |

Chosen approach: `ANDROID_NDK_ROOT=/opt/ndk ./Configure android-arm64 -D__ANDROID_API__=35 --prefix=/usr
--libdir=lib --openssldir=/system/etc/android-linux-tools/etc/ssl no-shared no-module no-engine no-dso
no-tests no-docs no-apps no-ui-console no-ssl3 no-comp $CFLAGS`, `make build_libs`, `make install_dev`.
`crypto/buildinf.h` is regenerated with `util/mkbuildinf.pl` and a fixed compiler description, because the
generated one embeds the whole compiler command line including the `-ffile-prefix-map` build paths
(reproducibility and the host-path check). No patches. CHECKSUM_SOURCE: `.asc`, OpenSSL key
`C46ED3F2CBEFDA1FDAADA44264ED7B1DCCE71CB2` (and the published `.sha256`).

Why: BIND 9.20 requires OpenSSL (>= 1.1.1) for its crypto (DNSSEC, TSIG, DoT); it cannot use mbedTLS, which curl
keeps. LTS 3.5 instead of 3.6. `--openssldir` makes OpenSSL's default CA file the module's Mozilla bundle
(`$ALTDIR/etc/ssl/cert.pem`) for `dig +tls` certificate checks.

### BIND 9.20.30 (dig, host)
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS | absent (platform/external has no bind; LineageOS android_external_bind 404) |
| Termux packages/dnsutils (master, 2026-11-08) | 9.20.30, dynamic shared BIND libs; `--disable-static --with-json-c --with-libxml2 --with-liburcu=qsbr --enable-developer`, attribute cache answers, `-DRESOLV_CONF=$PREFIX/etc/resolv.conf`, `-landroid-glob`, libtool soname fix; patches: delv RESOLV_CONF, socklen_t cast in lib/dns/resconf.c, qsbr shutdown deadlock |
| buildroot package/bind/bind.mk | 9.20.30 `--without-cmocka --without-lmdb --disable-doh --disable-static --with-openssl`; `depends on !BR2_STATIC_LIBS` |
| OpenWrt packages net/bind | 9.20.30 `--disable-geoip --with-openssl --without-lmdb --without-readline`, doh/jemalloc/gssapi toggles; deps libuv, liburcu |
| Nix pkgs/by-name/bi/bind | 9.20.30 `--without-lmdb --enable-dnstap --with-libidn2`; dont-keep-configure-flags.patch |
| Alpine main/bind | 9.20.30, shared (v1 bind-tools); APKBUILD not re-read (HTTP 403) |
| ISC GitLab bind9 tag v9.20.30 | configure.ac, bin/dig/dighost.c, lib/dns/resconf.c read |

Chosen approach:
- Deps: libuv, liburcu, openssl, libcap (static archives; configure requires libcap on `*-linux*`; the libcap
  recipe has no `.pc`, so `LIBCAP_CFLAGS=" " LIBCAP_LIBS=-lcap`).
- `configure_std --disable-doh --without-libnghttp2 --without-jemalloc --without-libxml2 --without-json-c
  --without-lmdb --without-gssapi --without-libidn2 --without-readline --without-zlib --disable-geoip
  --without-cmocka --disable-dnstap --disable-tracing --disable-fips-mode --disable-chroot`;
  `make -C lib`; `make -C bin/dig dig host`.
- `LINKAGE=dynamic`: PIEs against the system libc/libm/libdl only; libisc/libdns/libisccfg and all deps static.
- Patches: `0001-configure-allow-static-libraries.patch` removes configure's refusal of `--enable-static`
  outside `--enable-developer` (named loses dlopen() plugins; dig/host load none, and they stay PIE with RELRO);
  `0002-dighost-android-dns-servers.patch` (`ALT_DNS_SERVERS`, see "DNS without resolv.conf").
- CHECKSUM_SOURCE: `.asc`, ISC code-signing key (Michal Nowak) `D99CCEAF879747014F038D63182E23579462EFAA`.

Why:
- v2.0 left dig/host on Alpine because configure refuses static builds and a shared build would need
  `$MODDIR/lib` + RUNPATH. Static archives inside a dynamic PIE avoid both and keep the module's linkage rule.
- DoH is off (no nghttp2); `+tls` (DoT) works with OpenSSL. No IDN, no readline (nslookup is not shipped).
- Termux's socklen_t and qsbr patches are not needed: the build compiled without the cast at API 35, and the
  qsbr flavour is not used. Its RESOLV_CONF change is replaced by the ALT_DNS_SERVERS fallback, so no
  resolv.conf with public resolvers is shipped.
- Cost: dig and host are about 8 MB each (each carries libisc/libdns/libisccfg and libcrypto/libssl). v1 shipped a
  133 KB Alpine dig plus 3.2 MB of shared bind-libs and the shared libcrypto/libssl/libuv/liburcu.

## Diagnostics

### ncurses 6.6 (library for mtr)
Sources checked: no separate survey note. mtr.md records that Termux mtr depends on Termux's ncurses package, and
that the NDK has no ncurses.

Chosen approach:
- A host `tic` is built from the same source (gcc). It compiles a fixed list of terminfo entries into
  `data/terminfo`, which ships as `$ALTDIR/share/terminfo`. The list: xterm, xterm-256color, xterm-color, screen,
  screen-256color, tmux, tmux-256color, linux, vt100, vt220, dumb, ansi, rxvt, rxvt-unicode,
  rxvt-unicode-256color.
- Target library flags: `configure_std --without-shared --with-normal --without-debug --without-ada --without-cxx
  --without-cxx-binding --without-tests --without-progs --without-manpages --enable-widec --enable-pc-files
  --with-build-cc=gcc --with-default-terminfo-dir=/system/etc/android-linux-tools/share/terminfo
  --with-terminfo-dirs=/system/etc/android-linux-tools/share/terminfo:/system/etc/terminfo --disable-termcap --disable-db-install
  --without-gpm --disable-stripping`.
- Only include/ and ncurses/ are built and installed. Compatibility links are added: `libncurses.a`,
  `libtinfo(w).a`, `ncurses.pc`, and `include/ncurses(w)/`.
- No patches. CHECKSUM_SOURCE: GNU `.sig`, Thomas E. Dickey key `19882D92DDA4C400C22C0D56CC2AF4472167BE03`.

Why: the terminfo search path is the module's own compiled entries first, then `/system/etc/terminfo`, so no
terminal descriptions are compiled into the binary. The mtr survey's alternative was built-in fallbacks
(`--with-fallbacks=... --disable-database`) or `--without-ncurses`.

### mtr 0.96 (mtr, mtr-packet)
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS | absent |
| Termux root-packages/mtr | 0.96 from the GitHub tag archive (sha256 `73e6aef3...`), `--without-gtk`, dep ncurses, `./bootstrap.sh`. Patches: hsearch bundle + hsearch.patch, index_to_strchr.patch, packet.c.patch. Read at commit 5628ffe85dc4a70916543752fe81ad3c1066ea32 |
| Alpine (925c34ed) | 0.96 `--without-gtk` |
| buildroot (261a30b2), OpenWrt (7eef26d5) | 0.95; OpenWrt `--without-jansson ac_cv_lib_cap_cap_set_proc=no` |
| bitwizard.nl | 0.96 tarball re-rolled (the first upload is kept as `mtr-0.96.tar.gz_misses_utils.h`); no checksum or signature published |
| GitHub search "mtr android ndk" | no results |

Chosen approach:
- GitHub tag archive v0.96: write `.tarball-version`, run `./bootstrap.sh`, then `configure_std --without-gtk
  --without-jansson --with-ncurses` and `make`. Dependencies: ncurses and libcap (declared, so mtr-packet
  always drops its capabilities after opening the raw sockets).
- mtr is `LINKAGE=dynamic` (`getaddrinfo`/`getnameinfo`), with ncurses static.
- mtr-packet is relinked with `$LDFLAGS_BASE -static`, because it does no name resolution.
- Patch `0001-index-to-strchr-from-termux.patch`: Termux `index_to_strchr.patch` at 5628ffe8, unchanged (packet/command.c,
  ui/cmdpipe.c, ui/curses.c).
- CHECKSUM_SOURCE: GitHub tag archive, no upstream signature (the same sha256 as Termux pins).

Why:
- Bionic (LP64) has no `index()`, so that Termux patch is taken.
- Termux's hsearch patch is not needed (`hcreate`/`hsearch` since API 28).
- Termux's packet.c.patch (no setuid drop, for unprivileged apps) is not wanted in a root module.
- The survey suggested `-Dindex=strchr` instead of the patch, `ac_cv_lib_cap_cap_set_proc=no` (mtr's configure
  probes libcap unconditionally; `--without-libcap` is not an mtr option, so the recipe instead declares libcap as a
  dependency, which the per-recipe sysroot makes deterministic), and `--without-ipinfo`, because ASN lookups use `res_query` with no nameservers in a client
  process [I]. The recipe does not pass `--without-ipinfo`, so `-z`/`-y` are built but are expected not to work [I].

### socat 1.8.1.3
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS | absent |
| Termux packages/socat (e14ba437) | 1.8.1.3; `--disable-posixmq ac_cv_header_resolv_h=no sc_cv_getprotobynumber_r=`; patches 0001-no-o_append (no rationale, not adopted), 0002 32-bit format specifiers (`!__LP64__` only) |
| Alpine | 1.8.1.3; use-linux-headers.patch (musl) |
| buildroot | 1.8.1.3; termios shift cache vars; patch 0002 only for OpenSSL 4 |
| OpenWrt | 1.8.1.1 |
| GitHub search "socat android ndk" | no results |

Chosen approach: `ac_cv_header_resolv_h=no configure_std --disable-openssl --disable-readline --disable-libwrap
--disable-fips`, then `make socat`. `LINKAGE=dynamic` (`getaddrinfo`). No patches. CHECKSUM_SOURCE:
http://www.dest-unreach.org/socat/download.sha256sum, published by the author. The site is HTTP only, and Termux
and buildroot pin the same values.

Why:
- bionic's `struct __res_state` is opaque and there is no `_res`, so socat's resolver tweak options are dropped
  the same way Termux does it. Lookups still use `getaddrinfo`.
- The survey preferred `--disable-resolve` and also listed `--disable-posixmq` plus the cross-compile cache
  variables (`sc_cv_sys_*_shift`, `ac_cv_have_c99_snprintf`, `ac_cv_have_z_modifier`). The recipe passes none of
  these.
- TLS addresses are left out, since OpenSSL is not built.

### iperf3 3.22
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/iperf3 | 788fee21 (2024-11-27), version 3.9; `./configure --host=aarch64-linux-android` with `aarch64-linux-android28-clang`, checked-in iperf_config.h |
| Termux packages/iperf3 (e14ba437) | 3.22 from the GitHub tag archive (a different file); patches main_Makefile.in (src only) and the temp dir -> $PREFIX/tmp |
| Alpine, buildroot, OpenWrt | 3.22; buildroot `-D_GNU_SOURCE`; OpenWrt `--without-sctp` |
| davidBar-On/android-iperf3 | maintained (pushed 2026-09-30), ndk-build, NDK r28c, API 28+, vendored sources |
| KnightWhoSayNi/android-iperf | stopped at 3.10.1 (2022) |

Chosen approach: `configure_std --without-openssl --without-sctp`, then `make LDFLAGS="$LT_LDFLAGS"`.
`LINKAGE=dynamic` (`getaddrinfo` for client/server/bind addresses), with libiperf static. No patches.
CHECKSUM_SOURCE: `.sha256` published by ESnet for the downloads.es.net tarball.

Why:
- Upstream already handles Android: `iperf_pthread.c` emulates `pthread_cancel`, flowlabel is guarded, and the
  temp dir is `/data/local/tmp`, which suits root.
- Termux's patches only cover its prefix and examples.
- The survey suggested `CFLAGS=-D_GNU_SOURCE` and `make -C src iperf3`. The recipe uses a plain `make`.

### strace 7.3
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/strace | 3dacaecd (2025-02-03), frozen at 4.25 |
| Termux packages/strace | 7.3 `--with-libdw`, `-Dfputs_unlocked=fputs`, 8 patches. Read at commit bcea3c1434a95a0bbd2a55e8aa8413450b459163 |
| LineageOS | stale (lineage-16.0, 2018) |
| Alpine 7.2, buildroot 7.3, OpenWrt 6.18 | all `--enable-mpers=no` |
| GitHub search "strace android ndk static" | no results |

Chosen approach: `configure_std --enable-mpers=no --disable-gcc-Werror --without-libdw --without-libunwind
--without-libiberty`, then `make`. Static, since strace does no DNS. Patch
`0001-bundled-uapi-in-h-bionic-from-termux.patch`: Termux `bundled-linux-include-uapi-linux-in.h.patch` at
bcea3c14, unchanged. It makes the bundled `<linux/in.h>` use bionic's `<bits/in_addr.h>`; without it,
`<arpa/inet.h>` fails with "unknown type name in_addr_t". CHECKSUM_SOURCE: GitHub release `.asc`, Dmitry V. Levin
key `FB3DCD19FF874735E4F61CE64E9FE8522F160EC2`.

Why:
- The bundled uapi headers are kept (the default), so Termux's in.h patch is needed. The survey's first choice,
  `--enable-bundled=no`, is not used.
- `--disable-gcc-Werror` replaces Termux's warning-only patches (sigreturn.c, src-affinity.c).
- Termux's other patches are not needed:
  - `fputs_unlocked` exists since API 28.
  - strace.c (no setreuid) is for non-root apps.
  - The mpers/armv7 configure patches are moot with `--enable-mpers=no`.
  - src-defs.h and xlat-faccessat_flags.h were not needed for this root, non-mpers build (patch header).
- Stack tracing (`-k`) is left out, since there is no libdw or libunwind.

## Phase 2

Survey heads used in the tables below, as observed on 2026-11-08 unless dated otherwise: termux-packages
e14ba437, Alpine aports 925c34ed, buildroot 261a30b2 (2026-11-07), OpenWrt openwrt 706052b2 (2026-11-07), OpenWrt
packages 7eef26d5, TUR 07b737b8, Zackptg5/Cross-Compiled-Binaries-Android 9c14dc3a (2024-03-30, stale).

Linkage follows the cross-cutting rule:
- Dynamic (system `libc.so`/`libm.so`/`libdl.so` only, every third-party library static), because they call the
  libc resolver: rsync, ncat, iftop, traceroute, arping, tracepath.
- Fully static: everything else in this part.
- Several surveys planned these tools fully static and named the static-DNS problem as a hypothesis
  (ncat.md, iftop.md, traceroute.md, iputils.md). The cross-cutting section settles it.

Several post-API-29 functions that the surveys asked to force to `no` by hand (`lchmod`, `memfd_create`,
`copy_file_range`, `preadv2`, `statx`, ...) are already covered by the generated `CONFIG_SITE`. They are
mentioned below only where a recipe still passes them explicitly.

### ethtool 7.2 (ethtool-ng)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/ethtool | dace3f5d (2025-03-04), version 6.11. Android.bp builds one cc_binary from the bundled libmnl sources plus `netlink/*.c`, `-DETHTOOL_ENABLE_NETLINK`, `-Wno-*` only, `min_sdk_version: "30"` (tethering APEX). No source patches |
| Termux root-packages/ethtool | 7.2 from a git snapshot + `autoreconf -fi`, dep libmnl, no patches |
| Alpine, buildroot, OpenWrt | 7.2, no patches; buildroot takes its hash from `sha256sums.asc` |
| TUR, osm0sis | absent |

Chosen approach:
- `configure_std --enable-netlink --disable-pretty-dump`, then `make`. Static, linked against the phase-1 libmnl.
- No patches. CHECKSUM_SOURCE: kernel.org `sha256sums.asc`, checksum autosigner key
  `B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1`.
- ethtool is new in v2. It is always installed as the wrapper `ethtool-ng`.

Why:
- AOSP builds the upstream sources unmodified against bionic, and no distro patches them. A grep of 7.2 for
  bionic-missing calls found nothing.
- Netlink (libmnl) is kept for the newer features. The survey's zero-dependency alternative, `--disable-netlink`
  (ioctl only), was not taken. That ethtool falls back to ioctl on kernels without the netlink ethtool family
  (< 5.6) is [I] in the survey.
- `--disable-pretty-dump` is not from the survey. It leaves out the per-driver register-dump decoders.

### attr 2.6.0 (library) and acl 2.4.0 (getfacl, setfacl)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/acl, platform/external/attr | absent (HTTP 404). Toybox (external/toybox 59a869a8, 2025-03-26) has getfattr/setfattr only |
| Termux packages/libacl 2.4.0, packages/attr 2.6.0 | no patches; attr `--enable-gettext=no` |
| Alpine main/acl, main/attr | 2.3.2 and 2.5.2; attr-basename.patch (musl basename) |
| buildroot | acl 2.4.0, attr 2.6.0; one old-GCC patch each, irrelevant for clang |
| OpenWrt packages utils/acl, utils/attr | 2.4.0 and 2.6.0, no patches |

Chosen approach:
- attr: `configure_std`, then `make libattr.la`. Only the library, its `.pc` and its headers are installed into
  the prefix. getfattr/setfattr are not built.
- acl: `configure_std`, then `make getfacl setfacl LDFLAGS="$LT_LDFLAGS"` (`-all-static`).
- Patch `acl/0001-walk_tree-IFTODT-fallback.patch` is written for this module. bionic's `<dirent.h>` has the
  `DT_*` constants but not `IFTODT()`, so `getfacl`/`setfacl -R` failed to compile. The fallback uses the same
  definition as glibc and musl (`(mode & S_IFMT) >> 12`).
- CHECKSUM_SOURCE for both: savannah `.sig`, key `259B3792B3D6D319212CC4DCD5BF9FEB0313653A`. buildroot and
  OpenWrt pin the same sha256 values.

Why:
- No distro carries a bionic patch, and the survey expected none. That `basename(argv[0])` needs no musl-style
  patch was a hypothesis, and it held at compile time. The missing `IFTODT()` showed up only during the build.
- configure probes `getxattrat` and the related `*xattrat` functions, which bionic lacks, so the libmisc compat
  code is built. That is fine.
- acl 2.4.0 enables `USE_OPENAT2` because the NDK uapi declares `__NR_openat2`. Per the survey (tools/setfacl.c),
  `setfacl -P` with a directory component fails with ENOSYS on kernels < 5.6, and the other build path fails the
  same way.

### libcap 2.78 (capsh, getpcaps)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/libcap | a72f6f4e (2025-02-19), METADATA libcap-2.69. Android.bp: libcap, getcap, setcap and a host `_makenames` generator, `min_sdk_version: "29"`. No capsh/getpcaps |
| Termux packages/libcap | 2.78; `PTHREADS=no PAM_CAP=no RAISE_SETFCAP=no OBJCOPY=llvm-objcopy`; patches drop tests, build `_makenames` with host gcc, and point capsh's SHELL at the Termux prefix |
| Alpine main/libcap | 2.78; fortify.patch (musl) |
| buildroot | 2.78, no patches, hash from `sha256sums.asc` |
| OpenWrt package/libs/libcap | 2.69, 3 patches |

Chosen approach:
- Plain make, no configure. Variables: `CC BUILD_CC=gcc AR RANLIB OBJCOPY SHARED=no LIBCSTATIC=yes PTHREADS=no
  GOLANG=no PAM_CAP=no USE_GPERF=no COPTS="$CFLAGS -DSHELL=\"/system/bin/sh\""`.
- `make -C libcap libcap.a`, then `make -C progs capsh getpcaps`. `libcap.a` and `sys/capability.h` are copied
  into the prefix, where util-linux does not use them but bpftool does.
- No patches. CHECKSUM_SOURCE: kernel.org `sha256sums.asc`, autosigner key
  `B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1`.

Why:
- Termux's patches are workarounds for its prefix and host compiler. `BUILD_CC=gcc` builds `_makenames` on the
  host, and `-DSHELL` replaces the capsh patch (`/bin/bash` would not exist).
- `PTHREADS=no` avoids libpsx and its `-Wl,-wrap,pthread_create`, as Termux and AOSP do. `GOLANG`, `PAM_CAP` and
  `USE_GPERF` are forced off so auto-detection on the build host cannot change the build.
- `SHARED=no LIBCSTATIC=yes` makes progs/Makefile link `--static`. Without `LIBCSTATIC`, libc stays dynamic.

### libcap-ng 0.9.6 and util-linux 2.42.4 (setpriv, lsblk, blkid, findmnt, lscpu)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/util-linux | absent (HTTP 404). platform/external/libcap-ng 8dd5e09d (2024-07-31), 0.8.5 |
| Termux packages/util-linux | 2.42.4, 16 patches. Bionic-relevant: versionsort.patch (strverscmp/versionsort in libmount tab_parse.c), sys-utils-irq-common.patch, schedutils-sched_attr.h.patch, lib-sysfs.c.patch (`/dev/block/` names), SysV IPC stubs, nsenter; cache vars include `ac_cv_type_struct_fanotify_event_info_header=no`; links libandroid-glob/libandroid-posix-semaphore. versionsort.patch at commit 433f5e9e9d6de387f7e37ba41ce9e81356861531 |
| Termux packages/libcap-ng | 0.9.6, `--without-python --without-python3` |
| people.redhat.com (libcap-ng) | lists only up to 0.8.5; 0.9.6 is on github.com/stevegrubb/libcap-ng |
| Alpine main/util-linux | 2.42.4, musl patches |
| buildroot | 2.41.5, 3 patches (mount API, uuid.pc, loopdev) |
| OpenWrt package/utils/util-linux | 2.42.2, no patches |

Chosen approach:
- libcap-ng: GitHub tag archive v0.9.6, `./autogen.sh`, `configure_std --without-python --without-python3
  --disable-cap-audit`, then `make -C src libcap-ng.la` and install. CHECKSUM_SOURCE: GitHub tag archive. Upstream
  publishes no checksum or signature for 0.9.x.
- util-linux: `ac_cv_type_struct_fanotify_event_info_header=no configure_std --without-python --without-systemd
  --without-udev --without-ncursesw --without-ncurses --without-tinfo --without-readline --without-libmagic
  --without-selinux --without-audit --without-cryptsetup --without-btrfs --without-econf
  --disable-makeinstall-chown --disable-makeinstall-setuid --disable-liblastlog2 --disable-pam-lastlog2
  --with-cap-ng`, then `make setpriv lsblk blkid findmnt lscpu LDFLAGS="$LT_LDFLAGS"`.
- blkid is installed as the wrapper `blkid-ng`.
- Patch `util-linux/0001-libmount-versionsort-from-termux.patch`: Termux `versionsort.patch` at 433f5e9e (the
  strverscmp comes from musl, MIT). It is rebased to 2.42.4, and strverscmp is made static so it cannot clash with
  a libc definition.
- CHECKSUM_SOURCE: kernel.org `sha256sums.asc`, autosigner key `B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1`.

Why:
- The survey recommended `--disable-all-programs` plus explicit `--enable-*`. findmnt has no `--enable` switch and
  would stay disabled, so all programs stay enabled in configure. Only the five make targets, and the libraries
  they need, are built.
- bionic has no `<sys/fanotify.h>` (no `fanotify_init`/`fanotify_mark` wrappers), so libmount's fanotify monitor is
  disabled through the cache variable, as Termux does it.
- bionic lacks `strverscmp()` and `versionsort()`, which libmount uses with `scandirat()` for fstab.d-style
  directories. Termux's shim is taken.
- The survey's list of post-29 functions to force to `no` (`close_range`, `copy_file_range`, `pidfd_*`,
  `qsort_r`, `renameat2`, `sched_setattr`, `statx`) is covered by `CONFIG_SITE`.
- Most other Termux patches touch programs not built here (ipcs/ipcmk/ipcrm, nsenter, irq tools, lsfd) or its
  prefix. The optional lib-sysfs.c.patch is not applied, so lsblk may print `/dev/<name>` instead of the
  `/dev/block/` path [I, survey].
- setpriv needs libcap-ng, so libcap-ng 0.9.6 is built for it.
- setpriv (v2.2): bionic `getpwuid()` returns NULL `pw_passwd`/`pw_gecos` for Android IDs; upstream `passwd_copy()`
  `xstrdup()`s every field and aborts (xalloc.h assertion) on any `--reuid`/`--regid`. Patch 0002 copies NULL
  fields as NULL. Found on an Android 15 vendor ROM.

### htop 3.5.3
Sources checked:
| Source | Observed |
|---|---|
| AOSP | no external/htop (404); external/ncurses 34cc2444 (2022-11-04), 6.3 |
| Termux packages/htop | 3.5.3 from the GitHub archive + `./autogen.sh`, `ac_cv_lib_ncursesw6_addnwstr=yes LIBS=-landroid-support`; patches access-procstat-file/proc-stat (fallback for an unreadable `/proc/stat`, app sandbox only) |
| Alpine main/htop, OpenWrt packages admin/htop | 3.5.3, no patches |
| buildroot | 3.5.1, hash from upstream `.sha256`, no patches |
| Zackptg5 | htop 3.2.2 `--enable-static --enable-unicode`, removes `-rdynamic` from Makefile.am, `ffsl` -> `__builtin_ffsl` |

Chosen approach: `LIBS=-lm configure_std --enable-unicode --disable-sensors --disable-delayacct
--disable-capabilities --disable-hwloc --disable-unwind --enable-affinity`, then `make`. Static, with the phase-1
ncursesw. No patches. CHECKSUM_SOURCE: `htop-3.5.3.tar.xz.sha256` published in the GitHub release.

Why:
- `LIBS=-lm`: `pow`/`log10` live in `libm.a`. configure's `ceil()` probe is satisfied by a compiler builtin, so
  configure never adds `-lm` by itself.
- libsensors, libsystemd and libnl are dlopen()ed at runtime, which a static binary cannot do, so those features
  are disabled.
- Termux's `/proc/stat` patches only matter in the app sandbox. This module runs as root.
- The survey suggested `ac_cv_func_memfd_create=no`, which is covered by `CONFIG_SITE` (API 30).
- `-rdynamic` (Makefile.am) is left in. The survey judged it harmless with `-static` [I].
- The survey's ncurses with built-in fallbacks was not used. See the phase-1 ncurses section.

### libevent 2.1.13 and tmux 3.8
Sources checked:
| Source | Observed |
|---|---|
| AOSP | no external/tmux; external/libevent 5b388e72 (2025-03-17), 2.1.12-stable |
| Termux packages/tmux | 3.8, `--with-TERM=screen-256color --enable-sixel --enable-utf8proc`, libandroid-glob; patches: configure.ac (drop the strtonum/reallocarray/recallocarray run tests, so compat is always used), compat-setproctitle.c (include stdlib.h), tmux.h (socket prefix) |
| Termux packages/libevent | 2.1.13 via CMake, OpenSSL/tests/samples off; patches: evdns (net.dns1/2 properties, unused by tmux), evutil_rand, evutil (`__USE_GNU` for pipe2), CMakeLists |
| Alpine main/tmux, main/libevent | 3.8 and 2.1.13, no patches |
| buildroot | tmux 3.6b, libevent 2.1.13 (+LibreSSL patch) |
| OpenWrt packages utils/tmux | 3.8 |

Chosen approach:
- libevent: `configure_std --disable-openssl --disable-mbedtls --disable-samples --disable-libevent-regress
  --disable-debug-mode`, then `install_lib`. CHECKSUM_SOURCE: release `.asc`, key
  `7A02B3521DC75C542BA015456AFEE6D49E92B601`.
- tmux: `CPPFLAGS += -D_PATH_TMP=\"/data/local/tmp/\" -Dreallocarray=tmux_reallocarray`, then `configure_std
  --disable-utf8proc --enable-static` and `make`. Static, with ncursesw and libevent. No patches.
- The wrapper sets `TMUX_TMPDIR=/data/local/tmp` and `SHELL=/system/bin/sh` when they are unset
  (`ndk/scripts/stage.py`).
- tmux CHECKSUM_SOURCE: upstream publishes no checksum or signature. The sha256 equals the GitHub release asset
  digest.

Why:
- bionic's `<paths.h>` has no `_PATH_TMP`, so tmux's compat.h would fall back to `/tmp/`, which does not exist on
  Android. compat.h uses `#ifndef`, so a CPPFLAGS define is enough and no patch is needed.
- The "working reallocarray" probe is a run test, so a cross build always adds `compat/reallocarray.c`. That copy
  clashed with bionic's `reallocarray` in `libc.a` during the static link, so it gets its own name. The survey
  expected no conflict here.
- The always-compat outcome matches what Termux's configure.ac patch forces, so that patch is not needed.
- `--disable-utf8proc` avoids a dependency, since Linux uses `wcwidth`. The survey's `--with-TERM=screen-256color`
  is not passed.
- libevent uses the autotools tarball rather than Termux's CMake build. epoll, eventfd, pipe2 and arc4random are
  all in bionic.

### nano 9.3
Sources checked:
| Source | Observed |
|---|---|
| AOSP | absent (404) |
| Termux packages/nano | 9.3; `ac_cv_header_glob_h=no ac_cv_header_pwd_h=no gl_cv_func_strcasecmp_works=yes --enable-utf8 --with-wordbounds`, deps libandroid-support, ncurses, libmagic; src-files.c.patch (`/bin/sh` and `/tmp/` -> Termux prefix) |
| Alpine main/nano, OpenWrt packages utils/nano | 9.3, no patches |
| buildroot | 9.2 + a uclibc-only getrandom patch |
| Zackptg5 | nano 7.2 via NDK |

Chosen approach: `configure_std --enable-utf8 --disable-libmagic --disable-speller --with-wordbounds`, then
`make`. Static, with ncursesw. No patches. CHECKSUM_SOURCE: `.asc`, Benno Schulenberg key
`168E6F4297BFD7A79AFD4496514BBE2EB8E1961F`.

Why:
- Termux's `glob_h`/`pwd_h=no` are for its API-24 baseline (glob is API 28, getpwent API 26), so they are not
  needed at 29.
- The optional path patch was not taken. nano uses `$TMPDIR` before `P_tmpdir` (`"/tmp/"` in NDK stdio.h), and
  every wrapper exports `TMPDIR=/data/local/tmp` when it is unset.
- When `$SHELL` is unset, nano's fallback shell is still `/bin/sh` [survey, from the Termux patch].

### less 710
Sources checked:
| Source | Observed |
|---|---|
| AOSP | absent (404); toybox has no less |
| Termux packages/less | 710, deps ncurses and pcre2, `--with-regex=pcre2 --with-editor=editor`, `autoreconf -fi`, no patches |
| Alpine, buildroot, OpenWrt packages utils/less | 710, no patches |

Chosen approach: `LIBS=-lncursesw configure_std --with-regex=posix`, then `make`. Static. No patches.
CHECKSUM_SOURCE: GNU `.sig`, Mark Nudelman key `AE27252BD6846E7D6EAE1DD6F153A7C833235259`. buildroot and OpenWrt
pin the same sha256.

Why:
- No distro patches less.
- POSIX regex uses bionic's `regcomp`/`regexec`, so there is no pcre2 dependency.
- `LIBS=-lncursesw` provides `tgetent`, as the survey recommended. Terminal descriptions come from the module's
  terminfo (`TERMINFO` is set by the wrapper).
- The survey's runtime notes are not handled in the build: a read-only `$HOME` can be avoided with
  `LESSHISTFILE=-`, and the editor comes from `$EDITOR`.

### oniguruma 6.9.10 and jq 1.8.2
Sources checked:
| Source | Observed |
|---|---|
| AOSP | no external/jq or external/oniguruma (404) |
| Termux packages/jq, packages/oniguruma | 1.8.2 and 6.9.10, `--with-oniguruma`, no patches |
| Alpine, buildroot, OpenWrt packages | jq 1.8.2 and oniguruma 6.9.10, no patches; buildroot onig hash from the upstream `.sha256` |
| Zackptg5 | jq-1.7 via NDK |

Chosen approach:
- oniguruma: `configure_std`, then `install_lib`. CHECKSUM_SOURCE: `onig-6.9.10.tar.gz.sha256` published in the
  GitHub release.
- jq: `configure_std --with-oniguruma=$DEPROOT --disable-docs --disable-maintainer-mode --disable-valgrind`.
  `src/config_opts.inc` is then regenerated from `./config.status --config`, with the builder paths rewritten
  (prefix -> `/usr`, sysroot -> `/ndk-sysroot`). Finally `make LDFLAGS="$LT_LDFLAGS"` (`-all-static`).
- No patches. CHECKSUM_SOURCE: `sha256sum.txt` in the GitHub release jq-1.8.2.

Why:
- `--with-oniguruma=builtin` expects `modules/oniguruma`, which is not in the jq-1.8.2 tarball (verified), so
  oniguruma is built separately. This is the survey's option B.
- `jq --build-configuration` embeds the configure command line, which would otherwise carry builder paths.
- No distro patches either package. The functions jq probes (`strptime`, `timegm`, `gmtime_r`, `__thread`, ...)
  are all in bionic. `strptime/1` edge cases may differ from glibc [survey].

### sqlite 3.54.1 (sqlite3)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/sqlite | 38878b88 (2025-03-26, "Enable SQLITE_ENABLE_DBSTAT_VTAB"), METADATA 3.42.0; source of Android's own sqlite3 CLI |
| Termux packages/libsqlite | FTS3/4/5, readline, rtree, session, many `-DSQLITE_ENABLE_*`; src-os_unix.c.patch removes the `__ANDROID__` 2 GiB ftruncate guard and moves temp dirs to the prefix |
| Alpine, buildroot, OpenWrt packages libs/sqlite3 | 3.54.1, no patches |

Chosen approach:
- The amalgamation and CLI shell are compiled directly, with no configure: `$CC $CPPFLAGS $CFLAGS
  -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_RTREE
  -DSQLITE_ENABLE_DBSTAT_VTAB -DSQLITE_ENABLE_MATH_FUNCTIONS -DHAVE_USLEEP shell.c sqlite3.c $LDFLAGS -lm`.
- Static, with no readline. No patches.
- CHECKSUM_SOURCE: the SHA3-256 `b6ced585...` published on sqlite.org/download.html, verified at pin time. The
  pinned sha256 equals buildroot's and OpenWrt's.

Why:
- This is the survey's "simplest" option. It avoids the autosetup build and the differences between its option
  spellings and the legacy autoconf ones.
- Extension loading needs dlopen, which a static binary cannot do. The NDK has no readline, so shell.c uses its
  minimal line input.
- DBSTAT is enabled as in AOSP. The survey also suggested `--enable-session`, which is not enabled.
- Termux's ftruncate patch is not applied. The `__ANDROID__` guard in `robust_ftruncate()` stays, and per the
  survey it ignores truncation beyond 2 GiB (it matters for VACUUM/truncate of databases > 2 GiB).
- Temp files use `$TMPDIR`, which the wrapper sets to `/data/local/tmp`.

### zstd 1.5.7
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/zstd | 415469b3 (2025-03-05), v1.5.7; Android.bp builds libzstd only (`-DZSTD_HAVE_WEAK_SYMBOLS=0 -DZSTD_TRACE=0`), no CLI |
| Termux packages/zstd | 1.5.7 via build/cmake with programs, LZMA and zlib on, LZ4 off; patch only removes contrib gen_html |
| Alpine, buildroot, OpenWrt packages | 1.5.7, no patches; buildroot hash from upstream `.sha256` |
| Zackptg5 | v1.5.5 |

Chosen approach: `make -C programs zstd CC AR MOREFLAGS="$CFLAGS" LDFLAGS HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0
HAVE_THREAD=1 ZSTD_LEGACY_SUPPORT=0 BACKTRACE=0`. Static. The wrappers `unzstd` (`-d`) and `zstdcat` (`-dcf`)
call the same binary. No patches. CHECKSUM_SOURCE: `.sha256` and `.sig`, key
`4EF4AC63455FC9F4545D9B7DEF8FE99528B52FFD`.

Why:
- Upstream already handles bionic. `zstd_deps.h` and `cover.c` skip `qsort_r` under `__ANDROID__`, so
  `-D_GNU_SOURCE` is not added (it would select the API-36 `qsort_r`).
- `BACKTRACE=0`: `backtrace()` is API 33.
- The survey suggested `HAVE_ZLIB=1` (NDK `libz.a`). The recipe builds without gzip, lzma or lz4 formats, which
  the separate xz and lz4 tools cover.

### xz 5.8.4 (xz, unxz, xzcat)
Sources checked:
| Source | Observed |
|---|---|
| AOSP | no external/xz (404); external/xz-embedded d2c16535 (2024-05-30, decoder only) and external/lzma 2311e53f (2024-12-04, LZMA SDK 24.09) are not XZ Utils |
| Termux packages/liblzma | 5.8.4, `--enable-sandbox=no`; configure.patch only changes libtool's Android shared-library versioning |
| Alpine, buildroot, OpenWrt packages utils/xz | 5.8.4, no patches |

Chosen approach: `configure_std --enable-sandbox=no --disable-doc --disable-scripts --disable-lzmainfo
--disable-lzmadec --disable-xzdec --disable-lzma-links`, then `make LDFLAGS="$LT_LDFLAGS"`. Only `src/xz/xz` is
installed, and `unxz` (`-d`) and `xzcat` (`-dc`) are wrappers. `make -C src/liblzma install` also puts
`liblzma.a` and its headers into the build prefix for bcc/bpftrace (the xz program is unchanged). No patches. CHECKSUM_SOURCE: `.sig`, Lasse Collin
key `3690C240CE51B4670D30AD1C38EE757D69184620`.

Why:
- No patches are needed.
- The sandbox is disabled as in Termux, for a deterministic build. Landlock needs Linux 5.13+, so on most Android
  kernels the sandbox would be a no-op anyway.
- `--disable-scripts`: xzdiff/xzgrep need `/bin/sh` paths.

### lz4 1.11.0 (lz4, unlz4, lz4cat)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/lz4 | f2a71744 (2024-10-02), v1.10.0 |
| Termux packages/liblz4 | 1.11.0 via build/cmake, no patches |
| Alpine, buildroot | 1.10.0, no patches |
| OpenWrt | not found by name |

Chosen approach: `make -C programs lz4 CC AR CFLAGS LDFLAGS`. Static. `unlz4` (`-d`) and `lz4cat` (`-dc`) are
wrappers. No patches. CHECKSUM_SOURCE: `.sha256` published in the GitHub release.

Why:
- lz4 is plain C99 and POSIX, and threads come from bionic's pthread. No one patches it.
- 1.11.0 was 4 days old at survey time, and only Termux had shipped it. The survey therefore rated it less proven
  than 1.10.0.

### rsync 3.5.2 (dynamic)
Sources checked:
| Source | Observed |
|---|---|
| AOSP | absent (404) |
| Termux packages/rsync | 3.5.2 with system popt/zlib, openssl, xxhash, zstd, lz4, iconv, idn2; `--disable-xattr-support`; patches: lib/getpass.c `#ifndef HAVE_GETPASS`, rsync.h lock file path |
| Alpine main/rsync | 3.5.2; dont-use-nobody, syscall-skip-unsupported-symlink-chmod, 2 test patches |
| buildroot | 3.5.2 + openssl pkg-config patch |
| OpenWrt packages net/rsync | 3.5.1 |
| Zackptg5 | 3.2.7 via NDK |

Chosen approach:
- `LINKAGE=dynamic`. `configure_std --disable-openssl --disable-xxhash --disable-zstd --disable-lz4 --disable-md2man
  --disable-iconv --disable-acl-support --disable-xattr-support --with-included-popt --with-included-zlib
  --disable-idn --with-rsh=ssh`, then `make rsync`. No patches.
- CHECKSUM_SOURCE: `.asc`, key `8EDF88F4731A1E8B45D67FBE6909546B2C52EC2D`. buildroot pins the same sha256.

Why:
- rsync:// and daemon mode resolve names with `getaddrinfo`, so the binary is dynamic.
- With every optional dependency off, the build needs only the bundled popt and zlib.
- `lchmod` (API 36, in `libc.a`) is covered by `CONFIG_SITE`.
- bionic has no `getpass`, so `AC_REPLACE_FUNCS` builds lib/getpass.c. Termux's guard patch is not needed.
- bionic has no `<sys/acl.h>`, so ACL support is off. xattr support is off as in Termux.
- Stock Android has no `ssh`. Use `-e`/`--rsh` or daemon mode at runtime. The survey's
  `--with-rsyncd-conf=/data/local/etc/rsyncd.conf` is not passed, so a daemon needs `--config`.

### tree 2.3.2
Sources checked:
| Source | Observed |
|---|---|
| AOSP | absent (404) |
| Termux packages/tree | 2.3.2, plain make with `-D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64`, dep libandroid-support, no patches |
| Alpine 2.3.2, buildroot 2.2.1, OpenWrt packages utils/tree 2.3.1 | no patches |

Chosen approach: `make CC CFLAGS="$CFLAGS -std=c11 -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64" LDFLAGS`. Static.
No patches. CHECKSUM_SOURCE: upstream publishes no checksum or signature, so the sha256 was pinned at download.

Why:
- Upstream supports the NDK directly. The Makefile has an "Android NDK" block with the same defines and requires
  API >= 26.
- tree.h declares its own `strverscmp` for `__ANDROID__`, and `strverscmp.o` is always linked.
- Overriding CFLAGS drops the default `-Wconversion`/`-Wpedantic`.

### pv 1.12.7
Sources checked:
| Source | Observed |
|---|---|
| AOSP | absent |
| Termux packages/pv | 1.12.7, `--disable-ipc`; copy_file_range.patch (raw `syscall(__NR_copy_file_range)` for Android < API 34) |
| Alpine 1.12.7, buildroot 1.10.5, OpenWrt packages utils/pv 1.12.0 | no patches |

Chosen approach: `configure_std --disable-ipc --disable-copy-file-range`, then `make`. Static. No patches.
CHECKSUM_SOURCE: a detached signature `.txt` exists, but its key could not be obtained at pin time, so the
sha256 was pinned at download.

Why:
- `copy_file_range` (API 34) is in `libc.a`; it was hidden by the API-29 headers of the first v2 build and is visible at API 35. A probe that says yes would mean an
  implicit declaration in src/pv/transfer.c. Termux's syscall patch is not taken.
- `--remote` and `-d` use SysV shm/msg, which Android does not offer, so IPC is off as in Termux.

### bash 5.3.20
Sources checked:
| Source | Observed |
|---|---|
| AOSP | no external/bash; Android uses mksh (external/mksh 15480768, 2024-12-06) |
| Termux packages/bash | 5.3.20; `--enable-multibyte --without-bash-malloc --with-installed-readline --enable-progcomp` + `bash_cv_job_control_missing=present bash_cv_sys_siglist=yes bash_cv_func_sigsetjmp=present bash_cv_unusable_rtsigs=no ac_cv_func_mbsnrtowcs=no bash_cv_dev_fd=whacky bash_cv_getcwd_malloc=yes`; 13 patches, mostly prefix paths; functional: readline complete.c (no getpwent), loadables fdflags/getconf |
| Alpine main/bash | 5.3.9 (bash-noinfo.patch) |
| buildroot | 5.2.37 (+2) |
| OpenWrt packages utils/bash | 5.3 with 22 patches = upstream patches |
| Zackptg5 | bash 5.2 with Termux-derived patches |

Chosen approach:
- bash-5.3 plus the official `bash53-001`..`bash53-020` (patchlevel 20). They are fetched as `EXTRA_SRCS`, each
  pinned by sha256 and verified against its `.sig` at pin time, and applied with `patch -p0`.
- `configure_std --enable-static-link --without-bash-malloc --enable-multibyte --without-installed-readline
  --with-curses` plus Termux's cache answers above, plus `bash_cv_func_strchrnul_works=yes
  ac_cv_func_working_mktime=yes`.
- `CPPFLAGS += -DDEFAULT_PATH_VALUE="/system/bin:/system/xbin:/vendor/bin:/product/bin:/data/local/bin"
  -DSTANDARD_UTILS_PATH="/system/bin:/system/xbin"`.
- Static, with the bundled readline on ncursesw. No other patches.
- CHECKSUM_SOURCE: GNU `.sig` for the tarball and every patch, Chet Ramey key
  `7C0135FB088AAF6C66C650B9BB5869F064EA74AB`.

Why:
- configure runs AC_RUN tests, and a cross build needs answers for them. The bionic answers are Termux's.
- `strchrnul` and `mktime` also need answers. Otherwise configure builds compat copies that clash with `libc.a`
  in a static link.
- config-top.h uses `#ifndef` for the two path macros, so CPPFLAGS sets Android paths without a patch.
- Termux's prefix patches are not needed. Its readline getpwent patch is optional (getpwent only returns Android
  AIDs), and its loadables patches cover code that is not built.
- Temp files use `$TMPDIR`, which the wrapper sets.

### ncat (nmap 7.993, dynamic)
Sources checked:
| Source | Observed |
|---|---|
| AOSP | no external/nmap |
| Termux packages/nmap | 7.993, `--enable-static --with-liblua --without-nmap-update --without-zenmap --without-ndiff`; ncat patches: sockaddr_u.h (SUN_LEN fallback), ncat_posix.c/ncat_main.c (`/bin/sh` -> prefix), ncat_connect.c (`/tmp` -> prefix). Read at commit 7687cc4fbd5dd833e3709e86c2cd8b9159c9e005 |
| Alpine main/nmap | 7.992 (fortify-source.patch) |
| buildroot | 7.992 (+libdnet static, traceroute.cc cstddef) |
| OpenWrt packages net/nmap | 7.993, 2 patches; PKG_HASH equals the published SHA256 |
| Zackptg5 | nmap 7.93 |

Chosen approach:
- `LINKAGE=dynamic`. `configure_std --with-libpcap=$DEPROOT --without-openssl --without-liblua --without-libssh2
  --without-libz --without-zenmap --without-ndiff --without-nping --without-nmap-update --with-libpcre=included`,
  then `make build-ncat`. libpcap is the phase-1 static library.
- Patch `nmap/0001-ncat-android-paths-from-termux.patch`: Termux's four ncat patches at 7687cc4f, with
  `@TERMUX_PREFIX@/bin/sh` -> `/system/bin/sh` and `@TERMUX_PREFIX@/tmp` -> `/data/local/tmp`.
- CHECKSUM_SOURCE: `sigs/nmap-7.993.tar.bz2.asc`, Nmap Project key `436D66AB9A798425FDA0E3F801AF9F036B9355D0`,
  and the SHA256 in `sigs/nmap-7.993.tar.bz2.digest.txt`.

Why:
- The binary is dynamic because of `getaddrinfo`. The survey had raised the static-DNS problem as a hypothesis
  here first.
- Android has no `/bin/sh` and no `/tmp`, so `-c`/`--sh-exec` and the DGRAM unix-socket temp name would fail.
- bionic's `<sys/un.h>` defines `SUN_LEN` only under `__USE_BSD`/`__USE_GNU`. Termux's fallback avoids defining
  bionic-internal macros.
- The survey suggested `--with-libpcap=included` (top-level configure cannot drop pcap). The recipe links the
  libpcap already built for tcpdump instead.

### iftop 1.0pre4 (dynamic)
Sources checked:
| Source | Observed |
|---|---|
| AOSP | no external/iftop; external/libpcap dd978ad5 (2025-01-13), 1.10.5 |
| Termux, TUR | absent |
| Alpine main/iftop | 1.0_pre4; gcc15 cfgfile.h prototype fix, MAC address patch |
| buildroot package/iftop | 1.0pre4; 0001 ui_common.h `-fno-common` (extern globals), 0002 rename `pcap_filter` ("multiple definition" in static builds), 0003 function args (gcc 15, from Fedora). Read at commit fcf8bdc62aa419991273ff120d408273c8f85f1e |
| OpenWrt packages net/iftop | 010-gcc10.patch |
| Zackptg5 | 1.0pre4 at API >= 28; forces the configure pthread test and injects Bpthread.h (pthread_cancel emulation with SIGUSR1); `--with-resolver=netdb` |

Chosen approach:
- `LINKAGE=dynamic`. `LIBS=-lncursesw configure_std --with-libpcap=$DEPROOT --with-resolver=netdb`, then `make`.
  libpcap and ncursesw are static.
- Patches 0001-0003: buildroot's at fcf8bdc6, unchanged.
- Patch `iftop/0004-no-pthread_cancel-on-bionic.patch` is written for this module. On `__ANDROID__`, configure's
  POSIX threads probe detaches the worker instead of cancelling it, and iftop.c skips the final cancel of the
  resolver thread (process exit does that anyway).
- CHECKSUM_SOURCE: upstream publishes no checksum or signature. The sha256 was pinned at download and is the same
  file as Alpine community/iftop.

Why:
- The resolver thread calls `getnameinfo`, so the binary is dynamic.
- clang defaults to `-fno-common` (0001). The static libpcap.a link clashes on `pcap_filter` (0002). Prototype-less
  declarations break under C23 defaults (0003).
- bionic has no `pthread_cancel()`/`pthread_testcancel()`, so configure aborted with "can't figure out how to
  compile with POSIX threads". Zackptg5's signal-based emulation was not taken, which keeps the change to two
  `#ifdef`s.
- iftop upstream has been unmaintained since 2014.

### traceroute 2.1.6 (traceroute-ng, dynamic)
Sources checked:
| Source | Observed |
|---|---|
| AOSP | absent (the AOSP iputils fork has traceroute6 only, s20121221) |
| Termux packages/traceroute | 2.1.6, `make prefix=$PREFIX -e`; traceroute-flowlabel.h.patch. Read at commit 53da8982ee353176c6d56a6a19f49a159305e02c |
| Alpine community/traceroute | 2.1.6, reproducible-build.patch |
| buildroot | 2.1.6, no patches |
| OpenWrt | not found under that name |

Chosen approach:
- `LINKAGE=dynamic`. No configure: `make -j1 CC="$CC" DEPEND="$CC -MM -MG" AR RANLIB CFLAGS="$CFLAGS -include
  string.h" LDFLAGS`. Installed as the wrapper `traceroute-ng`.
- Patch `traceroute/0001-flowlabel-h-from-termux.patch`: Termux's at 53da8982, unchanged.
- CHECKSUM_SOURCE: upstream publishes no checksum or signature. The sha256 was pinned at download and equals
  buildroot's traceroute.hash.

Why:
- The binary is dynamic because of `getaddrinfo`/`getnameinfo`.
- bionic's `<netinet/in.h>` pulls in `<linux/in6.h>`, which already defines `struct in6_flowlabel_req`.
- Make.rules derives `gcc` from `CROSS`, so CC, DEPEND, AR and RANLIB are given explicitly.
- traceroute/mod-tcp.c relies on `<string.h>` arriving indirectly. glibc and musl headers provide it that way,
  bionic's do not, hence `-include string.h`. The survey had found no such issue.

### iputils 20250605 (arping-ng, tracepath-ng, dynamic)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/iputils | 9bc2137b (2024-12-20), SNAPSHOT s20121221, an ancient fork |
| Termux packages/tracepath | 20250605; compiles `iputils_common.c tracepath.c` by hand with `-DHAVE_ERROR_H`; tracepath.c patch (time.h, IPUTILS_VERSION). No ping (Android ships /system/bin/ping) |
| Alpine main/iputils | 20250605, getopt_long patch for ping |
| buildroot | 20250605, hash from `sha256sums.asc`, no patches |
| OpenWrt packages net/iputils | 20250605, version-without-git patch |

Chosen approach:
- `LINKAGE=dynamic`. A meson cross file (`system = 'android'`, `cpu_family = 'aarch64'`, c_args/c_link_args from
  CFLAGS/LDFLAGS), then `meson setup b --cross-file cross.ini -DUSE_CAP=false -DUSE_IDN=false -DUSE_GETTEXT=false
  -DBUILD_MANS=false -DBUILD_HTML_MANS=false -DSKIP_TESTS=true -DNO_SETCAP_OR_SUID=true -DBUILD_PING=false
  -DBUILD_CLOCKDIFF=false` and `ninja`.
- Only arping and tracepath are installed, as `arping-ng` and `tracepath-ng`.
- Patch `iputils/0001-meson-optional-libresolv.patch` is written for this module. It changes
  `cc.find_library('resolv')` to optional.
- CHECKSUM_SOURCE: `sha256sums.asc` in the GitHub release, key `2016FEA4858B1C36B32E833AC0DEC2EE72F33A5F`.

Why:
- arping and tracepath resolve host names, so they are dynamic.
- The NDK has no libresolv (the resolver is in libc), so the required `find_library` failed `meson setup`. The patch
  has the same effect as the survey's alternative, an empty libresolv.a, without adding a fake library.
- error.h, getrandom and `__fpending` are in bionic. meson.build has no `host_machine.system()` gate, so
  `system = 'android'` is safe.
- ping is not built, since Android ships its own. clockdiff is not built either.

### sysstat 12.8.0 (iostat, pidstat, mpstat)
Sources checked:
| Source | Observed |
|---|---|
| AOSP | absent |
| Termux, TUR | absent |
| Alpine community/sysstat | 12.7.8, no patches |
| buildroot | 12.7.5, no patches |
| OpenWrt packages utils/sysstat | 12.7.5, `--disable-documentation --disable-sensors`, 010-ldflags.patch |

Chosen approach:
- `configure_std --disable-sensors --disable-pcp --disable-documentation --disable-stripping --disable-file-attr
  sa_lib_dir=/data/local/lib/sa sa_dir=/data/local/var/log/sa conf_dir=/data/local/etc/sysconfig`, then `make
  iostat pidstat mpstat`. Static. No patches.
- The source is the `.tar.gz` (the survey listed the `.tar.xz`). CHECKSUM_SOURCE: the SHA1
  `bf343509a2a5a8019e72191ed6858659b868af6e` published on sysstat.github.io/versions.html. It matches the
  `.tar.gz`, and was verified at pin time.

Why:
- A grep for bionic-missing functions found none.
- The compiled-in paths are configure variables, so they point to `/data/local/...` without a patch.
- iostat, mpstat and pidstat need no daemon. sar and sadc need collected data and are not built.
- The `.tar.gz` is the file the only published checksum verifies.

### e2fsprogs 1.47.4 (e2fsck-ng, mke2fs-ng, tune2fs-ng, resize2fs-ng)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/e2fsprogs | ef148046 (2025-02-26), METADATA v1.46.6; the upstream tarball itself ships Android.bp. cflags `-Wall -Werror -Wno-*` |
| Termux packages/e2fsprogs | 1.47.4, `--disable-{defrag,e2initrd-helper,fsck,libuuid,libblkid,uuidd} --with-libarchive`; patches qsort, hasmntopt, fsmap.h, clang-compat, paths, libarchive soname (several date from 1.44-1.46) |
| Alpine, buildroot | 1.47.4, no patches; buildroot hash from `sha256sums.asc` |
| OpenWrt package/utils/e2fsprogs | 1.47.4, 3 patches |

Chosen approach:
- `configure_std --disable-fuse2fs --disable-uuidd --disable-fsck --disable-defrag --disable-e2initrd-helper
  --disable-backtrace --without-libarchive --disable-tdb ac_cv_func_qsort_r=no ac_cv_func_backtrace=no`.
- Then `make libs` and only `e2fsck`, `mke2fs`, `tune2fs` and `resize2fs`. Static. The wrappers carry the `-ng`
  suffix. No patches.
- CHECKSUM_SOURCE: kernel.org `sha256sums.asc`, autosigner key `B8868C80BA62A1FFFAF5FDA9632D3A06589DA6B1`.

Why:
- `qsort_r` (API 36) and `backtrace` (API 33) are in `libc.a` but hidden at 29. `CONFIG_SITE` already says no, and
  the recipe keeps both explicit. lib/support/sort_r.h then uses its own fallback.
- The internal libuuid/libblkid make the build self-contained. fuse2fs (libfuse), uuidd, the fsck wrapper and
  libarchive are left out.
- hasmntopt/setmntent are API 26, so Termux's hasmntopt patch (for API 24) is not needed.
- `/etc/mke2fs.conf` is absent on Android, so mke2fs uses its built-in defaults or `MKE2FS_CONFIG`.
- Android's own mke2fs/e2fsck are in /system/bin.

### f2fs-tools 1.17.0 (fsck.f2fs-ng, dump.f2fs-ng)
Sources checked:
| Source | Observed |
|---|---|
| git.kernel.org jaegeuk/f2fs-tools | tag `1.17.0` = 83fd39a184df96db5def895ddc55bf68e720ef76 = master head on 2026-11-08; no release tarballs, cgit snapshot only (Alpine uses the same URL) |
| AOSP platform/external/f2fs-tools | d34dcc88 (2025-03-20); Android.bp builds make_f2fs(.static), sload_f2fs, fsck.f2fs, `-DCONF_CASEFOLD -DCONF_PROJID` |
| Termux, TUR | absent |
| Alpine main/f2fs-tools | 1.17.0, musl patch adding `<linux/falloc.h>` to f2fs_io.c |
| buildroot | 1.16.0, musl lseek64/stdbool patches |
| OpenWrt package/utils/f2fs-tools | 1.16.0, `--without-blkid --without-lzo2 --without-lz4`, 1 patch |

Chosen approach:
- The pinned cgit snapshot of tag 1.17.0 (commit 83fd39a184df96db5def895ddc55bf68e720ef76), then `./autogen.sh`
  and `configure_std --without-selinux --without-blkid --without-lzo2 --without-lz4`.
- Then `make -C lib` and `make -C fsck LDFLAGS="$LT_LDFLAGS"`. Static.
- `fsck.f2fs` is also installed as `dump.f2fs`; it is the same binary, and the mode is chosen by argv[0].
- No patches. CHECKSUM_SOURCE: upstream publishes no release tarballs or checksums, so the snapshot's sha256 was
  pinned at download.

Why:
- `preadv2` (API 33) is in `libc.a`, and `CONFIG_SITE` answers no.
- Alpine's falloc include is unnecessary, because NDK `<fcntl.h>` includes `<linux/falloc.h>`. bionic has
  lseek64, so buildroot's musl patches do not apply.
- blkid, lzo2 and lz4 are off as in OpenWrt. selinux is off because there is no static libselinux.
- mkfs.f2fs is not built, so the survey's static libuuid for proper UUIDs is not linked.
- Android's own make_f2fs/fsck.f2fs are in /system/bin.

### elfutils 0.197 (libelf only, for bpftool)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external/elfutils | 2ddc8edd (2025-03-05), METADATA 0.191; libelf from `libelf/*.c` with `-include AndroidFixup.h` (rawmemchr, canonicalize_file_name) plus argp.h and libintl.h stubs in bionic-fixup/ |
| Termux packages/libelf | 0.197, 12 patches plus copied stdio_ext.h, obstack.h, qsort_r.h, aligned_alloc.c, search/ (full elfutils at API 24) |
| Alpine main/elfutils | 0.195, 4 musl patches |
| buildroot | 0.195 (+`--disable-progs` patch) |
| OpenWrt | 0.196 |

Chosen approach:
- `compat/libintl.h` is a header-only no-op shim (`dgettext`, `gettext`, `textdomain`, `bindtextdomain`), added
  with `-I`.
- configure gets these answers: `ac_cv_search_argp_parse='none required' ac_cv_search__obstack_free='none
  required' ac_cv_search_fts_close='none required'`, plus `configure_std --disable-debuginfod
  --disable-libdebuginfod --without-zstd --without-bzlib --without-lzma --disable-symbol-versioning
  --disable-demangler --disable-textrelcheck`.
- Only `lib/{eu-search,next_prime,crc32,xmalloc}.o` and `libelf/libelf.a` are built. They are archived together
  as `libelf.a`, and libelf.h, gelf.h and nlist.h are installed. No patches.
- CHECKSUM_SOURCE: `.sig`, key `6C2B631563B8D330578D3CB474FD3FA2779E7073`, and `sha512.sum` in the same
  directory.

Why:
- lib/eu-config.h includes `<libintl.h>` unconditionally, and bionic has no gettext.
- configure hard-fails without argp and obstack, which only the eu-* tools use, not libelf. The answers get
  config.h without building them.
- libelf needs those four libeu objects. The rest of libeu needs argp.
- AOSP does the same thing by listing the sources. This avoids Termux's full-elfutils patch set.

### bpftool 7.8.1 (no LLVM)
Sources checked:
| Source | Observed |
|---|---|
| github.com/libbpf/bpftool v7.8.1 | `bpftool-libbpf-v7.8.1-sources.tar.gz` (bundles the matching libbpf); upstream sha256 only for prebuilt binaries |
| AOSP platform/external/bpftool | ef58c558 (2024-12-20), v7.4.0; `-DBPFTOOL_WITHOUT_SKELETONS -DUSE_LIBCAP`, on device `-include linux/compiler.h` |
| AOSP platform/external/libbpf | 18f84302 (2025-03-05); `-DCOMPAT_NEED_REALLOCARRAY -include android/android.h` (`__poll_t`, which NDK r30 linux/types.h now defines) |
| Termux, TUR | no bpftool/libbpf. Unofficial github.com/NEURAX-FX/bpftool-termux-arm64 (pushed 2026-10-28) not evaluated |
| Alpine | bpftool from main/linux-tools 7.2.12; main/libbpf 1.8.0 (2 patches) |
| buildroot | bpftool v7.5.0, libbpf 1.6.2 |
| OpenWrt | bpftool 7.8.0, libbpf 1.8.0 |

Chosen approach:
- `qsort_r_decl.h` holds only a prototype, with the GNU argument order. It is added with `-include`.
- `make -C src CC AR HOSTCC=gcc HOSTAR=ar HOSTLD=ld LLVM_STRIP="$STRIP" SKIP_LLVM=1 SKIP_LIBBFD=1 SKIP_CRYPTO=1
  VMLINUX_BTF= feature-libcap=1 feature-zlib=1 feature-libelf=1 EXTRA_CFLAGS="$CFLAGS $CPPFLAGS -include
  qsort_r_decl.h" EXTRA_LDFLAGS="$LDFLAGS"`.
- Static, against libelf.a from elfutils, libcap.a and the NDK `libz.a`. No patches.
- CHECKSUM_SOURCE: upstream publishes no checksum for the sources tarball. The sha256 equals the GitHub release
  asset digest.
- Flavours (history): v2.0 shipped this NDK bpftool in lite and kept v1's Alpine bpftool with libLLVM (about
  172 MB) in full. v2.1-v2.2 shipped this NDK bpftool in both flavours, and the Alpine one is gone with the musl
  runtime; the flavours are now merged into one ZIP. Only JIT
  disassembly (`bpftool prog dump jited`, which needs LLVM or libbfd) and skeleton-based features are missing.
  `ndk/scripts/check.py` rejects a module without bpftool.

Why:
- `SKIP_LLVM`, `SKIP_LIBBFD` and `SKIP_CRYPTO` mean no LLVM, no libbfd and no libcrypto (signing).
- Skeletons need a host clang bootstrap and a `VMLINUX_BTF`. An empty `VMLINUX_BTF` builds without skeletons, the
  same as AOSP's `-DBPFTOOL_WITHOUT_SKELETONS`. That means no `prog profile` and no pid info in `map/prog show`
  [per survey].
- src/btf.c calls `qsort_r`, which is API 36. It is hidden by the API-35 headers but present in the static
  `libc.a`, so a prototype is enough and the code is unchanged.
- On older Android kernels BTF is usually absent, but `prog show`/`map show` still work as root [survey].

### LLVM 23.1.5, bcc 0.37.0 (symbol helpers), cereal 1.3.2 and bpftrace 0.27.1
Sources checked (2026-11-09):
| Source | Observed |
|---|---|
| github.com/bpftrace/bpftrace v0.27.1 | tag = commit `24e9fe60faff` (GitHub-verified signature). LLVM 18-23 accepted in Release builds; release binaries are a Nix build with LLVM 23 (flake.nix `defaultLlvmVersion = 23`); static CI (`.github/include/static.sh`, `docker/Dockerfile.static`) uses Alpine 3.22 with LLVM 18 static and `-DSTATIC_LINKING=ON -DBUILD_TESTING=OFF`. Static LLVM link (src/ast/CMakeLists.txt): `bpfcodegen coverage frontenddriver frontendhlsl frontendopenmp ipo irreader lto mcjit option orcjit` + `LLVM_TARGETS_TO_BUILD`, clang `libclang_static clangDriver clangFrontend clangCodeGen`. Only the BPF backend is initialised (codegen_llvm.cpp). Uses bcc only through `bcc_syms.h`, `bcc_elf.h`, `bcc_proc.h`. libbpf is the submodule at `85c0d575a447`. Has an `if(ANDROID)` branch for `STATIC_LINKING` |
| facebookexperimental/ExtendedAndroidTools | main `c80b92fb2da2` (2026-02-06): the only NDK bpftrace build found (v0.24.1, LLVM 18.1.8, NDK r27b, API 30). No patch files: host LLVM build of `llvm-config llvm-tblgen clang-tblgen`, target build with `LLVM_TABLEGEN`/`CLANG_TABLEGEN`, `LLVM_ENABLE_RTTI=yes`, `LIBCLANG_BUILD_STATIC=ON`, BPF-only targets in its static CI job; full libbcc (`-include strings.h`, `BPS_LINK_RT=OFF`); bpftrace `-DSTATIC_LINKING=ON -DBUILD_TESTING=OFF -DENABLE_MAN=OFF -DUSE_SYSTEM_LIBBPF=ON` |
| AOSP | no platform/external/bpftrace (404). external/bcc `8aa864777004` builds only `libbpf.c perf_reader.c bcc_zip.c` (no LLVM) |
| Termux | no bpftrace or bcc package (request termux-packages#27981). packages/libllvm 21.1.8: host tablegen stage, `LLVM_NATIVE_TOOL_DIR`, `LLVM_HOST_TRIPLE=aarch64-unknown-linux-android<API>`, RTTI on. Its `#undef CS`/`#undef SS` patches are for x86 NDK headers only |
| Alpine community/bpftrace, community/bcc | 0.27.1 with LLVM 20, system bcc 0.37.0 and libbpf; one patch for 32-bit `HAVE_DW_UNWIND` code (x86_64-only here) |
| buildroot package/bpftrace, bcc, llvm-project | bpftrace 0.27.0, LLVM 23.1.5 shared, glibc only; RTTI mandatory (bpftrace issue #1156); bcc patch for LLVM 23 touches only `src/cc/bcc_debug.cc` (not built here) |
| Nixpkgs pkgs/by-name/bp/bpftrace | 0.27.1, shared LLVM, system bcc/libbpf, `-DSYSTEM_INCLUDE_PATHS=<glibc>/include`; pkgsCross/pkgsStatic not evaluated [U] |
| llvm.org/docs/CMake.html | `LLVM_NATIVE_TOOL_DIR`: directory with native llvm-tblgen/clang-tblgen, no native sub-build is made |

Chosen approach:
- Builder: `ndk/Dockerfile` adds `g++` and `xxd` (same Debian snapshot, separate layer after the NDK). g++ builds
  LLVM's native tablegen tools; xxd is required by bpftrace's `cmake/Embed.cmake`.
- `llvm` (library recipe, nothing shipped): stage 1 builds `llvm-min-tblgen llvm-tblgen clang-tblgen` for the
  host with gcc/g++. Stage 2 cross-builds with the NDK cmake toolchain, `LLVM_NATIVE_TOOL_DIR` = stage 1,
  `LLVM_HOST_TRIPLE=aarch64-unknown-linux-android35` (as Termux), `LLVM_ENABLE_PROJECTS=clang`,
  `LLVM_TARGETS_TO_BUILD=BPF`, Release, `LLVM_ENABLE_RTTI=ON`, `LIBCLANG_BUILD_STATIC=ON`, `LLVM_ENABLE_PIC=ON`
  (with PIC off libclang is built static-only under the name `libclang`, and bpftrace links the target
  `libclang_static`, which exists only next to the shared one), tools/utils/tests/benchmarks/examples/docs/bindings off, static analyzer, ObjC
  rewriter and plugins off, zlib/zstd/libxml2/libedit/libpfm/ffi/curl/telemetry off, no libLLVM dylib,
  `LLVM_PARALLEL_LINK_JOBS=2`. Installed into the private prefix only (headers, static libraries, CMake
  package files; the shared libclang/libclang-cpp built because of PIC are not used).
- `bcc` (library recipe): only upstream's `bcc-loader-static` sources (`bcc_syms.cc bcc_elf.c bcc_perf_map.c
  bcc_proc.c bcc_zip.c common.cc`, src/cc/CMakeLists.txt) compiled with the NDK compiler into
  `libbcc-loader-static.a`, plus `bcc_syms.h bcc_proc.h bcc_elf.h`. No LLVM, no clang frontend, no debuginfod;
  `-DHAVE_LIBLZMA` (liblzma from the xz recipe) so symbols in `.gnu_debugdata` (MiniDebugInfo, as in Android
  system libraries) are read. bpftrace's static link requires liblzma anyway (src/CMakeLists.txt; EAT adds
  `liblzma.a` by hand for the same reason). bpftrace's `LIBBCC_LIBRARIES`, `LIBBCC_BPF_LIBRARIES` and
  `LIBBCC_LOADER_LIBRARY_STATIC` all point to this archive; `common.cc`'s BTF calls resolve to bpftrace's libbpf.
- `cereal`: header-only, `include/cereal` copied. Patch `0001-tuple-template-args-from-upstream.patch` is
  upstream commit `d81e2f7df7b3` (2026-03-06, not in a release): clang 19+ rejects `::template apply(`
  without template arguments, which bpftrace's `src/required_resources.cpp` instantiates.
- `bpftrace`: the libbpf submodule commit is an `EXTRA_SRCS` archive unpacked into `libbpf/`, built by
  bpftrace's own `cmake/FindLibBpf.cmake` with `BUILD_STATIC_ONLY=y` and the recipe's CFLAGS. CMake with the
  NDK toolchain, `-DSTATIC_LINKING=ON -DBUILD_TESTING=OFF -DENABLE_MAN=OFF -DENABLE_SYSTEMD=OFF
  -DENABLE_SKB_OUTPUT=ON` (libpcap recipe) `-DUSE_SYSTEM_LIBBPF=OFF`, LLVM/Clang CMake packages and the bcc,
  libelf, liblzma, cereal and libpcap paths from the private prefix; only the `bpftrace` target is built.
  `SYSTEM_INCLUDE_PATHS` keeps upstream's `auto` (it runs `clang-23` at run time if present, else falls back).
- Patch `ndk/patches/bpftrace/0001-android-static-link.patch` drops `-Wl,-Bdynamic` from the Android
  `STATIC_LINKING` branch so `-ldl -lm -lz` come from the NDK static archives: bpftrace calls neither
  `dlopen()` nor `getaddrinfo()`, so the static rule above applies.
- CHECKSUM_SOURCE: LLVM `.sig` verified with key `FFB3368980F3E6BB5737145A316C56D064CACBA5` (Douglas Yung,
  releases.llvm.org/release-keys.asc); bpftrace: the tag archive is identical to the git tree of the
  GitHub-signed tag commit; bcc: GitHub release asset digest (no signature); cereal and the libbpf commit
  archive: no upstream checksum, sha256 recorded at pin time.

Why:
- LLVM 23 is the newest major bpftrace 0.27.1 accepts and the one its release binaries use; 23.1.5 is its
  latest point release. BPF is the only backend bpftrace initialises; clang is needed because bpftrace
  compiles its C stdlib and C definitions in-process (clang CodeGen, libclang C API).
- bcc's full library needs its own LLVM frontend (and an unreleased fix for LLVM 23); bpftrace uses only the
  symbol-resolution helpers, which upstream already builds LLVM-free as `bcc-loader-static`.
- bpftrace needs no runtime files: its stdlib, headers and libbpf headers are embedded in the binary.
  Without libdw, DWARF-based uprobe argument types are unavailable (BTF and C definitions still work);
  blazesym, libbfd disassembly and systemd are off.

### talloc 2.5.0 (library for mount.cifs)
Sources checked:
| Source | Observed |
|---|---|
| AOSP platform/external, LineageOS android_external_talloc | absent |
| buildroot package/libtalloc/libtalloc.mk | 2.4.4 waf-package: `--cross-compile --cross-answers=cache.txt --disable-stack-protector --hostcc=gcc`, `--disable-python`; cache file answers the run-time checks for glibc/musl |
| Termux | no talloc package |

Chosen approach:
- `./configure --prefix=/usr --disable-python --disable-rpath --cross-compile --cross-answers=cross-answers.txt
  --hostcc=gcc`, with `LDFLAGS` without `-static`, so waf's link tests use the API-35 `libc.so` stubs (waf does not
  read the generated CONFIG_SITE). The answers file in the recipe gives the 17 results for aarch64 bionic (uname,
  large file support, strtoll, strptime, C99 vsnprintf, shared mmap, mremap, no incoherent mmap, secure mkstemp);
  the recipe fails if waf adds an UNKNOWN entry.
- waf builds only a shared `libtalloc.so`, so the recipe compiles `talloc.c` and `lib/replace/replace.c` against
  waf's `bin/default/config.h` and archives them as `libtalloc.a`; it installs `talloc.h` and a written
  `talloc.pc`. No patches.
- CHECKSUM_SOURCE: `.asc` over the uncompressed tar, Samba Library Distribution Key
  `9147A339719518EE9011BCB54793916113084025`.

### cifs-utils 7.9 (mount.cifs)
Sources checked:
| Source | Observed |
|---|---|
| AOSP, LineageOS, Termux (packages/, root-packages/, x11-packages/) | absent |
| buildroot package/cifs-utils | 7.8, `--disable-pie --disable-man`, `-std=gnu11`, depends on libtalloc; no patches |
| OpenWrt packages net/cifs-utils | 7.7, `--disable-cifsupcall --disable-cifscreds --disable-cifsidmap --disable-cifsacl --disable-pam --disable-pie --disable-relro --disable-systemd --disable-man --without-libcap`, depends on libtalloc |
| Nix pkgs/by-name/ci/cifs-utils | 7.5; cross: `ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes` |
| Alpine main/cifs-utils | 7.5 (v1 binary); APKBUILD not re-read (HTTP 403) |

Chosen approach:
- Deps: talloc, libcap (static). `LINKAGE=dynamic`: mount.cifs resolves the server name with `getaddrinfo`.
- `ndk/patches/cifs-utils/0001-bionic-compat.patch` adds `android_compat.{c,h}`: `addmntent()` and `getpass()`
  (as in musl 1.2.5, MIT), `_PATH_MNTTAB` (`/etc/fstab`, only read for non-root user mounts) and
  `_PATH_MOUNTED_LOCK`; `mtab_unusable()` treats bionic's `_PATH_MOUNTED` (`/proc/mounts` itself) like an mtab
  symlink, so mount.cifs never tries to lock or append to the kernel table; `cldap_ping.c` uses `memset()`
  instead of `bzero()`, which bionic removed.
- The recipe compiles `android_compat.c` into `compat/libandroidcompat.a` passed in `LIBS` (so configure's
  `getpass` check passes) and creates an empty `compat/libresolv.a` (Makefile.am hard-codes `-lresolv`; bionic
  has `res_query` in libc).
- `configure_std --disable-cifsupcall --disable-cifscreds --disable-cifsidmap --disable-cifsacl --disable-smbinfo
  --disable-pythontools --disable-pam --disable-systemd --disable-man --with-libcap=yes` (as OpenWrt, but with
  libcap so mount.cifs drops capabilities as upstream intends), `ac_cv_func_malloc_0_nonnull=yes
  ac_cv_func_realloc_0_nonnull=yes` (as Nix for cross), `make mount.cifs`.
- CHECKSUM_SOURCE: `.asc`, cifs-utils Distribution Verification Key `C699981A31F338706C817650DF5BA9D30642D5A0`.

Why: v2.0 left mount.cifs on Alpine because of talloc and the missing addmntent/getpass. talloc is kept (it is
used by the DFS cldap ping in `resolve_host`), not patched out. Many Android kernels lack `CONFIG_CIFS`; the
phone test checks only the version and help output.

### Not ported
None since v2.1: every tool of v1 (and wg-quick, awg, awg-quick, drill, ethtool-ng) is an NDK build. Since
v2.2-r2 there is no Alpine fallback: `ndk/scripts/stage.py` fails if a tool of `ndk/tools.tsv` has no NDK build,
and `ndk/scripts/check.py` fails on a `lib/` directory, the resolv.conf overlay, or ELF files outside
`$ALTDIR/libexec/`.
