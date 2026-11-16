# ndk/scripts/stage.py (real script, in bwrap) against a synthetic /work/out: every tools.tsv program is a copy of
# a host ELF, one meta record per recipe, a fake NDK sysroot. The module must ship the NDK sysroot NOTICE (bionic,
# linked into every program) with a licence row in NOTICE.txt and MANIFEST.json.
. "$ALT_TESTS/lib.sh"
ALT_TOOLS="$ALT_TOOLS readelf"
h=$(alt_scratch)
mkdir -p "$h/work/out/meta" "$h/work/out/bin" "$h/work/out/data" "$h/work/stage" "$h/sysroot"
python3 -I - "$ALT_TREE/ndk/tools.tsv" "$h/work/out" "$(type -P true)" <<'PY'
import json, os, shutil, sys
tsv, out, elf = sys.argv[1:4]
recipes = {'ncurses', 'cacert'}
for line in open(tsv):
    if line.strip() and not line.startswith('#'):
        name, recipe, binary = line.split()[:3]
        recipes.add(recipe)
        shutil.copyfile(elf, os.path.join(out, 'bin', binary))
for r in recipes:
    json.dump({'recipe': r, 'version': '1.0', 'url': 'https://example.org/%s-1.0.tar.gz' % r, 'sha256': '0' * 64,
               'checksum_source': 'example', 'license': 'MIT', 'deps': [], 'patches': [], 'bins': [],
               'recipe_hash': '0' * 16, 'linkage': 'static'}, open(os.path.join(out, 'meta', r + '.json'), 'w'))
open(os.path.join(out, 'data', 'cacert.pem'), 'w').write('# example CA bundle\n')
PY
printf 'Copyright (c) example\nRedistribution and use in source and binary forms ...\n' > "$h/sysroot/NOTICE"
alt_bwrap "$h/root" "$ALT_TREE" "$h/work" --ro-bind "$h/sysroot" /opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot \
  --setenv SYSROOT /opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot --setenv NDK_RELEASE r30 --setenv API 35 \
  python3 -I /src/ndk/scripts/stage.py > "$h/stage.txt" 2>&1 || { bad "stage.py failed: $(tail -n 3 "$h/stage.txt")"; rm -rf "$h"; exit 1; }
st="$h/work/stage/module/android-linux-tools"
if cmp -s "$h/sysroot/NOTICE" "$st/share/licenses/ndk/android-ndk-sysroot/NOTICE"; then
  ok "NDK sysroot NOTICE shipped as share/licenses/ndk/android-ndk-sysroot/NOTICE"
else
  bad "NDK sysroot NOTICE not in share/licenses/ndk/android-ndk-sysroot/"
fi
if grep -q '^android-ndk-sysroot  *r30 ' "$st/share/licenses/NOTICE.txt"; then ok "NOTICE.txt row"; else bad "no NOTICE.txt row for android-ndk-sysroot"; fi
python3 -I - "$st/system/etc/android-linux-tools/share/android-linux-tools/MANIFEST.json" <<'PY' && ok "MANIFEST.json licence row" || bad "no MANIFEST.json licence row for android-ndk-sysroot"
import json, sys
rows = [r for r in json.load(open(sys.argv[1]))['licenses'] if r['name'] == 'android-ndk-sysroot']
assert len(rows) == 1 and rows[0]['license_files'] == ['share/licenses/ndk/android-ndk-sysroot/NOTICE'], rows
assert rows[0]['version'] == 'r30' and len(rows[0]['sha256']) == 64, rows
PY

# every staged wrapper: sh -n and bash --posix -n, ALTDIR on line 2 (within the first 400 bytes, the marker
# customize.sh and phone-test.sh look for), no $MODDIR and no /data/adb
wbad=
for w in "$st"/system/bin/*; do
  sh -n "$w" 2>/dev/null && bash --posix -n "$w" 2>/dev/null || wbad="$wbad syntax:${w##*/}"
  [ "$(sed -n 2p "$w")" = ALTDIR=/system/etc/android-linux-tools ] || wbad="$wbad line2:${w##*/}"
  head -c 400 "$w" | grep -q '^ALTDIR=/system/etc/android-linux-tools$' || wbad="$wbad marker:${w##*/}"
  grep -q -e MODDIR -e /data/adb "$w" && wbad="$wbad datadb:${w##*/}"
