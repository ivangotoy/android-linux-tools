# ndk/scripts/stage.py (real script, in bwrap) against a synthetic /work/out: every tools.tsv program is a copy of
# a host ELF, one meta record per recipe, a fake NDK sysroot. The module must ship the NDK sysroot NOTICE (bionic,
# linked into every program) with a licence row in NOTICE.txt and MANIFEST.json.
. "$ALT_TESTS/lib.sh"
ALT_TOOLS="$ALT_TOOLS readelf"
h=$(alt_scratch)
mkdir -p "$h/work/out/meta" "$h/work/out/bin" "$h/work/out/data" "$h/work/stage" "$h/sysroot"
python3 -I - "$ALT_TREE/ndk/tools.tsv" "$h/work/out" "$(type -P true)" <<'PY'
import json, os, shutil, sys
tsv, out, elf = sys.argv[1:4]
recipes = {'ncurses', 'cacert'}
for line in open(tsv):
    if line.strip() and not line.startswith('#'):
        name, recipe, binary = line.split()[:3]
        recipes.add(recipe)
        shutil.copyfile(elf, os.path.join(out, 'bin', binary))
for r in recipes:
    json.dump({'recipe': r, 'version': '1.0', 'url': 'https://example.org/%s-1.0.tar.gz' % r, 'sha256': '0' * 64,
               'checksum_source': 'example', 'license': 'MIT', 'deps': [], 'patches': [], 'bins': [],
               'recipe_hash': '0' * 16, 'linkage': 'static'}, open(os.path.join(out, 'meta', r + '.json'), 'w'))
open(os.path.join(out, 'data', 'cacert.pem'), 'w').write('# example CA bundle\n')
PY
printf 'Copyright (c) example\nRedistribution and use in source and binary forms ...\n' > "$h/sysroot/NOTICE"
alt_bwrap "$h/root" "$ALT_TREE" "$h/work" --ro-bind "$h/sysroot" /opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot \
  --setenv SYSROOT /opt/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot --setenv NDK_RELEASE r30 --setenv API 35 \
  python3 -I /src/ndk/scripts/stage.py > "$h/stage.txt" 2>&1 || { bad "stage.py failed: $(tail -n 3 "$h/stage.txt")"; rm -rf "$h"; exit 1; }
st="$h/work/stage/module/android-linux-tools"
if cmp -s "$h/sysroot/NOTICE" "$st/share/licenses/ndk/android-ndk-sysroot/NOTICE"; then
  ok "NDK sysroot NOTICE shipped as share/licenses/ndk/android-ndk-sysroot/NOTICE"
else
  bad "NDK sysroot NOTICE not in share/licenses/ndk/android-ndk-sysroot/"
fi
if grep -q '^android-ndk-sysroot  *r30 ' "$st/share/licenses/NOTICE.txt"; then ok "NOTICE.txt row"; else bad "no NOTICE.txt row for android-ndk-sysroot"; fi
python3 -I - "$st/system/etc/android-linux-tools/share/android-linux-tools/MANIFEST.json" <<'PY' && ok "MANIFEST.json licence row" || bad "no MANIFEST.json licence row for android-ndk-sysroot"
import json, sys
rows = [r for r in json.load(open(sys.argv[1]))['licenses'] if r['name'] == 'android-ndk-sysroot']
assert len(rows) == 1 and rows[0]['license_files'] == ['share/licenses/ndk/android-ndk-sysroot/NOTICE'], rows
assert rows[0]['version'] == 'r30' and len(rows[0]['sha256']) == 64, rows
PY
rm -rf "$h"
[ "$FAILS" -eq 0 ]
