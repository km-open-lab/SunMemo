# ☀️ SunMemo · 晾想法

> **把未完成的想法与待办，晾在桌面阳光下。**  
> An elegant macOS clothesline for your thoughts, to-do lists, and screenshots.

<p align="center">
  <img src="build/SunMemo.app/Contents/Resources/SunMemo.icns" width="128" height="128" alt="SunMemo App Icon">
  <br><br>
  <strong>纯本地 · 离线隐私 · 极速流畅 · 专为 macOS 14+ 打造</strong>
  <br><br>
  <a href="https://github.com/zhangkaiming2579-dev/SunMemo/releases/latest"><strong>📦 下载最新 DMG 安装包 (v1.0.0)</strong></a>
  &nbsp;·&nbsp;
  <a href="#-快捷键与操作手势">快捷键一览</a>
  &nbsp;·&nbsp;
  <a href="#-源码编译-build-from-source">源码编译</a>
</p>

---

## 🌟 核心特色 (Features)

### ☀️ 1. 桌面顶部晾衣绳 (Top Clothesline)
- 鼠标悬停屏幕顶部边缘或按快捷键 `⌃ ⌥ ␣`，晾衣绳如羽毛般丝滑滑下。
- **动态自适应扇面叠放**：便签较少时自然舒展分布（间距 205pt）；便签增多时，卡片智能压缩间距（最低 45pt）并自然叠放，告别卡片溢出。
- **悬停高亮聚焦**：光标划过任意卡片即刻 1.05x 微缩放并跃至最顶层渲染，看清每一个待办细节。

### 📝 2. 便签速记与交互待办清单 (Interactive Todos & Notes)
- 按 `⌃ ⌥ N` 随时呼出原生独立便签弹窗，不打断手头工作。
- **完整 Markdown 工具栏**：支持一键插入 `☑️ 待办清单`、`B 粗体`、`• 无序列表`、`H 标题`，支持 `编辑 / MD 预览` 双模式实时切换。
- **绳上直接打勾**：无需点开编辑，直接在悬挂卡片上点击 `- [ ]` 待办复选框，即刻打勾并实时统计完成进度。
- **多色卡片主题**：支持暖阳黄、薄荷绿、樱花粉、晴空蓝四种清爽便签色彩。

### 📸 3. 截图与剪贴板接管 (Screenshots & Clipboard)
- 截屏或复制图片/文字后，按 `⌃ ⌥ V` 即可瞬间挂上晾衣绳。
- 可选接管 macOS 截图保存位置，截图瞬间自动上绳，桌面彻底告别杂乱文件堆积。

### 💾 4. 本地实时 Markdown 同步与防丢归档 (Dual Markdown Persistence)
- **永远不怕数据丢失**：所有在绳便签实时双向同步至用户文稿目录 `~/Documents/SunMemo.md`。
- **撕下便签带时间戳归档**：点击卡片右上角撕下便签后，绝不从文档物理抹去，而是自动沉淀至 `# 📦 历史已撕下便签归档`，精确记录创建时间与撕下时间戳。
- 与 **Obsidian、Typora、VS Code、macOS 备忘录** 无缝配合，随时检索回顾。

### ⚙️ 5. 自定义全局快捷键与防误触 (Preferences & Shortcuts)
- 专属偏好设置面板，支持在界面中按下任意组合键，一键自定义录制全局快捷键。
- 支持剪贴板自动挂绳防误触开关，避免误把普通图片或隐私内容挂上绳。

### 🛡️ 6. 纯本地安全与隐私保护 (100% Offline & Private)
- **0 网络权限**、**0 用户跟踪**、**0 账号体系**。
- 所有文字、截图与配置文件 100% 留存在你的 Mac 本机。

---

## ⌨️ 快捷键与操作手势

