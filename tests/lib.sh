# Helpers for the shell tests (sourced). ALT_TREE = source tree under test, scratch below $TMPDIR.
set -u
ALT_TOOLS="bash sh cat cp mv rm ln mkdir touch chmod ls basename dirname date tee sed grep awk cut sort uniq paste
  xargs find head tail tr wc sha256sum install tar gzip curl patch unzip zip python3 env true false sleep"
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
  # PATH: only the tools build.sh and package.sh use, as symlinks to the host's programs
  mkdir -p "$root/alt-path"
  for l in $ALT_TOOLS; do
    ln -sfn "$(command -v "$l")" "$root/alt-path/$l" || { echo "tests: missing host tool $l" >&2; exit 2; }
  done
  bwrap --bind "$root" / --ro-bind /usr /usr --ro-bind /etc /etc --ro-bind "$src" /src --bind "$work" /work \
    --dev /dev --proc /proc --clearenv --setenv PATH /alt-path --setenv TMPDIR /work/build/tmp --setenv JOBS 2 \
    --setenv HOME /work/build/home "$@"
}
FAILS=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; FAILS=$((FAILS + 1)); }
