#!/bin/bash
# Records the --demo tour of SunMemo into a video, for the promo.
#
# Usage: scripts/record-demo.sh [language]
#   language: zh-Hans (default), en or es. Captions and memo text follow it.
#   CLEAN=1 leaves the captions out, for scripts/promo/make-promo.sh to add
#   its own titles, music and sounds.
#
# Needs Screen Recording permission for your terminal: System Settings ›
# Privacy & Security › Screen Recording. The demo covers the desktop with
# its own backdrop and parks the pointer at the bottom edge; do not touch
# the mouse while it runs: the bottom edge is cut from the promo, the
# pointer anywhere else is not.
#
# The demo runs on throwaway data: your memos, screenshots, SunMemo.md and
# the macOS screenshot settings are never touched.
#
# Writes build/SunMemo-demo-<language>.mov, the tour's timeline next to it
# (.markers.jsonl), and an MP4 when ffmpeg is installed.
set -euo pipefail
cd "$(dirname "$0")/.."

LANGUAGE="${1:-zh-Hans}"
APP="build/SunMemo.app"
MOV="build/SunMemo-demo-$LANGUAGE.mov"
MP4="build/SunMemo-demo-$LANGUAGE.mp4"
MARKERS="build/SunMemo-demo-$LANGUAGE.markers.jsonl"
BACKDROP="scripts/promo/backdrop.jpg"

# The app reads the backdrop and writes the markers in a temporary folder:
# inside ~/Documents, macOS would stop the tour to ask for access.
SCRATCH="$(mktemp -d)"

[ -d "$APP" ] || scripts/build-app.sh release

# A running SunMemo would hang its own line over the demo's.
if pgrep -xq SunMemo; then
  read -r -p "SunMemo is running and would show up in the video. Quit it now? [y/N] " answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || { echo "Quit SunMemo first, then run this again."; exit 1; }
  # SIGTERM, so it puts the screenshot settings back as on a normal quit.
  pkill -TERM -x SunMemo
  while pgrep -xq SunMemo; do sleep 0.2; done
fi

mkdir -p build
rm -f "$MOV" "$MP4" "$MARKERS"

ARGS=(--demo --demo-markers "$SCRATCH/markers.jsonl" -AppleLanguages "($LANGUAGE)")
if [ -f "$BACKDROP" ]; then
  cp "$BACKDROP" "$SCRATCH/backdrop.jpg"
  ARGS+=(--demo-backdrop "$SCRATCH/backdrop.jpg")
fi
[ "${CLEAN:-0}" = "1" ] && ARGS+=(--demo-no-captions)

# screencapture -v stops when it reads a character, so it reads from a pipe
# we hold open. -V caps the length in case the demo never ends.
FIFO="$SCRATCH/stop"
mkfifo "$FIFO"
screencapture -v -V 120 -D 1 "$MOV" < "$FIFO" &
REC=$!
exec 3> "$FIFO"
trap 'exec 3>&-; rm -rf "$SCRATCH"' EXIT
sleep 1.5

echo "Recording. The tour takes about a minute and quits by itself..."
open -W -n "$APP" --args "${ARGS[@]}"
sleep 0.8

printf 'q' >&3
for _ in $(seq 1 50); do kill -0 "$REC" 2>/dev/null || break; sleep 0.2; done
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true
cp "$SCRATCH/markers.jsonl" "$MARKERS" 2>/dev/null || true

[ -s "$MOV" ] || { echo "No video was written. Check the Screen Recording permission."; exit 1; }
echo "Recorded $MOV"

# An MP4 at 1080p plays everywhere, from WeChat to GitHub. Optional, and
# skipped for a clean take, which make-promo.sh edits from the .mov.
if [ "${CLEAN:-0}" != "1" ] && command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -y -i "$MOV" -vf "scale=1920:-2:flags=lanczos,fps=60" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart -an "$MP4"
  echo "Converted $MP4"
fi
