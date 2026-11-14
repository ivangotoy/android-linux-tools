# Helpers for the shell tests (sourced). ALT_TREE = source tree under test, scratch below $TMPDIR.
set -u
alt_scratch() {
  local d
  d=$(mktemp -d "$TMPDIR/alt-test.XXXXXX") || exit 2
  echo "$d"
}
# alt_bwrap ROOT SRC WORK CMD...: run CMD with SRC at /src (read-only) and WORK at /work, everything else of the
# host read-only (/usr, /etc); nothing outside WORK is writable
alt_bwrap() {
  local root=$1 src=$2 work=$3 l
  shift 3
  mkdir -p "$root/usr" "$root/etc" "$root/src" "$root/work" "$root/dev" "$root/proc" "$root/opt"
  for l in bin sbin lib lib64; do
    if [ -L "/$l" ]; then ln -sfn "$(readlink "/$l")" "$root/$l"; fi
  done
  bwrap --bind "$root" / --ro-bind /usr /usr --ro-bind /etc /etc --ro-bind "$src" /src --bind "$work" /work \
    --dev /dev --proc /proc --clearenv --setenv PATH /usr/bin --setenv TMPDIR /work/build/tmp --setenv JOBS 2 \
    --setenv HOME /work/build/home "$@"
}
FAILS=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }
