#!/bin/bash
# Records the --demo tour of SunMemo into a video, for the promo.
#
# Usage: scripts/record-demo.sh [language]
#   language: zh-Hans (default), en or es. Captions and memo text follow it.
#
# Needs Screen Recording permission for your terminal: System Settings ›
# Privacy & Security › Screen Recording. Before running, hide desktop icons
# and other windows you do not want in the shot, and park the pointer at the
# bottom of the screen: the demo moves nothing but its own windows.
#
# The demo runs on throwaway data: your memos, screenshots, SunMemo.md and
# the macOS screenshot settings are never touched.
set -euo pipefail
cd "$(dirname "$0")/.."

LANGUAGE="${1:-zh-Hans}"
APP="build/SunMemo.app"
MOV="build/SunMemo-demo-$LANGUAGE.mov"
MP4="build/SunMemo-demo-$LANGUAGE.mp4"

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
rm -f "$MOV" "$MP4"

# screencapture -v stops when it reads a character, so it reads from a pipe
# we hold open. -V caps the length in case the demo never ends.
FIFO="$(mktemp -u)"
mkfifo "$FIFO"
screencapture -v -V 120 -D 1 "$MOV" < "$FIFO" &
REC=$!
exec 3> "$FIFO"
trap 'exec 3>&-; rm -f "$FIFO"' EXIT
sleep 1.5

echo "Recording. The tour takes about 50 seconds and quits by itself..."
open -W -n "$APP" --args --demo -AppleLanguages "($LANGUAGE)"
sleep 0.8

printf 'q' >&3
for _ in $(seq 1 50); do kill -0 "$REC" 2>/dev/null || break; sleep 0.2; done
kill -INT "$REC" 2>/dev/null || true
wait "$REC" 2>/dev/null || true

[ -s "$MOV" ] || { echo "No video was written. Check the Screen Recording permission."; exit 1; }
echo "Recorded $MOV"

# An MP4 at 1080p plays everywhere, from WeChat to GitHub. Optional.
if command -v ffmpeg >/dev/null; then
  ffmpeg -loglevel error -y -i "$MOV" -vf "scale=1920:-2:flags=lanczos,fps=60" \
    -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart -an "$MP4"
  echo "Converted $MP4"
else
  echo "Install ffmpeg (brew install ffmpeg) to also get an MP4."
fi
