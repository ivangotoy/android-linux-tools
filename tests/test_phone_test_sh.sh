# phone-test.sh (real script) as root under busybox ash (alpine:3.22, no network), with simulated device
# directories, a stub alt-list and a tmux wrapper made of stage.py's own wrapper lines in front of a stub tmux:
# the self-check must remove the tmux socket directory it created, also when TMPDIR points elsewhere, and must not
# write through links a shell user planted in /data/local/tmp.
. "$ALT_TESTS/lib.sh"
command -v docker >/dev/null || { echo "tests: missing host tool docker" >&2; exit 2; }
docker image inspect alpine:3.22 >/dev/null 2>&1 || { echo "tests: docker image alpine:3.22 missing" >&2; exit 2; }
h=$(alt_scratch)
# drun NAME ARGS...: docker run bounded by timeout; the named container is removed whatever happens
drun() {
  local name=alt-test-$$-$1; shift
  timeout 120 docker run --rm --name "$name" "$@"
  local rc=$?
  docker rm -f "$name" >/dev/null 2>&1
  return $rc
}
mkdir -p "$h/bin"
cp "$ALT_TREE/phone-test.sh" "$h/"
# tmux wrapper: the environment lines stage.py writes into every wrapper and the tmux ones (EXTRA_ENV)
python3 -I - "$ALT_TREE/ndk/scripts/stage.py" > "$h/bin/tmux" <<'PY' || { bad "cannot read wrapper lines from stage.py"; exit 1; }
import ast, sys
# the wrapper-line definitions of stage.py (module-level assignments and helper functions before the staging code),
# run on their own; TMPDIR_LINES (the TMPDIR lines of a wrapper) did not exist before the root-only TMPDIR guard
tree = ast.parse(open(sys.argv[1]).read())
names = {'ROOTDIR', 'ROOTTMP', 'TMPDIR_GUARD', 'TMPDIR_LINES', 'EXTRA_ENV'}
body = [n for n in tree.body if (isinstance(n, ast.Assign) and getattr(n.targets[0], 'id', '') in names)
        or (isinstance(n, ast.FunctionDef) and n.name == 'rootdir_ok')]
ns = {'MODID': 'android-linux-tools', 'ALTDIR': '/system/etc/android-linux-tools'}
exec(compile(ast.Module(body=body, type_ignores=[]), sys.argv[1], 'exec'), ns)
tmpdir = ns.get('TMPDIR_LINES') or [next(n.value for n in ast.walk(tree) if isinstance(n, ast.Constant)
                                         and isinstance(n.value, str) and n.value.startswith('[ -n "$TMPDIR" ] ||'))]
print('\n'.join(['#!/bin/sh', 'ALTDIR=/system/etc/android-linux-tools'] + tmpdir + ns['EXTRA_ENV']['tmux'] +
                ['exec /usr/local/bin/tmux.stub "$@"']))
PY
cat > "$h/bin/tmux.stub" <<'SH'
#!/bin/sh
# tmux stand-in: -L NAME new-session creates the socket in $TMUX_TMPDIR/tmux-UID like tmux, kill-server removes it
[ "$1" = -V ] && { echo "tmux 3.8"; exit 0; }
[ "$1" = -L ] || exit 1
d="$TMUX_TMPDIR/tmux-$(id -u)"; s="$d/$2"
# like tmux (tmux.c make_label): create the socket directory, refuse a symlink or a directory of another uid
mkdir -p -m 700 "$d"; { [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ]; } || { echo "directory $d has unsafe permissions" >&2; exit 1; }
case "$3" in
  new-session) : > "$s" ;;
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
out=$(drun inside --network none -v "$h:/w:ro" alpine:3.22 sh /w/inside.sh 2>&1)
case "$out" in
  *"PASS tmux-session"*) ok "phone-test tmux-session ran with the stub" ;;
  *) bad "phone-test tmux-session did not run: $out" ;;