| 操作 | 动作说明 |
| :--- | :--- |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>␣</kbd> | **呼出 / 收起晾衣绳**（下拉或隐藏顶部便签绳） |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>N</kbd> | **弹出速记窗口**（写想法、列待办） |
| <kbd>⌃</kbd>&thinsp;<kbd>⌥</kbd>&thinsp;<kbd>V</kbd> | **挂上剪贴板内容**（将截图或复制的文本挂上绳） |
| **单击便签卡片** | 弹出便签大窗口进行查看与二次编辑 |
| **单击待办复选框** | 在卡片上直接勾选或取消待办事项（`- [ ]` ↔ `- [x]`） |
| **拖动卡片** | 拖拽至飞书、微信、访达、Obsidian 即刻分享；拖至废纸篓撕下丢弃 |
| **点击卡片右上角 ×** | 撕下便签，并在本地 `SunMemo.md` 中自动归档记录撕下时间 |
| **长按图片卡片** | 开启 macOS 原生 Markup（标记画笔涂鸦） |

*注：以上所有全局快捷键均可在菜单栏「偏好设置与快捷键...」中任意修改。*

---

## 📦 下载与安装 (Installation)

### 方式 1：直接下载 DMG 安装包（推荐）
1. 前往 [Releases 页面](https://github.com/zhangkaiming2579-dev/SunMemo/releases/latest) 下载最新版本的 `SunMemo-1.0.0.dmg`。
2. 双击打开 DMG，将 **SunMemo.app** 拖动至 **Applications** 文件夹即可。
3. 首次启动时，SunMemo 会弹出欢迎与使用引导卡片，按指引开启即可畅享。

### 方式 2：源码编译 (Build from source)
项目采用纯 Swift + SwiftUI + AppKit 构建，无需安装庞大的 Xcode 完整工程即可直接用 SwiftPM 构建通用架构（Universal Binary: Apple Silicon + Intel）：

```sh
# 克隆仓库
git clone https://github.com/zhangkaiming2579-dev/SunMemo.git
cd SunMemo

# 编译并生成 SunMemo.app
bash scripts/build-app.sh release

# 运行应用
open build/SunMemo.app

# 打包 DMG 安装盘
bash scripts/make-dmg.sh
```

---

## 🛠️ 项目结构与技术架构

```text
SunMemo/
├── Package.swift                    # SwiftPM 项目清单
├── Sources/SunMemo/
│   ├── AppDelegate.swift            # 状态栏菜单、全局通知分发与生命周期
│   ├── Line.swift                   # 晾衣绳核心模型、数据持久化与微风摆动物理模拟
│   ├── LineView.swift               # 顶部透明画板、绳索抛物线几何与动态扇面叠放布局
│   ├── PeggedView.swift             # 便签卡片视图、交互复选框点击、悬停放大聚焦
│   ├── QuickMemoWindow.swift        # 原生独立速记弹窗、Markdown 工具栏与色彩切换
│   ├── MemoSyncManager.swift        # 本地 Markdown 双向持久化与撕下时间戳归档
│   ├── WelcomeWindow.swift          # 新版 SwiftUI 欢迎使用与引导弹窗
│   ├── SettingsWindow.swift         # 快捷键自定义录制与防误触管理
│   ├── ClipboardWatcher.swift       # 智能剪贴板监听与一键上绳
│   ├── HotKeyManager.swift          # Carbon 全局热键底层监听与分发
│   └── Resources/                   # 多语言本地化支持 (简体中文, English, Español)
├── scripts/
│   ├── build-app.sh                 # 通用二进制架构编译与签名脚本
│   ├── make-dmg.sh                  # 磁盘映像 DMG 自动化打包与 Finder 布局排版
│   ├── make-icon.swift              # 用纯 CoreGraphics / AppKit 绘制 1024x1024 渐变图标
│   └── make-dmg-background.swift    # DMG 视网膜安装背景图生成脚本
└── LICENSE                          # MIT 开源协议与版权声明
```

---

## 📄 开源许可与致谢 (License & Credits)

- 本项目基于 **MIT License** 开源。
- 灵感与基础物理摆动渲染来源于 Alejandro Buján 的优秀作品 [Tendedero](https://github.com/alejandrobujan/tendedero)。
- SunMemo 按照上游许可证要求，使用了完全独立的全新品牌命名、独立设计的暖阳便签图标（`scripts/make-icon.swift`）、重构优化的多色便签速记体系、交互式待办清单系统、扇面自适应叠放算法、全新的 SwiftUI 引导界面以及 `SunMemo.md` 本地双向防丢归档系统。
