#!/usr/bin/env bash
# android-linux-tools: build the NDK builder image and run ndk/build.sh inside it.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK="$ROOT/.work/ndk"
IMAGE=android-linux-tools-ndk:r30
JOBS=${JOBS:-8}
MEM=${MEM:-12G}

usage() {
  echo "usage: ./build-ndk.sh [--clean] [--image-only] [--shell] [tool...]"
  echo "  --clean       delete .work/ndk/{build,out,stage} and dist/ before building (downloads are kept)"
  echo "  --clean-all   like --clean and also delete the downloaded sources"
  echo "  --image-only  only build the container image"
  echo "  --shell       open a shell in the builder"
  echo "  tool...       only build these recipes (and their dependencies); no module packaging"
  echo "  env: JOBS (make -j, default 8), MEM (memory limit, default 12G)"
}
CLEAN=0; IMAGE_ONLY=0; SHELL_MODE=0; TOOLS=()
for a in "$@"; do
  case "$a" in
    --clean) CLEAN=1 ;;
    --clean-all) CLEAN=2 ;;
    --image-only) IMAGE_ONLY=1 ;;
    --shell) SHELL_MODE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage >&2; exit 2 ;;
    *) TOOLS+=("$a") ;;
  esac
done

for t in docker systemd-run; do
  command -v "$t" >/dev/null || { echo "missing host tool: $t" >&2; exit 1; }
done
mkdir -p "$WORK/tmp"
export TMPDIR="$WORK/tmp"

docker buildx build --builder default --load -t "$IMAGE" "$ROOT/ndk"
[ "$IMAGE_ONLY" = 1 ] && exit 0

if [ "$CLEAN" -ge 1 ]; then
  rm -rf "$WORK/build" "$WORK/out" "$WORK/stage"
  rm -f "$ROOT"/dist/android-linux-tools*-v2.* "$ROOT/dist/MANIFEST-v2.json"
fi
if [ "$CLEAN" -ge 2 ]; then
  rm -rf "$WORK/dl"
fi
mkdir -p "$WORK/build" "$WORK/out" "$WORK/dl" "$WORK/stage" "$ROOT/dist"

run=(docker run --rm --init --network host
     --memory "$MEM" --memory-swap "$MEM"
     --user "$(id -u):$(id -g)" --security-opt no-new-privileges --cap-drop ALL
     -e JOBS="$JOBS" -e HOME=/work/build/home -e TMPDIR=/work/build/tmp -e ALT_HOST_HOME="$HOME"
     -v "$ROOT:/src:ro"
     -v "$WORK/build:/work/build" -v "$WORK/out:/work/out" -v "$WORK/dl:/work/dl"
     -v "$WORK/stage:/work/stage" -v "$ROOT/dist:/work/dist")
if [ "$SHELL_MODE" = 1 ]; then
  exec "${run[@]}" -it "$IMAGE" bash
fi
exec systemd-run --user --scope --quiet -p MemoryMax="$MEM" -p MemorySwapMax=0 \
  "${run[@]}" "$IMAGE" bash /src/ndk/build.sh "${TOOLS[@]}"
