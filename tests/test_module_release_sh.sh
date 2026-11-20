# ci/module-release.sh (real script) in a throwaway fixture repo: a stub ./build-ndk.sh makes the module files,
# a stub git answers ls-remote/push (everything else is the real git on the fixture), a stub curl plays the forge
# (FORGE_MODE picks the failure). No network.
. "$ALT_TESTS/lib.sh"
REAL_GIT=$(command -v git)
tok="t-$$-example"
TAG=v9.9-r1

# new_fixture: scratch dir with repo/ (fixture git repo with the script under test), bin/ (stubs), state/; prints it
new_fixture() {
  local h; h=$(alt_scratch)
  mkdir -p "$h/repo/ndk" "$h/repo/ci" "$h/bin" "$h/state" "$h/tmp" "$h/cache"
  cp "$ALT_TREE/ci/module-release.sh" "$h/repo/ci/"
  printf 'V2_VERSION=9.9\nMODULE_RELEASE=1\n' > "$h/repo/ndk/build.conf"
  cat > "$h/repo/README.md" <<'EOF'
# fixture
12 commands plus `alt-list`
## Contents (v1.0-r1)
From `dist/MANIFEST-v2.json` of the v1.0-r1 build.
| `android-linux-tools-v1.0-r1.zip` | 1 | 1.0 MB |
## History
- v9.9-r1: test change.
EOF
  cat > "$h/repo/build-ndk.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
mkdir -p dist
python3 -I - <<'PY'
import json, os, zipfile
tag, url = "v9.9-r1", "https://forge.example.invalid/o/r"
z = f"dist/android-linux-tools-{tag}.zip"
with zipfile.ZipFile(z, "w") as f:
    f.writestr("module.prop", f"id=android-linux-tools\nversion={tag}\nversionCode=909001\n"
               f"updateJson={url}/raw/branch/main/update.json\n")
json.dump({"version": tag, "versionCode": 909001, "zipUrl": f"{url}/releases/download/{tag}/{os.path.basename(z)}"},
          open("dist/update.json", "w"))
json.dump({"version": tag, "versionCode": 909001, "host_check_errors": 0, "zip_bytes": os.path.getsize(z),
           "unpacked_mb": 0.1}, open("dist/MANIFEST-v2.json", "w"))
PY
cd dist && sha256sum android-linux-tools-v9.9-r1.zip > android-linux-tools-v9.9-r1.zip.sha256
EOF
  chmod +x "$h/repo/build-ndk.sh"
  cat > "$h/bin/git" <<'EOF'
#!/usr/bin/env bash
# records argv; ls-remote: no such tag; push: recorded, not sent; workflow mode (WF=1): clone/checkout faked
printf 'git %s\n' "$*" >> "$STATE/argv"
a=("$@"); sub=; auth=none; i=0
while [ "$i" -lt "${#a[@]}" ]; do
  case ${a[$i]} in
    -c) [ "${a[$((i + 1))]}" = "http.extraHeader=Authorization: token $RELEASE_TOKEN" ] && auth=argv; i=$((i + 2)) ;;
    -*) i=$((i + 1)) ;;
    *) sub=${a[$i]}; break ;;
  esac
done
[ "${GIT_CONFIG_COUNT:-}" = 1 ] && [ "${GIT_CONFIG_KEY_0:-}" = http.extraHeader ] &&
  [ "${GIT_CONFIG_VALUE_0:-}" = "Authorization: token $RELEASE_TOKEN" ] && auth=env
case "$sub:${WF:-}" in
  ls-remote:*) exit 2 ;;
  push:*) echo "push auth=$auth" >> "$STATE/calls"; exit 0 ;;
  clone:1)
    echo "clone auth=$auth" >> "$STATE/calls"
    mkdir -p "${a[-1]}/ci"
    printf '%s\n' 'if [ -n "${RELEASE_TOKEN:-}" ]; then t=set; else t=unset; fi' \
      'echo "script ran token=$t cache=${ALT_BUILD_CACHE:-}" >> "$STATE/calls"' > "${a[-1]}/ci/module-release.sh"
    exit 0 ;;
  checkout:1) exit 0 ;;
