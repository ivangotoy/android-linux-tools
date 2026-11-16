# ndk/module/uninstall.sh (real script) as root under busybox ash (alpine:3.22, no network), inside the container
# only (no host /data): it removes /data/local/android-linux-tools when that is a real directory owned by root, and
# leaves a symlink there (and its target), a directory of another uid, a missing directory and every other path.
. "$ALT_TESTS/lib.sh"
command -v docker >/dev/null || { echo "tests: missing host tool docker" >&2; exit 2; }
docker image inspect alpine:3.22 >/dev/null 2>&1 || { echo "tests: docker image alpine:3.22 missing" >&2; exit 2; }
h=$(alt_scratch)
cp "$ALT_TREE/ndk/module/uninstall.sh" "$h/"
cat > "$h/run.sh" <<'SH'
R=/data/local/android-linux-tools
mkdir -p /data/local/tmp /data/local/android-linux-tools2 /victim && echo keep > /victim/f && echo keep > /data/local/android-linux-tools2/f
case "$1" in
  real) mkdir -p $R/.android $R/tmp && echo key > $R/.android/adbkey && echo tmp > $R/tmp/f ;;
  symlink) ln -s /victim $R ;;
  foreign) mkdir $R && echo f > $R/f && chown -R 2000:2000 $R ;;
  missing) ;;
esac
sh /w/uninstall.sh
echo "rc=$?"
[ -e $R ] || [ -L $R ] && echo "R present" || echo "R gone"
[ -f /victim/f ] && [ -f /data/local/android-linux-tools2/f ] && [ -d /data/local/tmp ] && echo "others kept"
SH
for c in real:gone symlink:present foreign:present missing:gone; do
  out=$(timeout 120 docker run --rm --network none -v "$h:/w:ro" alpine:3.22 sh /w/run.sh "${c%:*}" 2>&1)
  want="rc=0
R ${c#*:}
others kept"
  if [ "$out" = "$want" ]; then ok "uninstall.sh (${c%:*} /data/local/android-linux-tools): ${c#*:}, nothing else touched"; else bad "uninstall.sh ${c%:*}: $(echo "$out" | tr '\n' '|')"; fi
done
rm -rf "$h"
[ "$FAILS" -eq 0 ]
