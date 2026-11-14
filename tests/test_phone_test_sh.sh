# phone-test.sh (real script) as root under busybox ash (alpine:3.22, no network), with simulated device
# directories, a stub alt-list and a tmux wrapper made of stage.py's own wrapper lines in front of a stub tmux:
# the self-check must remove the tmux socket directory it created, also when TMPDIR points elsewhere.
. "$ALT_TESTS/lib.sh"
command -v docker >/dev/null || { echo "tests: missing host tool docker" >&2; exit 2; }
docker image inspect alpine:3.22 >/dev/null 2>&1 || { echo "tests: docker image alpine:3.22 missing" >&2; exit 2; }
h=$(alt_scratch)
mkdir -p "$h/bin"
cp "$ALT_TREE/phone-test.sh" "$h/"
# tmux wrapper: the environment lines stage.py writes into every wrapper and the tmux ones (EXTRA_ENV)
python3 -I - "$ALT_TREE/ndk/scripts/stage.py" > "$h/bin/tmux" <<'PY' || { bad "cannot read wrapper lines from stage.py"; exit 1; }
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
extra = next(ast.literal_eval(n.value) for n in ast.walk(tree)
             if isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') == 'EXTRA_ENV')
tmpdir = next(n.value for n in ast.walk(tree) if isinstance(n, ast.Constant) and isinstance(n.value, str)
              and n.value.startswith('[ -n "$TMPDIR" ] ||'))
print('\n'.join(['#!/bin/sh', 'ALTDIR=/system/etc/android-linux-tools', tmpdir] + extra['tmux'] +
                ['exec /usr/local/bin/tmux.stub "$@"']))
PY
cat > "$h/bin/tmux.stub" <<'SH'
#!/bin/sh
# tmux stand-in: -L NAME new-session creates the socket in $TMUX_TMPDIR/tmux-UID like tmux, kill-server removes it
[ "$1" = -V ] && { echo "tmux 3.8"; exit 0; }
[ "$1" = -L ] || exit 1
d="$TMUX_TMPDIR/tmux-$(id -u)"; s="$d/$2"
case "$3" in
  new-session) mkdir -p -m 700 "$d" && : > "$s" ;;
  ls) [ -e "$s" ] && echo "alttoolstest: 1 windows" ;;
  kill-server) rm -f "$s" ;;
esac
SH
printf '#!/bin/sh\n[ "$1" = -m ] && echo "tmux tmux -"\nexit 0\n' > "$h/bin/alt-list"
cat > "$h/inside.sh" <<'SH'
mkdir -p /data/adb/modules/android-linux-tools /data/local/tmp/apptmp /system/bin
echo version=v0.0-r1 > /data/adb/modules/android-linux-tools/module.prop
ln -s /bin/sh /system/bin/sh
cp /w/bin/* /usr/local/bin/ && chmod 755 /usr/local/bin/*
TMPDIR=/data/local/tmp/apptmp sh /w/phone-test.sh > /phone-test.out 2>&1
grep -E '^(PASS|FAIL) tmux-session' /phone-test.out
for d in /data/local/tmp/apptmp/tmux-0 /data/local/tmp/tmux-0; do [ -e "$d" ] && echo "LEFT $d"; done
echo end
SH
out=$(docker run --rm --network none -v "$h:/w:ro" alpine:3.22 sh /w/inside.sh 2>&1)
case "$out" in
  *"PASS tmux-session"*) ok "phone-test tmux-session ran with the stub" ;;
  *) bad "phone-test tmux-session did not run: $out" ;;
esac
case "$out" in
  *LEFT*) bad "tmux socket directory left behind: $(echo "$out" | grep LEFT | tr '\n' ' ')" ;;
  *end*) ok "phone-test removed the tmux socket directory in TMPDIR" ;;
  *) bad "no result: $out" ;;
esac
rm -rf "$h"
[ "$FAILS" -eq 0 ]
