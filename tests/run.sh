#!/usr/bin/env bash
# Regression tests of the build, packaging and release scripts (host only; nothing here ships in the module).
#   tests/run.sh [TREE]   run every tests/test_* against the source tree TREE (default: this checkout)
# Needs bwrap, python3, curl, zip and unzip. Scratch goes to $TMPDIR (never /tmp).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tree=$(cd "${1:-$here/..}" && pwd) || exit 2
for t in bwrap python3 curl zip unzip; do
  command -v "$t" >/dev/null || { echo "tests: missing host tool $t" >&2; exit 2; }
done
case "${TMPDIR:-}" in
  ''|/tmp|/tmp/*) echo "tests: set TMPDIR to a disk-backed directory (not /tmp)" >&2; exit 2 ;;
esac
export ALT_TREE=$tree ALT_TESTS=$here
fail=0
for t in "$here"/test_*; do
  echo "== $(basename "$t") (tree $tree)"
  case "$t" in
    *.py) python3 -I "$t" ;;
    *.sh) bash "$t" ;;
  esac
  rc=$?
  [ "$rc" -eq 0 ] || { echo "FAILED $(basename "$t") rc=$rc"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "tests: all passed" || echo "tests: FAILURES"
exit "$fail"
