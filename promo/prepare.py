#!/usr/bin/env python3
"""Turns a clean take of the --demo tour into footage for the promo.

Usage: python3 promo/prepare.py [zh-Hans|en]

Reads build/SunMemo-demo-<language>.mov and its markers (recorded with
CLEAN=1 scripts/record-demo.sh <language>), finds the cut from black that
marks time zero, and writes:
  promo/public/clips/screen-<language>.mp4  the tour from time zero, cut to
      the area below the menu bar and above the Dock
  promo/src/data/tour-<language>.json        the markers and that geometry
"""
import json
import os
import re
import subprocess
import sys

lang = sys.argv[1] if len(sys.argv) > 1 else "zh-Hans"
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
take = os.path.join(root, "build", f"SunMemo-demo-{lang}.mov")
markers_path = os.path.join(root, "build", f"SunMemo-demo-{lang}.markers.jsonl")
clips = os.path.join(root, "promo", "public", "clips")
data = os.path.join(root, "promo", "src", "data")
os.makedirs(clips, exist_ok=True)
os.makedirs(data, exist_ok=True)

marks = [json.loads(line) for line in open(markers_path) if line.strip()]
start = next(m for m in marks if m["event"] == "start")
scale = start["scale"]
vx, vy, vw, vh = start["visible"]
crop = [round(v * scale) for v in (vx, vy, vw, vh)]
crop = [c - c % 2 for c in crop]

# Time zero: the first bright frame after the black backdrop. Average
# brightness, so a dialog over the black does not count as the picture.
probe = subprocess.run(
    ["ffmpeg", "-hide_banner", "-t", "45", "-i", take,
     "-vf", f"crop={crop[2]}:{crop[3]}:{crop[0]}:{crop[1]},scale=320:-2,signalstats,"
            "metadata=print:key=lavfi.signalstats.YAVG",
     "-an", "-f", "null", "-"],
    capture_output=True, text=True)
times = [float(x) for x in re.findall(r"pts_time:([\d.]+)", probe.stderr)]
levels = [float(x) for x in re.findall(r"YAVG=([\d.]+)", probe.stderr)]
sync = None
dark_since = None
for t, y in zip(times, levels):
    if y < 24:
        dark_since = t if dark_since is None else dark_since
    elif y > 80:
        if dark_since is not None and t - dark_since > 0.5:
            sync = t
            break
        dark_since = None
if sync is None:
    sys.exit("No cut from black found in the take.")
end = next(m["t"] for m in marks if m["event"] == "end")
print(f"time zero at {sync:.3f}s in the take; tour {end:.2f}s")

out = os.path.join(clips, f"screen-{lang}.mp4")
subprocess.run(
    ["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{sync:.3f}", "-t", f"{end + 0.5:.3f}", "-i", take,
     "-vf", f"crop={crop[2]}:{crop[3]}:{crop[0]}:{crop[1]},fps=60",
     "-c:v", "libx264", "-preset", "medium", "-crf", "15", "-g", "30", "-pix_fmt", "yuv420p",
     "-movflags", "+faststart", "-an", out],
    check=True)

json.dump({
    "language": lang,
    "screen": start["screen"],
    "visible": start["visible"],
    "scale": scale,
    "footage": [crop[2], crop[3]],
    "markers": [m for m in marks if m["event"] != "start"],
}, open(os.path.join(data, f"tour-{lang}.json"), "w"), indent=1)
print(f"wrote {out}")
