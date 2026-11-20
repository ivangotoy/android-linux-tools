#!/usr/bin/env bash
# Builds and releases the module version set in ndk/build.conf (run by
# .forgejo/workflows/module-release.yml from a clone of main at the dispatched commit).
#
# Before dispatching: bump V2_VERSION/MODULE_RELEASE in ndk/build.conf and add the
# changelog bullet "- vX.Y-rN: ..." under "## History" in README.md.
#
# build (./build-ndk.sh, cache in ALT_BUILD_CACHE) -> check the ZIP -> release commit
# (README Contents/size lines, root update.json = dist/update.json) -> annotated tag ->
# push main, then the tag -> draft release on the tag -> upload ZIP + .sha256 ->
# download back and compare -> publish.
set -euo pipefail

: "${RELEASE_TOKEN:?}" "${SERVER_URL:?}" "${REPOSITORY:?}" "${ALT_BUILD_CACHE:?}"
MODID=android-linux-tools
API="$SERVER_URL/api/v1/repos/$REPOSITORY"
URL="$SERVER_URL/$REPOSITORY"
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
export GIT_AUTHOR_NAME="Ivan Angelov" GIT_AUTHOR_EMAIL="ivangotoy@gmail.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME" GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"

log() { printf '==> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# the token reaches curl in a header file in a private dir and git in the environment, never a command line
api() { local m="$1" p="$2"; shift 2; curl -sS --fail-with-body --retry 3 -X "$m" -H "@$PRIV/auth" "$@" "$API$p"; }
code() { curl -sS -o /dev/null -w '%{http_code}' -H "@$PRIV/auth" "$API$1"; }
gitauth() { GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0="Authorization: token $RELEASE_TOKEN" git "$@"; }
jget() { python3 -I -c 'import json,sys;d=json.load(sys.stdin)
for k in sys.argv[1].split("."): d=d[int(k)] if k.isdigit() else d[k]
print(d)' "$1"; }
conf() { sed -n "s/^$1=//p" ndk/build.conf; }
# on exit: on failure delete the release only if the forge says it is still a draft (a publish whose reply
# was lost leaves a published release), remove the private dir and the downloaded-back assets; keeps the
# exit code
cleanup() {
    local rc=$?
    set +e
    if [ "${PUBLISHED:-0}" != 1 ] && [[ "${RELEASE_ID:-}" =~ ^[0-9]+$ ]]; then
        if [ "$(api GET "/releases/$RELEASE_ID" 2>/dev/null | jget draft 2>/dev/null)" != True ]; then
            log "release $RELEASE_ID ($TAG) not deleted: the forge did not confirm it is a draft, check $URL/releases by hand"
        elif api DELETE "/releases/$RELEASE_ID" >/dev/null; then
            log "deleted draft release $RELEASE_ID ($TAG)"
        else
            log "deleting draft release $RELEASE_ID ($TAG) failed, check $URL/releases by hand"
        fi
    fi
    rm -rf "$PRIV" "$ROOT"/.work/back-*
    exit "$rc"
}
RELEASE_ID= PUBLISHED=0
PRIV=$(mktemp -d)
trap cleanup EXIT
(umask 077 && printf 'Authorization: token %s\n' "$RELEASE_TOKEN" > "$PRIV/auth")

V2=$(conf V2_VERSION); REL=$(conf MODULE_RELEASE)
[[ "$REL" =~ ^[0-9]+$ ]] || die "bad MODULE_RELEASE '$REL'"
[[ "$V2" =~ ^([0-9]+)\.([0-9]+)$ ]] || die "bad V2_VERSION '$V2'"
VCODE=$((BASH_REMATCH[1] * 100000 + BASH_REMATCH[2] * 1000 + 10#$REL))
TAG="v$V2-r$REL"
ZIP="$MODID-$TAG.zip"
UPDATE_URL="$URL/raw/branch/main/update.json"

# fail early: the version must be new and have its changelog bullet
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1 && die "tag $TAG exists: bump MODULE_RELEASE or V2_VERSION"
[ "$(code "/tags/$TAG")" = 404 ] || die "tag $TAG exists (or the check failed)"
[ "$(code "/releases/tags/$TAG")" = 404 ] || die "release $TAG exists (or the check failed)"
grep -q "^- $TAG: " README.md || die "README.md has no changelog bullet '- $TAG: ...'"
log "release $TAG (versionCode $VCODE)"

# build with the persistent cache (downloads, per-recipe builds, outputs)
mkdir -p "$ALT_BUILD_CACHE" .work
ln -sfn "$ALT_BUILD_CACHE" .work/ndk
./build-ndk.sh

# check the module
[ -f "dist/$ZIP" ] && [ -f "dist/$ZIP.sha256" ] || die "dist/$ZIP or its .sha256 missing"
(cd dist && sha256sum -c --quiet "$ZIP.sha256") || die "dist/$ZIP.sha256 does not verify"
unzip -tq "dist/$ZIP" >/dev/null || die "zip test failed"
PROP=$(unzip -p "dist/$ZIP" module.prop)
for want in "version=$TAG" "versionCode=$VCODE" "updateJson=$UPDATE_URL"; do
    grep -qxF "$want" <<<"$PROP" || die "module.prop lacks '$want'"
done
python3 -I - "dist/update.json" "dist/MANIFEST-v2.json" "$TAG" "$VCODE" "$URL/releases/download/$TAG/$ZIP" <<'PY' || die "dist/update.json or MANIFEST does not match"
import json, sys
u, m = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
assert u["version"] == sys.argv[3] and u["versionCode"] == int(sys.argv[4]) and u["zipUrl"] == sys.argv[5], u
assert m["version"] == sys.argv[3] and m["versionCode"] == int(sys.argv[4]) and m["host_check_errors"] == 0, m
PY
ZIP_SHA=$(sha256sum "dist/$ZIP" | cut -d' ' -f1)
log "built $ZIP sha256 $ZIP_SHA"

# release commit: README Contents/size lines, root update.json
python3 -I - README.md dist/MANIFEST-v2.json "$TAG" "$ZIP" <<'PY'
import json, re, sys
path, man, tag, zipn = sys.argv[1:]
m = json.load(open(man))
s = open(path).read()
n = 0
for pat, rep in ((r"^## Contents \(v[0-9.]+-r[0-9]+\)$", f"## Contents ({tag})"),
                 (r"`dist/MANIFEST-v2\.json` of the v[0-9.]+-r[0-9]+ build\.", f"`dist/MANIFEST-v2.json` of the {tag} build."),
                 (r"^\| `android-linux-tools-v[0-9.]+-r[0-9]+\.zip` \| [0-9]+ \| [0-9.]+ MB \|$",
                  f"| `{zipn}` | {m['zip_bytes']} | {m['unpacked_mb']} MB |")):
    s, k = re.subn(pat, rep, s, count=1, flags=re.M)
    if k != 1:
        sys.exit(f"README: no line matching {pat}")
    n += k
open(path, "w").write(s)
PY
cp dist/update.json update.json
git add README.md update.json
git commit -q -m "Release $TAG"
git tag -a "$TAG" -m "$TAG"
REL_SHA=$(git rev-parse HEAD)
log "release commit $REL_SHA, tag $TAG"

# push main (fast-forward only), then the tag
gitauth push -q origin "HEAD:refs/heads/main" || die "push of main failed (main moved?)"
gitauth push -q origin "refs/tags/$TAG" || die "push of tag $TAG failed"

# draft release on the tag, upload, download back, publish
BODY=$(python3 -I - README.md "$TAG" "$ZIP" dist/MANIFEST-v2.json <<'PY'
import json, re, sys
path, tag, zipn, man = sys.argv[1:]
s = open(path).read()
cmds = re.search(r"^(\d+) commands plus `alt-list`", s, re.M).group(1)
b = re.search(r"^- " + re.escape(tag) + r": (.*?)(?=^- |^## |\Z)", s, re.M | re.S).group(1)
change = " ".join(l.strip() for l in b.strip().splitlines())
change = change[0].upper() + change[1:]
size = json.load(open(man))["zip_bytes"]
print(f"Android Linux tools {tag}: one module ZIP with {cmds} Linux command-line tools for rooted Android "
      "(aarch64), built with the Android NDK. Install it from the root manager app (Magisk, KernelSU with or "
      "without a metamodule, APatch) and reboot.\n\n"
      f"Changes:\n- {change}\n\n"
      f"Assets: `{zipn}` ({size} bytes) and its `.sha256`.")
PY
)
REQ=$(python3 -I -c 'import json,sys;print(json.dumps({"tag_name":sys.argv[1],"name":sys.argv[1],"body":sys.argv[2],"draft":True}))' "$TAG" "$BODY")
# a rejected request, or one the forge applied but whose reply was lost, may leave a draft on the forge
nodraft="creating the draft release failed: the forge may hold a draft release for tag $TAG, check $URL/releases by hand"
RELEASE_ID=$(api POST /releases -H 'Content-Type: application/json' -d "$REQ" | jget id) || die "$nodraft"
[[ "$RELEASE_ID" =~ ^[0-9]+$ ]] || die "$nodraft (reply id '$RELEASE_ID')"
log "draft release $RELEASE_ID"
for f in "$ZIP" "$ZIP.sha256"; do
    id=$(api POST "/releases/$RELEASE_ID/assets?name=$f" -F "attachment=@dist/$f" | jget id)
    u=$(api GET "/releases/$RELEASE_ID/assets/$id" | jget browser_download_url)
    curl -sSL --fail-with-body -H "@$PRIV/auth" -o ".work/back-$f" "$u"
    cmp -s "dist/$f" ".work/back-$f" || die "uploaded $f differs from dist/$f"
    rm -f ".work/back-$f"
    log "uploaded and compared $f"
done
api PATCH "/releases/$RELEASE_ID" -H 'Content-Type: application/json' -d '{"draft":false}' >/dev/null
PUBLISHED=1
[ "$(api GET "/tags/$TAG" | jget commit.sha)" = "$REL_SHA" ] || die "tag $TAG does not point at $REL_SHA"
log "published $TAG"

log "done: $UPDATE_URL -> $TAG"
