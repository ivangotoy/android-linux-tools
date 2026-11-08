#!/system/bin/sh
# android-linux-tools phone test (device independent, POSIX sh for mksh/toybox).
# Run as root:  sh /data/adb/modules/android-linux-tools/share/android-linux-tools/phone-test.sh
MODDIR=/data/adb/modules/android-linux-tools
PASS=0
FAIL=0
SKIP=0
TO=""
if command -v timeout >/dev/null 2>&1; then TO="timeout 30"; fi

if [ "$(id -u)" != "0" ]; then
  echo "must run as root"
  exit 2
fi
if [ ! -r "$MODDIR/module.prop" ]; then
  echo "module not installed at $MODDIR"
  exit 2
fi

FLAVOUR=$(sed -n 's/^flavour=//p' "$MODDIR/module.prop")
echo "== $(sed -n 's/^version=//p' "$MODDIR/module.prop") flavour=$FLAVOUR kernel=$(uname -r)"

result() {
  case "$1" in
    ok) PASS=$((PASS + 1)); echo "PASS $2" ;;
    skip) SKIP=$((SKIP + 1)); echo "SKIP $2 :: $3" ;;
    *) FAIL=$((FAIL + 1))
       echo "FAIL $2 rc=$3 :: $(printf '%s' "$4" | head -n 3 | tr '\n' ' ' | cut -c1-200)" ;;
  esac
}

MAP=$(alt-list -m 2>/dev/null)
if [ -z "$MAP" ]; then
  result bad alt-list 1 "alt-list -m gave no output"
fi

# tn TOOL: installed command name for TOOL (after -ng renames), empty if not installed
tn() {
  printf '%s\n' "$MAP" | while read -r o n d; do
    if [ "$o" = "$1" ]; then
      printf '%s\n' "$n"
      break
    fi
  done
}

# missing TOOL LABEL: report a tool that is not installed
missing() {
  if [ "$1" = bpftool ] && [ "$FLAVOUR" = lite ]; then
    result skip "$2" "bpftool is only in the full flavour"
  else
    result bad "$2" 127 "$1 not installed"
  fi
}

# chk LABEL REGEX TOOL ARGS... : pass if exit<126 and output matches REGEX (case-insensitive)
chk() {
  label=$1
  pat=$2
  tool=$3
  shift 3
  cmd=$(tn "$tool")
  if [ -z "$cmd" ]; then
    missing "$tool" "$label"
    return
  fi
  out=$($TO "$cmd" "$@" 2>&1 </dev/null)
  rc=$?
  if [ "$rc" -lt 126 ] && printf '%s\n' "$out" | grep -qiE "$pat"; then
    result ok "$label"
  else
    result bad "$label" "$rc" "$out"
  fi
}

# vchk TOOL REGEX ARGS... : version/help check, label = TOOL
vchk() {
  vt=$1
  vp=$2
  shift 2
  chk "$vt" "$vp" "$vt" "$@"
}

# fchk LABEL TOOL ARGS... : pass if exit status 0
fchk() {
  label=$1
  tool=$2
  shift 2
  cmd=$(tn "$tool")
  if [ -z "$cmd" ]; then
    missing "$tool" "$label"
    return
  fi
  out=$($TO "$cmd" "$@" 2>&1 </dev/null)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    result ok "$label"
  else
    result bad "$label" "$rc" "$out"
  fi
}

KCONF=""
if [ -r /proc/config.gz ]; then
  KCONF=$(gzip -dc /proc/config.gz 2>/dev/null || zcat /proc/config.gz 2>/dev/null)
fi
# kfeat CONFIG_A [CONFIG_B...]: 0 = all present (y/m), 1 = one absent, 2 = unknown (no /proc/config.gz)
kfeat() {
  [ -n "$KCONF" ] || return 2
  for k in "$@"; do
    printf '%s\n' "$KCONF" | grep -qE "^$k=(y|m)$" || { KMISS=$k; return 1; }
  done
  return 0
}
KPAT='protocol not supported|operation not supported|not supported by|kernel error|cannot open session|no such file or directory|address family not supported|unknown family'