done
if [ -z "$wbad" ]; then ok "wrappers: syntax, ALTDIR line 2, no \$MODDIR or /data/adb ($(ls "$st/system/bin" | wc -l) files)"; else bad "wrappers:$wbad"; fi

# the adb wrapper stage.py wrote, under busybox ash (alpine:3.22) in front of a stub adb that prints its HOME:
# with a HOME it cannot write, root gets the root-only /data/local/android-linux-tools (never /data/local/tmp,
# which the shell user controls), other uids get /data/local/tmp, and root falls back to /data/local/tmp with a
# warning when /data/local is read-only
if command -v docker >/dev/null && docker image inspect alpine:3.22 >/dev/null 2>&1; then
  mkdir -p "$h/adb/local"
  cp "$st/system/bin/adb" "$h/adb/adb"
  if grep -q -e MODDIR -e /data/adb "$h/adb/adb"; then bad "adb wrapper references \$MODDIR or /data/adb"; fi
  cat > "$h/adb/run.sh" <<'SH'
mkdir -p /system/bin /system/etc/android-linux-tools/libexec /data/local/tmp && ln -s /bin/sh /system/bin/sh
printf '#!/bin/sh\necho "HOME=$HOME"\n' > /system/etc/android-linux-tools/libexec/adb
chmod 755 /system/etc/android-linux-tools/libexec/adb
cp /w/adb /system/bin/adb && chmod 755 /system/bin/adb && chmod 1777 /data/local/tmp
HOME=/nonexistent /system/bin/adb 2>&1
HOME=/nonexistent su -s /bin/sh nobody -c /system/bin/adb 2>&1
echo "mode $(stat -c %a /data/local/android-linux-tools 2>/dev/null)"
SH
  out=$(timeout 120 docker run --rm --network none -v "$h/adb:/w:ro" alpine:3.22 sh /w/run.sh 2>&1)
  case "$out" in
    "HOME=/data/local/android-linux-tools"$'\n'"HOME=/data/local/tmp"$'\n'"mode 700") ok "adb wrapper: root HOME /data/local/android-linux-tools (0700), other uids /data/local/tmp" ;;
    *) bad "adb wrapper HOME: $(echo "$out" | tr '\n' ' ')" ;;
  esac
  out=$(timeout 120 docker run --rm --network none -v "$h/adb:/w:ro" -v "$h/adb/local:/data/local:ro" alpine:3.22 \
    sh -c 'mkdir -p /system/bin /system/etc/android-linux-tools/libexec && ln -s /bin/sh /system/bin/sh
printf "#!/bin/sh\necho HOME=\$HOME\n" > /system/etc/android-linux-tools/libexec/adb
chmod 755 /system/etc/android-linux-tools/libexec/adb
HOME=/nonexistent sh /w/adb 2>&1' 2>&1)
  case "$out" in
    *"adb: cannot use /data/local/android-linux-tools"*"HOME=/data/local/tmp") ok "adb wrapper: root falls back to /data/local/tmp with a warning when /data/local is read-only" ;;
    *) bad "adb wrapper fallback: $(echo "$out" | tr '\n' ' ')" ;;
  esac

  # TMPDIR of the wrappers (busybox ash as uid 0 and as nobody; stub programs print what they get). Only the opt-in
  # tools (stage.py ROOT_TMPDIR_TOOLS, here mkfs.erofs) give root with TMPDIR unset the root-only
  # /data/local/android-linux-tools/tmp; other wrappers keep /data/local/tmp; a TMPDIR the caller set is kept,
  # except that root-only path for a caller that cannot write it. Under umask 000, whichever creator runs first
  # (adb wrapper or mkfs.erofs wrapper), both directory levels end up 0700. A planted symlink for the tmp level
  # makes root fall back to /data/local/tmp without a message.
  mkdir -p "$h/tw"
  for w in mkfs.erofs jq tmux adb; do cp "$st/system/bin/$w" "$h/tw/$w"; done
  cat > "$h/tw/run.sh" <<'SH'
