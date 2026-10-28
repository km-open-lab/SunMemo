#!/usr/bin/env python3
"""Create and sign the Sparkle feed for an already notarized release archive."""
import argparse
import datetime
import email.utils
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("archive", type=Path)
parser.add_argument("--app", type=Path, default=Path("build/SunMemo.app"))
parser.add_argument("--output", type=Path, default=Path("build/appcast.xml"))
parser.add_argument("--download-url")
args = parser.parse_args()
info = plistlib.loads((args.app / "Contents/Info.plist").read_bytes())
version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
tools = Path(".build/artifacts/sparkle/Sparkle/bin")
account = "com.zhangkaiming.SunMemo"
public_key = subprocess.check_output([str(tools / "generate_keys"), "--account", account, "-p"], text=True).strip()
if public_key != info["SUPublicEDKey"]:
    raise SystemExit("The app's update key does not match the signing key in Keychain")
signature = subprocess.check_output([str(tools / "sign_update"), "--account", account, "-p", str(args.archive)], text=True).strip()
ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", ns)
rss = ET.Element("rss", version="2.0")
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "SunMemo Updates"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = f"SunMemo {version}"
ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, f"{{{ns}}}version").text = build
ET.SubElement(item, f"{{{ns}}}shortVersionString").text = version
ET.SubElement(item, f"{{{ns}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
notes = Path(f"docs/releases/v{version}.md")
if notes.exists():
    ET.SubElement(item, "description", format="plain-text").text = notes.read_text()
url = args.download_url or f"https://github.com/km-open-lab/SunMemo/releases/download/v{version}/{args.archive.name}"
ET.SubElement(item, "enclosure", {
    "url": url, "length": str(args.archive.stat().st_size), "type": "application/octet-stream",
    f"{{{ns}}}edSignature": signature,
})
ET.indent(rss)
args.output.parent.mkdir(parents=True, exist_ok=True)
ET.ElementTree(rss).write(args.output, encoding="utf-8", xml_declaration=True)
subprocess.run([str(tools / "sign_update"), "--account", account, str(args.output)], check=True)
subprocess.run([str(tools / "sign_update"), "--account", account, "--verify", str(args.output)], check=True)
subprocess.run([str(tools / "sign_update"), "--account", account, "--verify", str(args.archive), signature], check=True)
print(f"Signed appcast for {version} ({build}): {args.output}")
