#!/usr/bin/env bash
# Stage, check and zip the module (inside the builder; called by ndk/build.sh).
set -euo pipefail
. /src/ndk/lib/env.sh
MODID=android-linux-tools
STAGE=/work/stage
DIST=/work/dist
export SOURCE_DATE_EPOCH=$(sed -n 's/^SOURCE_DATE_EPOCH=//p' /src/ndk/build.conf)
export PYTHONDONTWRITEBYTECODE=1
umask 022
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$B/logs/build.log"; }

# also removes ZIPs of the former full flavour (android-linux-tools-full-v2.*), so dist/ has one module ZIP
rm -f "$DIST/$MODID"-*v2.*.zip "$DIST/$MODID"-*v2.*.zip.sha256 "$DIST/MANIFEST-v2.json"
log "stage"
python3 -I /src/ndk/scripts/stage.py
log "host checks"
python3 -I /src/ndk/scripts/check.py
st="$STAGE/module/$MODID"
version=$(sed -n 's/^version=//p' "$st/module.prop")
zipf="$DIST/$MODID-$version.zip"
find "$st" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
(cd "$st" && find . -mindepth 1 \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort | TZ=UTC zip -q -r -y -X -D "$zipf" -@)
log "zip -> $(basename "$zipf")"
unzip -tq "$zipf" >/dev/null
zip -T "$zipf" >/dev/null
# build-host paths in any file of the module: scan the staged tree the ZIP was made from (in the ZIP itself
# almost every entry is deflated, so a grep over it sees little more than the file names)
if grep -r -a -l ${ALT_HOST_HOME:+-e "$ALT_HOST_HOME"} -e /work/build -e /work/out -e /.work/ -e /opt/ndk "$st" >&2; then
  echo "host path found in the files above (module $zipf)" >&2
  exit 1
fi
# no grep -q: it stops reading at the first match, unzip then dies of SIGPIPE and under pipefail the
# pipeline (and so this check) fails exactly when there is a match
if unzip -l "$zipf" | grep -e '\.work' -e '__pycache__' >&2; then
  echo "unexpected entries in $zipf" >&2
  exit 1
fi
log "layout test (install simulation, non-root view of /system/etc/$MODID)"
rm -rf "$B/tmp/layout"
python3 -I /src/ndk/scripts/layout_test.py "$zipf" "$B/tmp/layout" | tee "$STAGE/layout_test.txt"
rm -rf "$B/tmp/layout"
cp /src/phone-test.sh "$DIST/phone-test.sh"
chmod 0755 "$DIST/phone-test.sh"
python3 -I /src/ndk/scripts/manifest.py
log "package done"