# kchk LABEL "CONFIG..." TOOL ARGS... : like fchk, SKIP if the kernel lacks the feature
kchk() {
  label=$1
  cfgs=$2
  tool=$3
  shift 3
  KMISS=""
  kfeat $cfgs
  ks=$?
  if [ "$ks" = 1 ]; then
    result skip "$label" "kernel lacks $KMISS"
    return
  fi
  cmd=$(tn "$tool")
  if [ -z "$cmd" ]; then
    missing "$tool" "$label"
    return
  fi
  out=$($TO "$cmd" "$@" 2>&1 </dev/null)
  rc=$?
  if [ "$rc" -eq 0 ]; then
    result ok "$label"
  elif [ "$ks" = 2 ] && printf '%s\n' "$out" | grep -qiE "$KPAT"; then
    result skip "$label" "kernel support missing (no /proc/config.gz): $(printf '%s' "$out" | head -n 1 | cut -c1-120)"
  else
    result bad "$label" "$rc" "$out"
  fi
}

ORIGINS="$MODDIR/share/android-linux-tools/origins.txt"
# origin TOOL: ndk|alpine (v2 modules); empty for v1 modules without origins.txt
origin() {
  [ -r "$ORIGINS" ] || return 0
  while read -r ot oo ov ol; do
    if [ "$ot" = "$1" ]; then
      printf '%s\n' "$oo"
      break
    fi
  done < "$ORIGINS"
}
if [ -r "$ORIGINS" ]; then
  echo "== origins (tool installed-name origin version linkage)"
  grep -v '^#' "$ORIGINS" | while read -r ot oo ov ol; do
    echo "ORIGIN $ot $(tn "$ot") $oo $ov $ol"
  done
fi

echo "== installed tools (alt-list)"
W=/data/local/tmp/alttoolstest.$$
mkdir -p "$W"
printf '%s\n' "$MAP" > "$W/map"
while read -r o n d; do
  [ -n "$o" ] || continue
  p=$(command -v "$n" 2>/dev/null)
  if [ -z "$p" ]; then
    result bad "path:$n" 127 "not in PATH"
  elif head -c 400 "$p" 2>/dev/null | grep -q "MODDIR=$MODDIR"; then
    result ok "path:$n"
  else
    result bad "path:$n" 1 "$p is not the module wrapper"
  fi
  if [ "$o" != "$n" ]; then
    q=$(command -v "$o" 2>/dev/null)
    if [ -n "$q" ] && head -c 400 "$q" 2>/dev/null | grep -q "MODDIR=$MODDIR"; then
      result bad "noshadow:$o" 1 "$q is the module wrapper"
    else
      result ok "noshadow:$o (device: ${q:-$d}, module: $n)"
    fi
  fi
done < "$W/map"

echo "== version/help"
vchk nft 'nftables v[0-9]' --version
vchk ipset 'ipset v[0-9]' version
vchk conntrack 'conntrack v[0-9]' --version
vchk nfct 'nfct|usage' --version
vchk wg 'wireguard-tools v[0-9]' --version
vchk bridge 'bridge utility, v?[0-9]' -V
vchk ethtool-ng 'ethtool version [0-9]' --version
vchk ip-ng 'utility, iproute2-[0-9]' -V
vchk tc-ng 'utility, iproute2-[0-9]' -V
vchk ss-ng 'utility, iproute2-[0-9]' -V
vchk bpftool 'bpftool v[0-9]' version
vchk getfacl 'getfacl [0-9]' --version
vchk setfacl 'setfacl [0-9]' --version
vchk mount.cifs 'mount.cifs version: [0-9]' -V
vchk iperf3 'iperf [0-9]' --version
vchk tcpdump 'tcpdump version [0-9]' --version
vchk strace 'strace -- version [0-9]' -V
vchk capsh 'Current: ' --print
vchk getpcaps '^1' 1
vchk setpriv 'setpriv from util-linux' --version
vchk lsblk 'lsblk from util-linux' --version
vchk blkid-ng 'blkid from util-linux' -V
vchk findmnt 'findmnt from util-linux' --version
vchk lscpu 'lscpu from util-linux' --version
vchk curl 'curl [0-9]' --version
vchk drill 'drill version [0-9]' -v
vchk dig 'DiG [0-9]' -v
vchk host 'host [0-9]' -V
vchk mtr 'mtr [0-9]' --version
vchk socat 'socat version [0-9]' -V
vchk htop 'htop [0-9]' --version
vchk iostat 'sysstat version [0-9]' -V
vchk pidstat 'sysstat version [0-9]' -V
vchk mpstat 'sysstat version [0-9]' -V
vchk sqlite3 '^3\.[0-9]+\.[0-9]+' --version
vchk rsync 'rsync +version [0-9]' --version
vchk zstd 'Zstandard CLI' -V
vchk unzstd 'Zstandard CLI' -V
vchk zstdcat 'Zstandard CLI' -V
vchk xz 'xz \(XZ Utils\)' --version
vchk unxz 'xz \(XZ Utils\)' --version
vchk xzcat 'xz \(XZ Utils\)' --version
vchk lz4 'lz4.* v[0-9]' -V
vchk unlz4 'lz4.* v[0-9]' -V
vchk lz4cat 'lz4.* v[0-9]' -V
vchk e2fsck-ng 'e2fsck [0-9]' -V
vchk mke2fs-ng 'mke2fs [0-9]' -V
vchk tune2fs-ng 'tune2fs [0-9]'
vchk resize2fs-ng 'resize2fs [0-9]'
vchk fsck.f2fs-ng 'f2fs [0-9]' -V
vchk dump.f2fs-ng 'f2fs [0-9]' -V
vchk traceroute-ng 'Modern traceroute' --version
vchk arping-ng 'from iputils' -V
vchk tracepath-ng 'from iputils' -V
vchk tmux 'tmux [0-9]' -V
vchk nano 'GNU nano, version [0-9]' --version
vchk less 'less [0-9]' --version
vchk jq '^jq-[0-9]' --version
vchk bash 'GNU bash, version [0-9]' --version
vchk ncat 'Version [0-9.]+ \(' --version
vchk iftop 'Synopsis: iftop|iftop, version' -h
vchk tree 'tree v[0-9]' --version
vchk pv 'pv [0-9]' --version

