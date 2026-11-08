#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK="$ROOT/.work"
DIST="$ROOT/dist"
MODID=android-linux-tools
UPDATE_LOCK=0
CLEAN=0

usage() {
  echo "usage: ./build.sh [--update-lock] [--clean]"
  echo "  --update-lock  re-resolve packages from the Alpine branch in config/build.conf and rewrite alpine.lock.json"
  echo "  --clean        delete cached downloads, unpacked packages, staging and dist before building"
}
for a in "$@"; do
  case "$a" in
    --update-lock) UPDATE_LOCK=1 ;;
    --clean) CLEAN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

for t in python3 patchelf readelf file zip unzip sha256sum find sort touch grep; do
  command -v "$t" >/dev/null || { echo "missing host tool: $t" >&2; exit 1; }
done

mkdir -p "$WORK/tmp"
export TMPDIR="$WORK/tmp"
export LC_ALL=C TZ=UTC
export PYTHONDONTWRITEBYTECODE=1
umask 022
cd "$ROOT"

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$WORK/build.log"; }

SOURCE_DATE_EPOCH=$(sed -n 's/^SOURCE_DATE_EPOCH=//p' config/build.conf)
[[ "$SOURCE_DATE_EPOCH" =~ ^[0-9]+$ ]] || { echo "SOURCE_DATE_EPOCH missing in config/build.conf" >&2; exit 1; }
export SOURCE_DATE_EPOCH

if [ "$CLEAN" = 1 ]; then
  log "clean: removing .work/{index,dl,unpack,stage,json} and dist"
  rm -rf "$WORK/index" "$WORK/dl" "$WORK/unpack" "$WORK/stage" "$WORK/json" "$DIST"
fi
mkdir -p "$DIST"

fetch_args=()
[ "$UPDATE_LOCK" = 1 ] && fetch_args+=(--update-lock)
log "fetch+verify+unpack ${fetch_args[*]:-(locked if alpine.lock.json exists)}"
python3 -I scripts/fetch.py "$ROOT" "${fetch_args[@]}"

rm -f "$DIST/$MODID"-*.zip "$DIST/$MODID"-*.zip.sha256 "$DIST/MANIFEST.json"
for fl in lite full; do
  log "stage $fl"
  python3 -I scripts/stage.py "$ROOT" "$fl"
  log "host checks $fl"
  python3 -I scripts/check.py "$ROOT" "$fl"
  st="$WORK/stage/$fl/$MODID"
  version=$(sed -n 's/^version=//p' "$st/module.prop")
  name=$MODID
  [ "$fl" = full ] && name="$MODID-full"
  zipf="$DIST/$name-$version.zip"
  find "$st" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
  (cd "$st" && find . -mindepth 1 \( -type f -o -type l \) | sed 's|^\./||' | sort | zip -q -r -y -X -D "$zipf" -@)
  log "zip $fl -> $(basename "$zipf")"
  unzip -tq "$zipf" >/dev/null
  zip -T "$zipf" >/dev/null
  if grep -a -q -e "$ROOT" -e "$HOME" -e "/.work/" "$zipf"; then
    echo "host path found in $zipf" >&2
    exit 1
  fi
  if unzip -l "$zipf" | grep -q -e '\.work' -e '__pycache__'; then
    echo "unexpected entries in $zipf" >&2
    exit 1
  fi
done
cp phone-test.sh "$DIST/phone-test.sh"
chmod 0755 "$DIST/phone-test.sh"
python3 -I scripts/manifest.py "$ROOT"
log "done"
