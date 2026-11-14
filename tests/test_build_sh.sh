# ndk/build.sh (real script, in bwrap) with small fake recipes and local source tarballs.
. "$ALT_TESTS/lib.sh"

# new_tree: scratch dir with the build scripts of ALT_TREE under src/ndk; prints its path
new_tree() {
  local h; h=$(alt_scratch)
  mkdir -p "$h/src/ndk/lib" "$h/src/ndk/recipes" "$h/src/fx" "$h/work"
  cp "$ALT_TREE/ndk/build.sh" "$ALT_TREE/ndk/Dockerfile" "$ALT_TREE/ndk/build.conf" "$h/src/ndk/"
  cp "$ALT_TREE/ndk/lib/env.sh" "$ALT_TREE/ndk/lib/api-site.py" "$h/src/ndk/lib/"
  echo "$h"
}
# tarball H NAME: src/fx/NAME-1.tar.gz with one file; prints its sha256
tarball() {
  mkdir -p "$1/fx-src/$2-1"
  echo "$2" > "$1/fx-src/$2-1/hello.txt"
  tar -C "$1/fx-src" --sort=name --mtime=@0 --owner=0 --group=0 -czf "$1/src/fx/$2-1.tar.gz" "$2-1"
  sha256sum "$1/src/fx/$2-1.tar.gz" | cut -d' ' -f1
}
# recipe H NAME URL SHA BODY: write src/ndk/recipes/NAME.sh with build() { BODY; }
recipe() {
  printf 'VERSION=1\nURL=%s\nSHA256=%s\nLICENSE=MIT\nbuild() { %s; }\n' "$3" "$4" "$5" > "$1/src/ndk/recipes/$2.sh"
}
build() {
  local h=$1; shift
  alt_bwrap "$h/root" "$h/src" "$h/work" bash /src/ndk/build.sh "$@"
}

# a recipe input under ndk/module/<recipe>/ (git's gitconfig) is part of the recipe's identity
case_module_input() {
  local h sha; h=$(new_tree)
  sha=$(tarball "$h" altmod)
  recipe "$h" altmod file:///src/fx/altmod-1.tar.gz "$sha" \
    'mkdir -p "$OUT/data/rt/altmod/etc"; cp "$SRCROOT/ndk/module/altmod/conf" "$OUT/data/rt/altmod/etc/conf"'
  mkdir -p "$h/src/ndk/module/altmod"
  echo v1 > "$h/src/ndk/module/altmod/conf"
  build "$h" altmod > "$h/run1.txt" 2>&1 || { bad "module input: first build failed"; return; }
  echo v2 > "$h/src/ndk/module/altmod/conf"
  build "$h" altmod > "$h/run2.txt" 2>&1 || { bad "module input: second build failed"; return; }
  if [ "$(cat "$h/work/out/data/rt/altmod/etc/conf")" = v2 ]; then
    ok "module input: edited ndk/module/altmod/conf rebuilds the recipe"
  else
    bad "module input: edited ndk/module/altmod/conf, the cached build still has $(cat "$h/work/out/data/rt/altmod/etc/conf")"
  fi
  rm -rf "$h"
}

case_module_input
[ "$FAILS" -eq 0 ]
