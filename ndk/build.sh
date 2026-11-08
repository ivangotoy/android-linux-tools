#!/usr/bin/env bash
# android-linux-tools v2 builder entry point (runs inside the ndk/Dockerfile image via ./build-ndk.sh).
#   bash /src/ndk/build.sh            build every recipe in ndk/recipes.list, then stage, check and zip the module
#   bash /src/ndk/build.sh tool...    build only these recipes (plus dependencies)
set -euo pipefail
. /src/ndk/lib/env.sh
mkdir -p "$B/src" "$B/stamps" "$B/meta" "$B/logs" "$B/tmp" "$B/home" "$B/pkg" "$B/sysroot" "$OUT/bin" "$OUT/meta" "$DL"
python3 -I /src/ndk/lib/api-site.py "$SYSROOT/usr/include" "$API" "$B/api-site.sh" >/dev/null
export SOURCE_DATE_EPOCH=$(sed -n 's/^SOURCE_DATE_EPOCH=//p' /src/config/build.conf)

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$B/logs/build.log"; }

recipe_file() { echo "/src/ndk/recipes/$1.sh"; }

# load_recipe NAME: reset recipe variables and source the recipe
load_recipe() {
  unset -f build 2>/dev/null || true
  NAME=$1; VERSION=; URL=; SHA256=; DEPS=; LICENSE=; SRCDIR=; CHECKSUM_SOURCE=; PATCHES_FROM=$1; TARBALL=; LINKAGE=; EXTRA_SRCS=()
  . "$(recipe_file "$1")"
  : "${VERSION:?}" "${URL:?}" "${SHA256:?}"
  TARBALL=${TARBALL:-$(basename "$URL")}
  SRCDIR=${SRCDIR:-$NAME-$VERSION}
}