echo "== functional"
TMUXDIR_EXISTED=0
[ -d /data/local/tmp/tmux-0 ] && TMUXDIR_EXISTED=1
NFT=$(tn nft)
kchk nft-add "CONFIG_NF_TABLES CONFIG_NF_TABLES_INET" nft add table inet alttoolstest
if [ -n "$NFT" ] && "$NFT" list table inet alttoolstest >/dev/null 2>&1; then
  fchk nft-list nft list table inet alttoolstest
  fchk nft-delete nft delete table inet alttoolstest
fi
kchk ipset-create "CONFIG_IP_SET CONFIG_IP_SET_HASH_IP" ipset create alttoolstest hash:ip
IPSET=$(tn ipset)
if [ -n "$IPSET" ] && "$IPSET" list -n alttoolstest >/dev/null 2>&1; then
  fchk ipset-add ipset add alttoolstest 192.0.2.1
  chk ipset-list '192\.0\.2\.1' ipset list alttoolstest
  fchk ipset-destroy ipset destroy alttoolstest
fi
kchk conntrack-count "CONFIG_NF_CONNTRACK CONFIG_NF_CT_NETLINK" conntrack -C
kchk wg-show "CONFIG_WIREGUARD" wg show all
kchk bridge-link "CONFIG_BRIDGE" bridge link
chk tc-ng-qdisc 'qdisc' tc-ng qdisc show dev lo
chk ethtool-ng-lo 'Settings for lo|Link detected' ethtool-ng lo
chk bpftool-version 'bpftool v[0-9]' bpftool version
chk getfacl-dir 'owner' getfacl /data/local/tmp

echo "== DNS"
if [ -f "$MODDIR/share/android-linux-tools/resolv-refresh" ]; then
  # v1 resolv.conf overlay, only shipped while some Alpine (musl) network tools remain
  ALT_DNS_FORCE=1 /system/bin/sh "$MODDIR/share/android-linux-tools/resolv-refresh" >/dev/null 2>&1
  if grep -q '^nameserver ' "$MODDIR/etc/resolv.conf" 2>/dev/null; then
    result ok "dns-resolvconf ($(grep '^nameserver ' "$MODDIR/etc/resolv.conf" | sed 's/^nameserver //' | tr '\n' ' '))"
    if [ -L /system/etc/resolv.conf ] && grep -q '^nameserver ' /etc/resolv.conf 2>/dev/null; then
      result ok dns-overlay
    elif [ -e /system/etc/resolv.conf ] && [ ! -L /system/etc/resolv.conf ]; then
      result skip dns-overlay "device ships its own /system/etc/resolv.conf"
    else
      result bad dns-overlay 1 "/etc/resolv.conf does not point to $MODDIR/etc/resolv.conf (overlay not mounted?)"
    fi
  else
    result skip dns-resolvconf "no DNS servers found on the active network (offline?)"
  fi
else
  echo "no resolv.conf overlay in this build (all network tools use Android netd)"