esac
exec "$REAL_GIT" "$@"
EOF
  cat > "$h/bin/curl" <<'EOF'
#!/usr/bin/env python3
# the forge: state in $STATE/forge.json; one line per call in $STATE/calls (method, path, how the token came)
import json, os, shutil, stat, subprocess, sys
st = os.environ["STATE"]
mode = os.environ.get("FORGE_MODE", "ok")
want = "Authorization: token " + os.environ["RELEASE_TOKEN"]
with open(st + "/argv", "a") as f:
    f.write("curl " + " ".join(sys.argv[1:]) + "\n")
sp = st + "/forge.json"
s = json.load(open(sp)) if os.path.exists(sp) else {"draft": None, "assets": {}}
args, meth, out, wfmt, form, url, auth, fm, dm = sys.argv[1:], "GET", None, None, None, None, "none", "-", "-"
i = 0
while i < len(args):
    a = args[i]
    if a in ("-X", "-H", "-o", "-w", "-d", "-F", "--retry"):
        v = args[i + 1]
        i += 2
        if a == "-X": meth = v
        elif a == "-o": out = v
        elif a == "-w": wfmt = v
        elif a == "-F": form = v
        elif a == "-H" and v.startswith("@"):
            p = v[1:]
            if open(p).read().strip() == want:
                auth = "file"
                fm = "%o" % stat.S_IMODE(os.stat(p).st_mode)
                dm = "%o" % stat.S_IMODE(os.stat(os.path.dirname(os.path.abspath(p))).st_mode)
        elif a == "-H" and v == want:
            auth = "argv"
        continue
    if a.startswith("https://"): url = a
    i += 1
api = "https://forge.example.invalid/api/v1/repos/o/r"
path = url[len(api):] if url.startswith(api) else url
with open(st + "/calls", "a") as f:
    f.write(f"{meth} {path} auth={auth} fmode={fm} dmode={dm}\n")
def save(): json.dump(s, open(sp, "w"))
def reply(obj): print(json.dumps(obj)); save(); sys.exit(0)
def fail(rc, body=""): save(); body and print(body); sys.exit(rc)
tag = "v9.9-r1"
if wfmt:
    if path in (f"/tags/{tag}", f"/releases/tags/{tag}"): print("404", end=""); sys.exit(0)
elif meth == "POST" and path == "/releases":
    if mode == "post_fail": fail(22, '{"message":"rejected"}')
    s["draft"] = True
    if mode == "post_lost": fail(56)
    reply({"id": 7})
elif meth == "POST" and path.startswith("/releases/7/assets?name="):
    if mode == "upload_fail": fail(22, '{"message":"upload rejected"}')
    name = path.split("=", 1)[1]
    shutil.copy(form.split("@", 1)[1], st + "/asset-" + name)
    s["assets"][str(len(s["assets"]) + 1)] = name
    reply({"id": len(s["assets"])})
elif meth == "GET" and path.startswith("/releases/7/assets/"):
    name = s["assets"][path.rsplit("/", 1)[1]]
    reply({"browser_download_url": f"https://forge.example.invalid/o/r/releases/download/{tag}/{name}"})
elif meth == "GET" and path.startswith(f"https://forge.example.invalid/o/r/releases/download/{tag}/"):
    shutil.copy(st + "/asset-" + path.rsplit("/", 1)[1], out)
    if mode == "corrupt": open(out, "ab").write(b"x")
    sys.exit(0)
elif meth == "PATCH" and path == "/releases/7":
    s["draft"] = False
    if mode in ("patch_lost", "get_fail"): fail(56)
    reply({"id": 7, "draft": False})
elif meth == "GET" and path == "/releases/7":
    if mode == "get_fail": fail(7)
    reply({"id": 7, "draft": s["draft"]})
elif meth == "DELETE" and path == "/releases/7":
    s["draft"] = "deleted"
    fail(0)
