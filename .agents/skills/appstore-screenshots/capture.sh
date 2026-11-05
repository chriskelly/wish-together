#!/bin/sh
# Capture one App Store listing screenshot from the real app on a booted
# simulator, signed in to the staging database with a dev token.
#
#   ./capture.sh 03-home /
#   ./capture.sh 01-the-carters /group/demo-group-family
#   WT_EXTRA_DEFINES="--dart-define=WT_SHOT_SCROLL=480" \
#     ./capture.sh 04-sasha-birthday /wishlist/demo-wishlist-sasha-birthday 14
#
# The route is a compile-time define, so every screen costs one build. The token
# is read from $WT_TOKEN_FILE (a file, not an argument) and never enters the
# repository. PNGs land in $WT_OUT_DIR, outside the repository by default.
#
# Environment:
#   WT_TOKEN_FILE    file holding the dev token; required unless --signed-out
#   WT_UDID          simulator to use; required when more than one is booted
#   WT_OUT_DIR       where the PNG goes; defaults to $TMPDIR/appstore-shots
#   WT_APP_DIR       repository root to build; defaults to the current directory
#   WT_BUNDLE_ID     defaults to gift.wishtogether
#   WT_EXTRA_DEFINES extra --dart-define flags, e.g. WT_SHOT_SCROLL / WT_SHOT_TAP
set -eu

OUT="${1:?usage: capture.sh <name> <route> [wait-seconds] [--signed-out]}"
ROUTE="${2:?usage: capture.sh <name> <route> [wait-seconds] [--signed-out]}"
WAIT="${3:-12}"
MODE="${4:-}"

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${WT_APP_DIR:-$(pwd)}"
BUNDLE_ID="${WT_BUNDLE_ID:-gift.wishtogether}"
ENTRYPOINT="lib/dev/scenarios/local/appstore_shots.dart"
OUT_DIR="${WT_OUT_DIR:-${TMPDIR:-/tmp}/appstore-shots}"

# Without ffmpeg the PNG keeps its alpha channel, which App Store Connect
# rejects, so stop before spending a build on it.
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg is required to strip the alpha channel (brew install ffmpeg)." >&2
  exit 2
fi

if [ -z "${WT_UDID:-}" ]; then
  booted=$(xcrun simctl list devices booted | awk -F '[()]' '/Booted/{print $2}')
  count=$(printf '%s\n' "$booted" | grep -c . || true)
  if [ "$count" -ne 1 ]; then
    echo "Found ${count} booted simulators; set WT_UDID to the medium device" >&2
    echo "you mean (a Pro Max writes 1320x2868, not the required size):" >&2
    printf '%s\n' "$booted" | sed 's/^/  /' >&2
    exit 2
  fi
  UDID="$booted"
else
  UDID="$WT_UDID"
fi
echo "simulator: ${UDID}"

mkdir -p "$OUT_DIR"
case "$OUT" in
  /*) ;;
  *) OUT="${OUT_DIR%/}/${OUT}" ;;
esac

DEFINES="--dart-define=WT_SHOT_ROUTE=${ROUTE} ${WT_EXTRA_DEFINES:-}"
if [ "$MODE" = "--signed-out" ]; then
  DEFINES="$DEFINES --dart-define=WT_SHOT_SIGNED_OUT=true"
else
  : "${WT_TOKEN_FILE:?set WT_TOKEN_FILE to a file holding the dev token}"
  # A tail of the mint script's output is a sentence, not a token; take only a
  # JWT-shaped line so a bad file fails here rather than after a build.
  TOKEN=$(grep -E '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' "$WT_TOKEN_FILE" | head -1)
  if [ -z "$TOKEN" ]; then
    echo "WT_TOKEN_FILE does not hold a dev token." >&2
    echo "Mint one with: npm --prefix scripts run --silent dev:token -- \\" >&2
    echo "  --uid <uid> --database staging" >&2
    exit 2
  fi
  DEFINES="$DEFINES --dart-define=WT_DEV_TOKEN=${TOKEN}"
fi

cd "$APP_DIR"
if [ ! -f "$ENTRYPOINT" ]; then
  mkdir -p "$(dirname "$ENTRYPOINT")"
  cp "$SKILL_DIR/appstore_shots.dart" "$ENTRYPOINT"
  echo "copied the entrypoint template to ${ENTRYPOINT} (gitignored)"
fi

# shellcheck disable=SC2086
flutter build ios --simulator --debug -t "$ENTRYPOINT" $DEFINES

xcrun simctl uninstall "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep "$WAIT"
xcrun simctl io "$UDID" screenshot --type=png "${OUT}.png"
xcrun simctl terminate "$UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

# App Store Connect rejects any alpha channel, and the simulator always writes
# one even though the image looks opaque.
ffmpeg -y -loglevel error -i "${OUT}.png" -pix_fmt rgb24 "${OUT}.flat.png"
mv "${OUT}.flat.png" "${OUT}.png"

dims=$(sips -g pixelWidth -g pixelHeight "${OUT}.png" |
  awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{print w"x"h}')
echo "captured ${OUT}.png (${dims})"

if [ "$dims" != "1206x2622" ]; then
  echo ""
  echo "WARNING: ${dims} is not the required 1206x2622 and verify.sh will fail."
  echo "Capture on a medium device (iPhone 16 Pro / 17 Pro) for that size, or"
  echo "downscale this one:"
  echo "  ffmpeg -y -loglevel error -i '${OUT}.png' \\"
  echo "    -vf 'scale=1206:2622:flags=lanczos' -pix_fmt rgb24 '${OUT}.1206.png'"
  echo "  mv '${OUT}.1206.png' '${OUT}.png'"
fi