fi
[ -e /etc/resolv.conf ] && echo "note: /etc/resolv.conf exists ($(readlink /etc/resolv.conf 2>/dev/null || echo file))"
NS=""
[ -f "$MODDIR/share/android-linux-tools/dns-servers" ] && NS=$(/system/bin/sh "$MODDIR/share/android-linux-tools/dns-servers" 2>/dev/null | tr '\n' ' ')
echo "active network DNS servers: ${NS:-none found}"
# dnschk LABEL REGEX TOOL ARGS...: like chk, but prints the tool origin; SKIP when offline
dnschk() {
  dl=$1
  dp=$2
  dt=$3
  shift 3
  if [ -z "$(tn "$dt")" ]; then
    result skip "$dl" "$dt not installed"
    return
  fi
  if [ -z "$NS" ] && ! ping -c 1 -W 3 example.com >/dev/null 2>&1; then
    result skip "$dl" "offline (no DNS servers, ping example.com fails)"
    return
  fi
  chk "$dl [$(origin "$dt")]" "$dp" "$dt" "$@"
}
dnschk curl-https '^HTTP/' curl -sI --max-time 20 https://example.com
dnschk drill-example 'rcode: NOERROR' drill example.com
dnschk dig-short '^[0-9a-f:.]+$' dig +short example.com
out=$($TO ping -c 1 -W 3 example.com 2>&1)
if printf '%s\n' "$out" | grep -qiE '^PING example\.com'; then
  result ok bionic-dns-unaffected
elif printf '%s\n' "$out" | grep -qiE 'unknown host|bad address'; then
  result bad bionic-dns-unaffected 1 "$out"
else
  result skip bionic-dns-unaffected "ping unusable: $(printf '%s' "$out" | head -n 1 | cut -c1-80)"
fi

echo "== misc"
chk iperf3-version 'iperf' iperf3 --version
chk tcpdump-version 'tcpdump' tcpdump --version
chk strace-version 'strace' strace -V
chk htop-version 'htop' htop --version
chk tmux-version 'tmux' tmux -V
printf 'android-linux-tools roundtrip test\n' > "$W/a"
T_ZSTD=$(tn zstd); T_ZSTDCAT=$(tn zstdcat); T_XZ=$(tn xz); T_XZCAT=$(tn xzcat); T_LZ4=$(tn lz4); T_LZ4CAT=$(tn lz4cat)
T_JQ=$(tn jq); T_TMUX=$(tn tmux)
out=$("$T_ZSTD" -q -c "$W/a" | "$T_ZSTDCAT" 2>&1)
if [ "$out" = "android-linux-tools roundtrip test" ]; then result ok zstd-roundtrip; else result bad zstd-roundtrip 1 "$out"; fi
out=$("$T_XZ" -c "$W/a" | "$T_XZCAT" 2>&1)
if [ "$out" = "android-linux-tools roundtrip test" ]; then result ok xz-roundtrip; else result bad xz-roundtrip 1 "$out"; fi
out=$("$T_LZ4" -q -c "$W/a" | "$T_LZ4CAT" 2>&1)
if [ "$out" = "android-linux-tools roundtrip test" ]; then result ok lz4-roundtrip; else result bad lz4-roundtrip 1 "$out"; fi
out=$(echo '{"a":3}' | "$T_JQ" .a 2>&1)
if [ "$out" = 3 ]; then result ok jq-eval; else result bad jq-eval 1 "$out"; fi
chk sqlite3-eval '^2$' sqlite3 :memory: 'select 1+1;'
chk bash-eval '^ok$' bash -c 'echo ok'
out=$("$T_TMUX" -L alttoolstest new-session -d -s alttoolstest 'sleep 30' 2>&1 && "$T_TMUX" -L alttoolstest ls 2>&1)
"$T_TMUX" -L alttoolstest kill-server >/dev/null 2>&1
if printf '%s\n' "$out" | grep -q alttoolstest; then result ok tmux-session; else result bad tmux-session 1 "$out"; fi
chk lsblk-list 'NAME' lsblk
chk findmnt-data 'TARGET' findmnt /data

echo "== cleanup"
[ -n "$NFT" ] && "$NFT" delete table inet alttoolstest >/dev/null 2>&1
[ -n "$IPSET" ] && "$IPSET" destroy alttoolstest >/dev/null 2>&1
[ -n "$T_TMUX" ] && "$T_TMUX" -L alttoolstest kill-server >/dev/null 2>&1
rm -rf "$W"
rm -f /data/local/tmp/tmux-0/alttoolstest
[ "$TMUXDIR_EXISTED" = 0 ] && rmdir /data/local/tmp/tmux-0 2>/dev/null
echo "renamed on this device: $(alt-list -r 2>/dev/null | tr '\n' ';')"
echo "SKIPPED $SKIP"
echo "TOTAL pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