umask 000
mkdir -p /system/bin /system/etc/android-linux-tools/libexec /data/local/tmp && ln -s /bin/sh /system/bin/sh
chmod 751 /data/local && chmod 1777 /data/local/tmp
for t in mkfs.erofs jq adb; do printf '#!/bin/sh\necho "TMPDIR=$TMPDIR HOME=$HOME"\n' > /system/etc/android-linux-tools/libexec/$t; done
printf '#!/bin/sh\necho "TMUX_TMPDIR=$TMUX_TMPDIR"\n' > /system/etc/android-linux-tools/libexec/tmux
chmod 755 /system/etc/android-linux-tools/libexec/*
for w in mkfs.erofs jq tmux adb; do cp /w/$w /system/bin/$w && chmod 755 /system/bin/$w; done
R=/data/local/android-linux-tools/tmp
m() { echo "modes $(stat -c %a /data/local/android-linux-tools 2>/dev/null || echo none) $(stat -c %a $R 2>/dev/null || echo none)"; }
case "$1" in
  adb-first) env -u TMPDIR HOME=/nonexistent /system/bin/adb; m; env -u TMPDIR /system/bin/mkfs.erofs; m ;;
  listed-first) env -u TMPDIR /system/bin/mkfs.erofs; m; env -u TMPDIR HOME=/nonexistent /system/bin/adb; m ;;
  cases)
    env -u TMPDIR /system/bin/jq
    TMPDIR=/data/local/tmp/other /system/bin/mkfs.erofs
    env -u TMPDIR /system/bin/mkfs.erofs
    su -s /bin/sh nobody -c "TMPDIR=$R /system/bin/mkfs.erofs; TMPDIR=$R /system/bin/jq; unset TMPDIR; /system/bin/mkfs.erofs; TMUX_TMPDIR=$R TMPDIR=$R /system/bin/tmux" ;;
  planted) mkdir -m 700 /data/local/android-linux-tools && ln -s /data/local/tmp $R
    env -u TMPDIR /system/bin/mkfs.erofs 2>&1 ;;
esac
SH
  for c in adb-first listed-first cases planted; do
    out=$(timeout 120 docker run --rm --network none -v "$h/tw:/w:ro" alpine:3.22 sh /w/run.sh "$c" 2>&1)
    case "$c" in
      adb-first) want="TMPDIR=/data/local/tmp HOME=/data/local/android-linux-tools
modes 700 none
TMPDIR=/data/local/android-linux-tools/tmp HOME=/root
modes 700 700" ;;
      listed-first) want="TMPDIR=/data/local/android-linux-tools/tmp HOME=/root
modes 700 700
TMPDIR=/data/local/tmp HOME=/data/local/android-linux-tools
modes 700 700" ;;
      cases) want="TMPDIR=/data/local/tmp HOME=/root
TMPDIR=/data/local/tmp/other HOME=/root
TMPDIR=/data/local/android-linux-tools/tmp HOME=/root
TMPDIR=/data/local/tmp HOME=/
TMPDIR=/data/local/tmp HOME=/
TMPDIR=/data/local/tmp HOME=/
TMUX_TMPDIR=/data/local/tmp" ;;
      planted) want="TMPDIR=/data/local/tmp HOME=/root" ;;
    esac
    if [ "$out" = "$want" ]; then ok "wrapper TMPDIR: $c"; else bad "wrapper TMPDIR $c: $(echo "$out" | tr '\n' '|') want $(echo "$want" | tr '\n' '|')"; fi
  done
else
  bad "adb wrapper: docker or the alpine:3.22 image missing"
fi
rm -rf "$h"
[ "$FAILS" -eq 0 ]
