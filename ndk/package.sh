#!/usr/bin/env bash
# Stage, check and zip both flavours of the v2 module (inside the builder; called by ndk/build.sh).
set -euo pipefail
. /src/ndk/lib/env.sh
MODID=android-linux-tools
STAGE=/work/stage
DIST=/work/dist
V1=$STAGE/v1root
export SOURCE_DATE_EPOCH=$(sed -n 's/^SOURCE_DATE_EPOCH=//p' /src/config/build.conf)
export PYTHONDONTWRITEBYTECODE=1
umask 022
log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$B/logs/build.log"; }

# v1 Alpine packages, only for tools without an NDK build (none since v2.1), fetched and verified by the
# unchanged v1 fetch.py
rm -rf "$V1"; mkdir -p "$V1"
for x in config alpine.lock.json module scripts phone-test.sh; do ln -s "/src/$x" "$V1/$x"; done
ln -s /work/alpine "$V1/.work"
need_alpine=$(for fl in lite full; do python3 -I /src/ndk/scripts/stage.py "$fl" --needs-alpine; done | sort -u | paste -sd' ' -)
if [ -n "$need_alpine" ]; then
  log "alpine fetch+verify (locked, alpine.lock.json) for: $need_alpine"
  python3 -I /src/scripts/fetch.py "$V1"
else
  log "no Alpine packages needed: every tool is an NDK build"
fi

rm -f "$DIST/$MODID"-*v2.*.zip "$DIST/$MODID"-*v2.*.zip.sha256 "$DIST/MANIFEST-v2.json"
for fl in lite full; do
  log "stage $fl"
  python3 -I /src/ndk/scripts/stage.py "$fl"
  log "host checks $fl"
  python3 -I /src/ndk/scripts/check.py "$fl"
  st="$STAGE/$fl/$MODID"
  version=$(sed -n 's/^version=//p' "$st/module.prop")
  name=$MODID
  [ "$fl" = full ] && name="$MODID-full"
  zipf="$DIST/$name-$version.zip"
  find "$st" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
  (cd "$st" && find . -mindepth 1 \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort | TZ=UTC zip -q -r -y -X -D "$zipf" -@)
  log "zip $fl -> $(basename "$zipf")"
  unzip -tq "$zipf" >/dev/null
  zip -T "$zipf" >/dev/null
  if grep -a -q -e /home/ivan -e /work/build -e /work/out -e /.work/ -e /opt/ndk "$zipf"; then
    echo "host path found in $zipf" >&2
    exit 1
  fi
  if unzip -l "$zipf" | grep -q -e '\.work' -e '__pycache__'; then
    echo "unexpected entries in $zipf" >&2
    exit 1
  fi
done
cp /src/phone-test.sh "$DIST/phone-test.sh"
chmod 0755 "$DIST/phone-test.sh"
python3 -I /src/ndk/scripts/manifest.py
log "package done"