elif meth == "GET" and path == f"/tags/{tag}":
    sha = subprocess.run([os.environ["REAL_GIT"], "rev-parse", tag + "^{commit}"], capture_output=True, text=True).stdout.strip()
    reply({"commit": {"sha": sha}})
print(f"stub curl: unknown request {meth} {url}", file=sys.stderr)
sys.exit(99)
EOF
  chmod +x "$h/bin/git" "$h/bin/curl"
  (cd "$h/repo" && "$REAL_GIT" init -q -b main && "$REAL_GIT" add -A &&
    "$REAL_GIT" -c user.name=t -c user.email=t@example.invalid commit -qm fixture &&
    "$REAL_GIT" remote add origin https://forge.example.invalid/o/r.git) || { echo "tests: fixture repo failed" >&2; exit 2; }
  echo "$h"
}
# run_release H MODE: run the script in H/repo against the stub forge in MODE; prints its exit code
run_release() {
  (cd "$1/repo" && PATH="$1/bin:$PATH" TMPDIR="$1/tmp" STATE="$1/state" FORGE_MODE=$2 REAL_GIT=$REAL_GIT \
    RELEASE_TOKEN=$tok SERVER_URL=https://forge.example.invalid REPOSITORY=o/r ALT_BUILD_CACHE="$1/cache" \
    bash ci/module-release.sh) > "$1/out.txt" 2>&1
  echo $?
}
# draft H: the release's state on the stub forge (True, False, deleted, None)
draft() { python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["draft"])' "$1/state/forge.json"; }

case_ok() {
  local h rc; h=$(new_fixture)
  rc=$(run_release "$h" ok)
  if [ "$rc" = 0 ] && [ "$(draft "$h")" = False ] && grep -q "published $TAG" "$h/out.txt" && ! grep -q '^DELETE' "$h/state/calls"; then
    ok "release: published, nothing deleted"
  else
    bad "release: rc=$rc draft=$(draft "$h"): $(tail -3 "$h/out.txt")"
  fi
  rm -rf "$h"
}

# F1: the draft request fails (rejected, or applied with the reply lost): the error names the tag and says
# the forge may hold a draft to check by hand
case_draft_request() {
  local h rc m; m=$1; h=$(new_fixture)
  rc=$(run_release "$h" "$m")
  if [ "$rc" = 1 ] && grep -q "ERROR: .*the forge may hold a draft release for tag $TAG, check https://forge.example.invalid/o/r/releases by hand" "$h/out.txt"; then
    ok "draft request ($m): rc=1, the error names $TAG and the draft to check"
  else
    bad "draft request ($m): rc=$rc, no draft warning: $(tail -2 "$h/out.txt")"
  fi
  rm -rf "$h"
}

# F2: a failure after the draft exists deletes it only when the forge confirms it is still a draft; the exit
# code is the failing step's
case_cleanup() {
  local h rc m=$1 want_rc=$2 want=$3; h=$(new_fixture)
  rc=$(run_release "$h" "$m")
  if [ "$rc" = "$want_rc" ] && [ "$(draft "$h")" = "$want" ]; then
    case "$want" in
      deleted) ok "cleanup ($m): rc=$rc, the draft is deleted" ;;
      *) if grep -q "release 7 ($TAG) not deleted: .*check https://forge.example.invalid/o/r/releases by hand" "$h/out.txt"; then
           ok "cleanup ($m): rc=$rc, release not deleted and named to check by hand"
         else bad "cleanup ($m): kept, but no check-by-hand line: $(tail -2 "$h/out.txt")"; fi ;;
    esac
  else
    bad "cleanup ($m): rc=$rc (want $want_rc), release $(draft "$h") (want $want): $(grep -c '^DELETE' "$h/state/calls") DELETE calls"
  fi
  rm -rf "$h"
}

case_ok
case_draft_request post_fail
case_draft_request post_lost
case_cleanup upload_fail 1 deleted
case_cleanup patch_lost 56 False
case_cleanup get_fail 56 False
[ "$FAILS" -eq 0 ]
