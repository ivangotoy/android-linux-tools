#!/usr/bin/env bash
# android-linux-tools v2 builder entry point (runs inside the ndk/Dockerfile image via ./build-ndk.sh).
#   bash /src/ndk/build.sh            build every recipe in ndk/recipes.list, then stage, check and zip the module
#   bash /src/ndk/build.sh tool...    build only these recipes (plus dependencies)
set -euo pipefail
. /src/ndk/lib/env.sh
mkdir -p "$B/src" "$B/stamps" "$B/meta" "$B/logs" "$B/tmp" "$B/home" "$B/pkg" "$B/sysroot" "$OUT/bin" "$OUT/meta" "$DL"
python3 -I /src/ndk/lib/api-site.py "$SYSROOT/usr/include" "$API" "$B/api-site.sh" >/dev/null
export SOURCE_DATE_EPOCH=$(sed -n 's/^SOURCE_DATE_EPOCH=//p' /src/ndk/build.conf)

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

# recipe_hash NAME: identity of a recipe = recipe file + patches + files the recipe copies from ndk/module/NAME/
# (git: gitconfig) + env + SOURCE_DATE_EPOCH (only that value of build.conf, so a version bump rebuilds nothing)
# + builder image (Dockerfile: NDK, Go, Rust and Debian pins) + dependency hashes, so a toolchain bump rebuilds
# every recipe
recipe_hash() {
  local n=$1 d h
  h=$( { cat "$(recipe_file "$n")" /src/ndk/lib/env.sh /src/ndk/lib/api-site.py /src/ndk/build.sh /src/ndk/Dockerfile;
         echo "SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH";
         [ -d "/src/ndk/patches/$n" ] && find "/src/ndk/patches/$n" -type f | sort | xargs cat;
         [ -d "/src/ndk/module/$n" ] && find "/src/ndk/module/$n" -type f | sort | xargs cat;
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

# curl has no transfer timeout of its own: a server that stops sending would hang the build. Less than 1 byte/s
# for 60 s (or no connection in 30 s) fails the attempt, and --retry starts the next one.
CURL_FETCH=(curl -fsSL --retry 5 --connect-timeout 30 --speed-limit 1 --speed-time 60)
# fetch_one URL SHA256 FILE: FILE (under $DL) with that SHA256. A cached FILE that matches is used without any
# download; otherwise the download goes to FILE.part, is checked, and only a matching file is renamed to FILE.
# A failed download or a mismatch removes FILE.part and fails the recipe.
fetch_one() {
  local u=$1 h=$2 f=$3
  if [ -f "$f" ] && echo "$h  $f" | sha256sum -c --quiet - 2>/dev/null; then
    return 0
  fi
  log "fetch $NAME $u"
  rm -f "$f.part"
  if ! "${CURL_FETCH[@]}" -o "$f.part" "$u"; then
    rm -f "$f.part"
    log "FETCH FAILED $NAME $u"
    exit 1
  fi
  if ! echo "$h  $f.part" | sha256sum -c --quiet -; then
    rm -f "$f.part"
    log "SHA256 MISMATCH $NAME $u"
    exit 1
  fi
  mv "$f.part" "$f"
}
fetch() {
  fetch_one "$URL" "$SHA256" "$DL/$TARBALL"
  # EXTRA_SRCS: additional upstream files ("URL SHA256" per entry), e.g. official patch series
  local x
  for x in "${EXTRA_SRCS[@]}"; do
    fetch_one "${x% *}" "${x##* }" "$DL/$(basename "${x% *}")"
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
    patch -d "$B/src/$SRCDIR" -p1 --no-backup-if-mismatch -s < "$p" || { log "PATCH FAILED $NAME $(basename "$p")"; exit 1; }
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
  # drop the old stamp first: the step below removes the recipe's previous package and outputs, so after a
  # failed build an old stamp (valid again once the recipe is reverted) would stand for outputs that are gone
  rm -f "$B/stamps/$n".*
  # The subshell must not be part of a conditional (|| exit, if !): bash then ignores set -e for every
  # command in it, and a failed download, extraction or patch would still yield a stamped recipe.
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
    patches=$(ls "/src/ndk/patches/$PATCHES_FROM"/*.patch 2>/dev/null | xargs -r -n1 basename | sort | paste -sd, -) || true
    bins=$(cat "$B/meta/$n.bins" 2>/dev/null | sort -u | paste -sd, - || true)
    # recipe values go to python as arguments, never into its source (quotes or backslashes in them stay as they are)
    python3 -I - "$OUT/meta/$n.json" "$n" "$VERSION" "$URL" "$SHA256" "$CHECKSUM_SOURCE" "$LICENSE" "$DEPS" \
      "$patches" "$bins" "$h" "${LINKAGE:-static}" <<'PY'
import json, sys
out, n, version, url, sha256, checksum_source, lic, deps, patches, bins, h, linkage = sys.argv[1:13]
json.dump({"recipe": n, "version": version, "url": url, "sha256": sha256,
           "checksum_source": checksum_source, "license": lic, "deps": deps.split(),
           "patches": [p for p in patches.split(",") if p], "bins": [b for b in bins.split(",") if b],
           "recipe_hash": h, "linkage": linkage}, open(out, "w"), indent=1, sort_keys=True)
PY
  )
  touch "$B/stamps/$n.$h"
  DONE[$n]=1
}

# check_dl_names RECIPE...: the recipes and their dependencies share one download directory ($DL, files by
# name): two different files (different SHA256) under one name would replace each other there. Fail before any
# fetch; one name with one SHA256 (the same file used by several recipes) is fine.
check_dl_names() {
  local r x clash
  clash=$(for r in $( { for x in "$@"; do all_deps "$x"; echo "$x"; done; } | awk '!seen[$0]++'); do
            ( load_recipe "$r"
              echo "$TARBALL $SHA256 $r"
              for x in "${EXTRA_SRCS[@]}"; do echo "$(basename "${x% *}") ${x##* } $r"; done )
          done | sort | awk '$1 == n && $2 != s {print n ": " s " (" r ") and " $2 " (" $3 ")"} {n = $1; s = $2; r = $3}')
  if [ -n "$clash" ]; then
    log "download name used for different files (set TARBALL or rename): $clash"
    exit 1
  fi
}

if [ $# -gt 0 ]; then
  check_dl_names "$@"
  for t in "$@"; do build_one "$t"; done
  log "done (recipes only: $*)"
  exit 0
fi

mapfile -t ALL_RECIPES < <(grep -v '^#' /src/ndk/recipes.list | tr ' ' '\n' | grep .)
check_dl_names "${ALL_RECIPES[@]}"
FAILED=()
for t in $(grep -v '^#' /src/ndk/recipes.list); do
  # outside any conditional, so set -e stays in force inside build_one (see there)
  set +e
  ( set -e; build_one "$t" )
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || FAILED+=("$t")
done
printf '%s\n' "${FAILED[@]}" > "$OUT/failed.txt"
if [ ${#FAILED[@]} -ne 0 ]; then
  # A failed recipe must not silently drop a tool from the ZIP.
  log "recipes failed: ${FAILED[*]}; not packaging"
  exit 1
fi
log "package"
bash /src/ndk/package.sh
log "done"
