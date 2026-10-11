#!/bin/bash
# Turns a clean take of the --demo tour into the finished promo: camera
# moves and titles (compose.swift), music and sound effects (audio.py).
#
# Usage:
#   CLEAN=1 scripts/record-demo.sh zh-Hans   # record a take without captions
#   scripts/promo/make-promo.sh [zh-Hans|en]  # edit it into the promo
#
# Writes build/SunMemo-promo-<language>.mp4, 1080p60 with sound.
# Needs ffmpeg and python3 with numpy.
set -euo pipefail
cd "$(dirname "$0")/../.."

LANGUAGE="${1:-zh-Hans}"
case "$LANGUAGE" in zh*) TITLES=zh ;; *) TITLES=en ;; esac
TAKE="build/SunMemo-demo-$LANGUAGE.mov"
MARKERS="build/SunMemo-demo-$LANGUAGE.markers.jsonl"
WORK="build/promo"
OUT="build/SunMemo-promo-$LANGUAGE.mp4"

[ -s "$TAKE" ] && [ -s "$MARKERS" ] || { echo "Record a take first: CLEAN=1 scripts/record-demo.sh $LANGUAGE"; exit 1; }
mkdir -p "$WORK"

echo "Building the editor..."
swiftc -O -suppress-warnings scripts/promo/compose.swift -o "$WORK/compose"

echo "Editing the picture..."
"$WORK/compose" "$TAKE" "$MARKERS" docs/images/icon.png "$WORK/picture.mov" "$TITLES"

echo "Composing the sound..."
python3 scripts/promo/audio.py "$MARKERS" "$WORK/sound.wav"

echo "Mixing..."
ffmpeg -loglevel error -y -i "$WORK/picture.mov" -i "$WORK/sound.wav" \
  -map 0:v -map 1:a -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -r 60 \
  -af "loudnorm=I=-16:TP=-1.5:LRA=11" -c:a aac -b:a 256k -ar 48000 \
  -shortest -movflags +faststart "$OUT"
echo "Done: $OUT"