# recipe_hash NAME: identity of a recipe = recipe file + patches + env + dependency hashes
recipe_hash() {
  local n=$1 d h
  h=$( { cat "$(recipe_file "$n")" /src/ndk/lib/env.sh /src/ndk/lib/api-site.py /src/ndk/build.sh;
         [ -d "/src/ndk/patches/$n" ] && find "/src/ndk/patches/$n" -type f | sort | xargs cat;
         for d in $(deps_of "$n"); do recipe_hash "$d"; done; } | sha256sum | cut -c1-16)
  echo "$h"
}
deps_of() ( load_recipe "$1" >/dev/null; echo "$DEPS" )
# all_deps NAME: transitive dependencies, each once, dependencies first
all_deps() {
  local d
  for d in $(deps_of "$1"); do all_deps "$d"; echo "$d"; done | awk '!seen[$0]++'
}
# mk_sysroot NAME: private prefix with exactly the declared (transitive) dependencies, so a recipe can
# never pick up an optional library just because another recipe happened to be built earlier
mk_sysroot() {
  local r="$B/sysroot/$1" d
  rm -rf "$r"; mkdir -p "$r/include" "$r/lib/pkgconfig"
  for d in $(all_deps "$1"); do
    [ -d "$B/pkg/$d" ] && cp -a "$B/pkg/$d/." "$r/"
  done
  for d in "$r"/lib/pkgconfig/*.pc "$r"/share/pkgconfig/*.pc; do
    [ -f "$d" ] && [ ! -L "$d" ] && sed -i "s|^prefix=.*|prefix=$r|" "$d"
  done
  return 0
}

fetch() {
  local f="$DL/$TARBALL"
  if [ ! -f "$f" ] || ! echo "$SHA256  $f" | sha256sum -c --quiet - 2>/dev/null; then
    log "fetch $NAME $URL"
    curl -fsSL --retry 5 -o "$f.part" "$URL"
    mv "$f.part" "$f"
  fi
  echo "$SHA256  $f" | sha256sum -c --quiet - || { log "SHA256 MISMATCH $NAME $f"; exit 1; }
  # EXTRA_SRCS: additional upstream files ("URL SHA256" per entry), e.g. official patch series
  local x u h
  for x in "${EXTRA_SRCS[@]}"; do
    u=${x% *}; h=${x##* }; f="$DL/$(basename "$u")"
    if [ ! -f "$f" ] || ! echo "$h  $f" | sha256sum -c --quiet - 2>/dev/null; then
      log "fetch $NAME $u"
      curl -fsSL --retry 5 -o "$f.part" "$u"
      mv "$f.part" "$f"
    fi
    echo "$h  $f" | sha256sum -c --quiet - || { log "SHA256 MISMATCH $NAME $f"; exit 1; }
  done
}

extract() {
  local f="$DL/$TARBALL"
  rm -rf "$B/src/$SRCDIR"
  case "$f" in
    *.tar.*|*.tgz) tar -xf "$f" -C "$B/src" --no-same-owner ;;
    *.zip) unzip -q "$f" -d "$B/src" ;;
    *) mkdir -p "$B/src/$SRCDIR"; cp "$f" "$B/src/$SRCDIR/" ;;
  esac
  local p
  for p in $(ls "/src/ndk/patches/$PATCHES_FROM"/*.patch 2>/dev/null | sort); do
    log "patch $NAME $(basename "$p")"
    patch -d "$B/src/$SRCDIR" -p1 --no-backup-if-mismatch -s < "$p"
  done
}

declare -A DONE=()
build_one() {
  local n=$1 d
  [ -n "${DONE[$n]:-}" ] && return 0
  for d in $(deps_of "$n"); do build_one "$d"; done
  local h; h=$(recipe_hash "$n")
  if [ -f "$B/stamps/$n.$h" ]; then
    DONE[$n]=1; return 0
  fi
  (
    load_recipe "$n"
    log "build $n $VERSION ($h)"
    fetch
    extract
    rm -f "$B/meta/$n.bins"
    mk_sysroot "$n"
    rm -rf "$B/pkg/$n"
    DEPROOT="$B/sysroot/$n" PKGDIR="$B/pkg/$n" \
    bash -eo pipefail -c '. /src/ndk/lib/env.sh; NAME=$1; . "/src/ndk/recipes/$1.sh"; set_linkage; cd "$2"; set -x; build' \
      build "$n" "$B/src/$SRCDIR" > "$B/logs/$n.log" 2>&1 || { log "FAILED $n (see .work/ndk/build/logs/$n.log)"; tail -n 40 "$B/logs/$n.log"; exit 1; }
    lic="$OUT/licenses/$n"
    rm -rf "$lic"; mkdir -p "$lic"
    for f in $(cd "$B/src/$SRCDIR" && ls -d COPYING* COPYRIGHT* LICENSE* LICENCE* License NOTICE* README.md-license doc/COPYING* docs/COPYING* 2>/dev/null); do
      [ -f "$B/src/$SRCDIR/$f" ] && cp "$B/src/$SRCDIR/$f" "$lic/"
    done
    [ -d "/src/ndk/patches/$PATCHES_FROM" ] && cp /src/ndk/patches/"$PATCHES_FROM"/*.patch "$lic/" 2>/dev/null || true
    patches=$(ls "/src/ndk/patches/$PATCHES_FROM"/*.patch 2>/dev/null | xargs -r -n1 basename | sort | paste -sd, -)
    bins=$(cat "$B/meta/$n.bins" 2>/dev/null | sort -u | paste -sd, - || true)
    python3 -I - "$OUT/meta/$n.json" <<PY
import json, sys
json.dump({"recipe": "$n", "version": "$VERSION", "url": "$URL", "sha256": "$SHA256",
           "checksum_source": """$CHECKSUM_SOURCE""", "license": "$LICENSE", "deps": "$DEPS".split(),
           "patches": [p for p in "$patches".split(",") if p], "bins": [b for b in "$bins".split(",") if b],
           "recipe_hash": "$h", "linkage": "${LINKAGE:-static}"}, open(sys.argv[1], "w"), indent=1, sort_keys=True)
PY
  ) || exit 1
  rm -f "$B/stamps/$n".*
  touch "$B/stamps/$n.$h"
  DONE[$n]=1
}

if [ $# -gt 0 ]; then
  for t in "$@"; do build_one "$t"; done
  log "done (recipes only: $*)"
  exit 0
fi

FAILED=()
for t in $(grep -v '^#' /src/ndk/recipes.list); do
  if ! ( build_one "$t" ); then FAILED+=("$t"); fi
done
printf '%s\n' "${FAILED[@]}" > "$OUT/failed.txt"
if [ ${#FAILED[@]} -ne 0 ]; then
  # A failed recipe must not silently drop a tool (or let it fall back to Alpine) in the ZIP.
  log "recipes failed: ${FAILED[*]}; not packaging"
  exit 1
fi
log "package"
bash /src/ndk/package.sh
log "done"
