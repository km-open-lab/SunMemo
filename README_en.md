# ☀️ SunMemo

> **Hang your unfinished thoughts, tasks, and screenshots in the desktop sunlight.**  
> An organic, physics-driven clothesline productivity utility for macOS.

<p align="center">
  <a href="README.md">简体中文</a> &nbsp;·&nbsp; <strong>English</strong>
</p>

<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="SunMemo App Icon">
  <br><br>
  <strong>Local Data · No Accounts, No Analytics · Blazing Fast Native Swift · Compatible with macOS 13+ (Ventura / Sonoma / Sequoia)</strong>
  <br><br>
  <a href="https://github.com/km-open-lab/SunMemo/releases/latest"><strong>📦 Download Latest DMG (v1.1.0)</strong></a>
  &nbsp;·&nbsp;
  <a href="#-keyboard-shortcuts--gestures">Shortcuts</a>
  &nbsp;·&nbsp;
  <a href="#-build-from-source">Build from Source</a>
</p>

<p align="center">
  <img src="docs/images/demo_hero_clothesline.png" width="100%" alt="SunMemo Desktop Clothesline Banner">
</p>

---

## 🌟 Key Features

### ☀️ 1. Desktop Top Clothesline
- **Frictionless Glance**: Push your cursor against the top screen edge or press `⌃ ⌥ Space` — the clothesline glides down as light as a breeze.
- **Hand-Parting Playing Cards (Peeking)**: Hover over any card and it steps forward smoothly, while adjacent cards fan out and tilt slightly to the left and right like playing cards held in hand — eliminating scale distortion and card collisions.
- **Dynamic Adaptive Spacing**: Cards gently sway with the breeze; as items accumulate, spacing compresses gracefully (down to 45pt) to hold dozens of notes without overflow.

### 📝 2. Quick Memos, Multi-Aspect Ratios & Markdown Toolbar
<p align="center">
  <img src="docs/images/demo_quick_memo.png" width="560" alt="SunMemo QuickMemo Editor Modal">
</p>

- Press `⌃ ⌥ N` anywhere to summon a floating, lightweight note editor without interrupting your workflow.
- **Three Aspect Ratios**: Switch effortlessly between **Wide (`16:10`)**, **Square (`1:1`)**, and **Tall (`3:4`)** to fit horizontal code snippets, fleeting thoughts, or vertical checklists.
- **Full Markdown Formatting**: One-click insertion of `☑️ Todo Checklists`, `B Bold`, `• Bullet Lists`, and `H Headers`, with instant live switching between `Edit` and `MD Preview` modes.
- **Check Off Directly on the Rope**: Click `- [ ]` checkboxes directly on hanging cards without opening the editor. Progress bars update in real time.
- **Four Pastel Themes**: Warm Sunshine Yellow, Mint Green, Sakura Pink, and Sky Blue.

### 🔍 3. Single-Click Hero Preview & 1.3pt Catenary Tether Cord
<p align="center">
  <img src="docs/images/demo_preview_tether.png" width="800" alt="SunMemo Hero Preview with Tether">
</p>

- **Organic Physical Tethering**: Click any card to pull it down into a centered, full-screen hero preview. The top clothesline stays docked while an organic 1.3pt dual-tone catenary elastic cord connects the top wooden peg to the card's metallic eyelet ring.
- **Immersive Actions**: Interact with Markdown checkboxes, switch aspect ratios on the fly, copy the full text (`📋 Copy`), tear off to archive (`🗑 Tear Off`), or double-click to edit (`✎ Edit`). Press `Esc` or click the backdrop to tuck away smoothly.

### 📸 4. Screenshots & Clipboard Takeover
- Copy an image or text and press `⌃ ⌥ V` to pin it to the rope instantly.
- Click screenshots to preview with full detail, double-click to copy to clipboard, or long-press to open native macOS Markup tools for freehand sketching and annotations.

### 💾 5. Dual Markdown Persistence & Tear-Off Archiving
- **Read-only Markdown Export**: Whenever a memo changes, SunMemo exports every memo on the line, plus the archive, to `~/Documents/SunMemo.md`. The export is **one-way**: the file is rewritten each time, so edits made in it are overwritten and never reach SunMemo. Edit memos in SunMemo itself.
- **No Lost Drafts**: Text in the editor is kept as a draft as you type, and closing the editor or switching to another memo asks first. Memo files are written atomically, and a failed save is reported.
- **Timestamped Archive**: Tearing off a note never deletes it permanently; it is neatly appended to `# 📦 Archived Memos` with exact creation and tear-off timestamps.
- **Readable Anywhere**: Open the export in **Obsidian, Typora or VS Code** to read and search it; copy it first if you want to rework it.