esac
case "$out" in
  *LEFT*) bad "tmux socket directory left behind: $(echo "$out" | grep LEFT | tr '\n' ' ')" ;;
  *end*) ok "phone-test removed the tmux socket directory in TMPDIR" ;;
  *) bad "no result: $out" ;;
esac

# /data/local/tmp belongs to the shell user: links planted there for the pids the root run may get must not make
# root write through them; the same for the non-root run (--nonroot) and its TMPDIR. The links are planted for the
# pid of the shell that then execs phone-test.sh, so the script's $$ is exactly the planted pid.
cat > "$h/plant.sh" <<'SH'
s=/system/etc/android-linux-tools/share/android-linux-tools
mkdir -p /data/adb/modules/android-linux-tools /data/local/tmp /system/bin /victim "$s"
echo version=v0.0-r1 > /data/adb/modules/android-linux-tools/module.prop
printf '{\n "version": "v0.0-r1"\n}\n' > "$s/MANIFEST.json"
ln -s /bin/sh /system/bin/sh
cp /w/bin/* /usr/local/bin/ && chmod 755 /usr/local/bin/*
sh -c 'ln -s /victim "/data/local/tmp/alttoolstest.$$"
ln -s /victim/kconfig "/data/local/tmp/.alt-phone-test-kconfig.$$"
ln -s /victim "/data/local/tmp/alttoolstest-nr.$$"
exec sh /w/phone-test.sh "$@" > /phone-test.out 2>&1' sh "$@"
grep -E '^(TOTAL|NONROOT) ' /phone-test.out
echo "left:$(find /data/local/tmp /data/local/android-linux-tools/tmp -maxdepth 1 -name 'alttoolstest*' -type d 2>/dev/null | tr '\n' ' ')"
echo "victim:$(ls -A /victim | tr '\n' ' ')"
SH
for mode in root --nonroot; do
  arg=; [ "$mode" = root ] || arg=$mode
  out=$(drun "plant${arg}" --network none -v "$h:/w:ro" alpine:3.22 sh /w/plant.sh $arg 2>&1)
  case "$out" in
    *" pass="*"left:"$'\n'"victim:") ok "phone-test ($mode) wrote nothing through links planted in /data/local/tmp" ;;
    *"victim:"?*) bad "phone-test ($mode) wrote through planted links: $(echo "$out" | grep victim)" ;;
    *) bad "planted-link run ($mode) gave no result or left a work dir: $out" ;;
  esac
done

# TERM in the middle of the root run, also after the reader of its output has gone, and a closed output alone
# (SIGPIPE on the next line): the self-check must clean up (work directory, tmux test socket) and exit 128+signal.
# The tmux stub signals "ready" through a fifo from inside `tmux ls` (after the socket exists) and then blocks on a
# second fifo; the harness closes the output and/or sends TERM, then releases the stub. No sleeps, no polling;
# every docker run of this case is bounded by timeout and its container removed by name.
mkdir -p "$h/sig"
cat > "$h/sig/tmux.stub" <<'SH'
#!/bin/sh
[ "$1" = -V ] && { echo "tmux 3.8"; exit 0; }
[ "$1" = -L ] || exit 1
d="$TMUX_TMPDIR/tmux-$(id -u)"; s="$d/$2"
# like tmux (tmux.c make_label): create the socket directory, refuse a symlink or a directory of another uid
mkdir -p -m 700 "$d"; { [ -d "$d" ] && [ ! -L "$d" ] && [ -O "$d" ]; } || { echo "directory $d has unsafe permissions" >&2; exit 1; }
case "$3" in
  new-session) : > "$s" ;;
  ls) echo ready > /ready; read -r x < /block; [ -e "$s" ] && echo "alttoolstest: 1 windows" ;;
  kill-server) rm -f "$s" ;;
esac
SH
cat > "$h/sig/run.sh" <<'SH'
mkdir -p /data/adb/modules/android-linux-tools /data/local/tmp /system/bin
echo version=v0.0-r1 > /data/adb/modules/android-linux-tools/module.prop
ln -s /bin/sh /system/bin/sh
cp /w/bin/* /usr/local/bin/ && cp /w/sig/tmux.stub /usr/local/bin/tmux.stub && chmod 755 /usr/local/bin/*
mkfifo /ready /block /out
cat /out > /phone-test.out &
reader=$!
sh /w/phone-test.sh > /out 2>&1 &
pid=$!
read -r x < /ready
case "$1" in term-closed|closed) kill "$reader"; wait "$reader" ;; esac
case "$1" in term|term-closed) kill -TERM "$pid" ;; esac
echo go > /block
wait "$pid"
echo "rc=$?"
echo "left:$(find /data/local/tmp /data/local/android-linux-tools/tmp -mindepth 1 -maxdepth 1 2>/dev/null | tr '\n' ' ')"
SH
for c in term:143 term-closed:143 closed:141; do
  name=alt-test-sig-$$-${c%:*}
  out=$(timeout 120 docker run --rm --name "$name" --init --network none -v "$h:/w:ro" alpine:3.22 sh /w/sig/run.sh "${c%:*}" 2>&1)
  docker rm -f "$name" >/dev/null 2>&1
  case "$out" in
    *"rc=${c#*:}"$'\n'"left:") ok "phone-test ${c%:*}: exit ${c#*:}, work directory and tmux socket removed" ;;
    *) bad "phone-test ${c%:*}: $(echo "$out" | tr '\n' ' ')" ;;
  esac
done

# the tmux cleanup of the root run must not act through a tmux-0 it does not own: a symlink to a root-owned victim
# directory (caught by ! -L) and a real directory of another uid (caught by -O), each holding a file named
# alttoolstest, keep that file
cat > "$h/tmuxdir.sh" <<'SH'
mkdir -p /data/adb/modules/android-linux-tools /data/local/tmp /system/bin /victim
echo version=v0.0-r1 > /data/adb/modules/android-linux-tools/module.prop
ln -s /bin/sh /system/bin/sh
cp /w/bin/* /usr/local/bin/ && chmod 755 /usr/local/bin/*
echo keep > /victim/alttoolstest
case "$1" in
  symlink) ln -s /victim /data/local/tmp/tmux-0; f=/victim/alttoolstest ;;
  foreign) mkdir -m 700 /data/local/tmp/tmux-0; echo keep > /data/local/tmp/tmux-0/alttoolstest
           chown -R 2000:2000 /data/local/tmp/tmux-0; f=/data/local/tmp/tmux-0/alttoolstest ;;
esac
sh /w/phone-test.sh > /phone-test.out 2>&1
grep -q '^TOTAL ' /phone-test.out && echo "ran"
[ -f "$f" ] && echo "kept $f" || echo "removed $f"
SH
for c in symlink foreign; do
  out=$(drun "tmuxdir-$c" --network none -v "$h:/w:ro" alpine:3.22 sh /w/tmuxdir.sh "$c" 2>&1)
  case "$out" in
    "ran"$'\n'"kept "*) ok "phone-test tmux cleanup leaves a $c tmux-0 alone" ;;
    *) bad "phone-test tmux cleanup ($c tmux-0): $(echo "$out" | tr '\n' ' ')" ;;
  esac
done

# the root run's work directory is under the root-only /data/local/android-linux-tools/tmp, not in /data/local/tmp
# (where the shell user could rename it). Inspected mid-run while the stub tmux blocks in `tmux ls` (fifos, no
# sleeps): the work directory, nothing named alttoolstest* in /data/local/tmp, both levels 0700 under umask 000
# (phone-test.sh makes them first), and uid 2000 can neither list nor rename in there. A planted symlink for the
# tmp level makes the run fall back to /data/local/tmp with a note. The non-root run that inherited the root-only
# TMPDIR (not writable for it) works in /data/local/tmp.
cat > "$h/sig/where.sh" <<'SH'
umask 000
mkdir -p /data/adb/modules/android-linux-tools /data/local/tmp /system/bin && chmod 751 /data/local && chmod 1771 /data/local/tmp
echo version=v0.0-r1 > /data/adb/modules/android-linux-tools/module.prop
ln -s /bin/sh /system/bin/sh
cp /w/bin/* /usr/local/bin/ && cp /w/sig/tmux.stub /usr/local/bin/tmux.stub && chmod 755 /usr/local/bin/*
R=/data/local/android-linux-tools/tmp
[ "$1" = planted ] && mkdir -m 700 /data/local/android-linux-tools && ln -s /data/local/tmp $R
mkfifo /ready /block
env -u TMPDIR sh /w/phone-test.sh > /phone-test.out 2>&1 &
pid=$!
read -r x < /ready
for d in $R/alttoolstest.* /data/local/tmp/alttoolstest.*; do [ -d "$d" ] && echo "work $(readlink -f "$d" | sed 's/\.[^.]*$//')"; done | sort -u
echo "modes $(stat -c %a /data/local/android-linux-tools) $(stat -c %a $R)"
su -s /bin/sh nobody -c "ls $R >/dev/null 2>&1 && echo 'nobody can list'; mv $R/alttoolstest.* /data/local/tmp/x 2>/dev/null && echo 'nobody renamed'"
echo go > /block
wait "$pid"
grep '^note: cannot use' /phone-test.out
echo "left:$(find /data/local/tmp $R/ -mindepth 1 -maxdepth 1 -name 'alttoolstest*' 2>/dev/null | tr '\n' ' ')"
SH
for c in normal planted; do
  out=$(drun "where-$c" --init --network none -v "$h:/w:ro" alpine:3.22 sh /w/sig/where.sh "$c" 2>&1)
  case "$c" in
    normal) want="work /data/local/android-linux-tools/tmp/alttoolstest
modes 700 700
left:" ;;
    planted) want="work /data/local/tmp/alttoolstest
modes 700 777
note: cannot use /data/local/android-linux-tools/tmp for the work directory, using /data/local/tmp
left:" ;;
  esac
  if [ "$out" = "$want" ]; then ok "phone-test root work directory ($c)"; else bad "phone-test root work directory ($c): $(echo "$out" | tr '\n' '|')"; fi
done
cat > "$h/nrinh.sh" <<'SH'
s=/system/etc/android-linux-tools/share/android-linux-tools
mkdir -p /data/adb/modules/android-linux-tools /data/local/android-linux-tools/tmp /data/local/tmp /system/bin "$s"
chmod 751 /data/local && chmod 700 /data/local/android-linux-tools /data/local/android-linux-tools/tmp && chmod 1777 /data/local/tmp
printf '{\n "version": "v0.0-r1"\n}\n' > "$s/MANIFEST.json"
ln -s /bin/sh /system/bin/sh
cp /w/bin/* /usr/local/bin/ && chmod 755 /usr/local/bin/*
cp /w/phone-test.sh /pt.sh && chmod 644 /pt.sh
su -s /bin/sh nobody -c 'TMPDIR=/data/local/android-linux-tools/tmp sh /pt.sh --nonroot' > /nr.out 2>&1
grep -E 'wrappers.*cannot write|^NONROOT ' /nr.out | sed 's/pass=.*//'
grep -q '^NONROOT ' /nr.out || tail -n 5 /nr.out
SH
out=$(drun nrinh --network none -v "$h:/w:ro" alpine:3.22 sh /w/nrinh.sh 2>&1)
case "$out" in
  "NONROOT ") ok "phone-test --nonroot with an inherited root-only TMPDIR works in /data/local/tmp" ;;
  *) bad "phone-test --nonroot inherited TMPDIR: $(echo "$out" | tr '\n' '|')" ;;
esac
rm -rf "$h"
[ "$FAILS" -eq 0 ]