### 🔄 6. Automatic Update Checks & Preferences
- Built-in GitHub Releases update checker notifies you unobtrusively in the menu bar whenever a new release arrives.
- Dedicated preferences panel lets you customize global hotkeys and toggle clipboard auto-hang.

### 🛡️ 7. Local-first, Private & Lightweight
- **Zero user accounts**, **zero tracking or analytics**, and **zero third-party SDKs**.
- **The only network access is the update check**: on by default, it asks the GitHub Releases API (`api.github.com`) for the latest version at launch and every 24 hours, and never uploads memos or screenshots. Turn it off in Preferences → Software Updates.
- Memos, screenshots and settings stay on your Mac. If iCloud Desktop & Documents is on, `~/Documents/SunMemo.md` syncs to iCloud along with the rest of Documents.

---

## ⌨️ Keyboard Shortcuts & Gestures

| Shortcut / Gesture | Action |
| :--- | :--- |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>␣</kbd> | **Reveal / Hide Clothesline** (Toggle the top clothesline down or up) |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> | **New Quick Memo** (Summon the floating note editor) |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>V</kbd> | **Hang Clipboard** (Pin copied text or image to the clothesline) |
| **Click Memo Card** | Open full-size hero preview connected by the suspension tether |
| **Click Todo Checkbox** | Toggle task status directly on the hanging card (`- [ ]` ↔ `- [x]`) |
| **Drag Card** | Drag into Slack, WeChat, Finder, or Obsidian to share; drag to Trash to discard |
| **Click Card × Button** | Tear off memo and archive it with timestamps in `SunMemo.md` |
| **Long Press Screenshot** | Open native macOS Markup tools (annotate, draw, sign) |

*Note: All global shortcuts can be customized in menu bar → Preferences.*

---

## 📦 Installation

### Option 1: Download DMG (Recommended)
1. Head over to [GitHub Releases](https://github.com/km-open-lab/SunMemo/releases/latest) and download `SunMemo-1.1.0.dmg`.
2. Open the DMG and drag **SunMemo.app** into your **Applications** folder.
3. Launch SunMemo and follow the quick onboarding guide.

### Option 2: Build from Source
Built with pure Swift, SwiftUI, and AppKit without requiring heavyweight Xcode project files. You can compile a universal binary (`arm64` + `x86_64`) directly via SwiftPM:

```sh
# Clone repository
git clone https://github.com/km-open-lab/SunMemo.git
cd SunMemo

# Build production app bundle
bash scripts/build-app.sh release

# Launch app
open build/SunMemo.app

# Package release DMG
bash scripts/make-dmg.sh
```

---

## 🛠️ Project Structure

```text
SunMemo/
├── Package.swift                    # SwiftPM package manifest
├── Sources/SunMemo/
│   ├── AppDelegate.swift            # Menu bar item, notification bus & app lifecycle
│   ├── Line.swift                   # Clothesline state model, wind physics & persistence
│   ├── LineView.swift               # Transparent overlay, catenary curve & peeking fan layout
│   ├── PeggedView.swift             # Clothed cards, in-place checkbox toggles & hover
│   ├── QuickMemoWindow.swift        # Floating memo modal, Markdown toolbar & aspect ratio pills
│   ├── MemoPreviewWindow.swift      # Hero preview modal with 1.3pt catenary suspension cord
│   ├── MemoAspectRatio.swift       # Wide (16:10), Square (1:1), Tall (3:4) ratio system
│   ├── MemoSyncManager.swift        # One-way, read-only Markdown export & tear-off archiving
│   ├── UpdateChecker.swift          # GitHub Releases auto-update checker & alert banner
│   ├── SettingsWindow.swift         # Global hotkey recorder & clipboard preferences
│   ├── WelcomeWindow.swift          # SwiftUI onboarding guide
│   ├── ClipboardWatcher.swift       # Smart clipboard monitoring & pinning
│   ├── HotKeyManager.swift          # Low-level Carbon global hotkey dispatcher
│   └── Resources/                   # Localization (English, 简体中文, Español)
├── scripts/
│   ├── build-app.sh                 # Universal binary build, icon generation & code signing
│   ├── make-dmg.sh                  # Automated disk image creation with Finder layout
│   ├── make-icon.swift              # App icon renderer using CoreGraphics / AppKit
│   └── inject-demo-data.swift       # Demo data generator for clean screenshots
└── LICENSE                          # MIT License
```

---

## 📄 License & Credits

- Licensed under the **MIT License**.
- Inspired by and rooted in the physical clothesline concept of Alejandro Buján's [Tendedero](https://github.com/alejandrobujan/tendedero).
- SunMemo introduces an entirely independent product identity, redesigned app icon, multi-aspect ratio memo system, interactive todo checklists, hand-parting playing cards animation, organic catenary suspension cord, dual Markdown persistence & archiving, and full localization.
