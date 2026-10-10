# 项目进度记录

## 2026-10-10 16:59 CST — 拓展支持 macOS Ventura 13.0+（含 13.5.2）系统兼容

- 用户原话或需求摘要：「这个系统的用户用不了 吗」（上传 macOS Ventura 13.5.2 系统版本截图）。
- 完成内容与技术实现：
  1. 根因排查：原项目 `Package.swift` 限制为 `.macOS(.v14)`，`scripts/build-app.sh` 编译参数为 `triple="...-macosx14.0"` 且 `Info.plist` 硬编码 `<key>LSMinimumSystemVersion</key><string>14.0</string>`，导致 macOS 13.x 用户运行或安装时系统抛出禁止图标并提示无法打开。
  2. 兼容性改造：
     - `Package.swift` 下调系统要求至 `.macOS(.v13)`。
     - 语法兼容：修复 5 处 SwiftUI 在 macOS 14 新增的双参数 `.onChange(of: value) { old, new in }` 闭包，改写为 macOS 13 完全兼容的单参数 `.onChange(of: value) { newValue in }`。
     - 构建与打包下调：`scripts/build-app.sh` 架构编译目标下调至 `arm64-apple-macosx13.0` 与 `x86_64-apple-macosx13.0`，`Info.plist` 的 `LSMinimumSystemVersion` 变更为 `13.0`。
- 验证结果：`otool -l` 检查二进制 Mach-O Header，双架构 `minos` 与 `sdk` 均确认为 `13.0`；通用架构构建（Universal Binary）通过；`scripts/make-dmg.sh` 重新产出全面支持 macOS 13+ 的 `SunMemo-1.1.0.dmg`。
- 生产 / 发布边界：Git 提交并推送至 `origin/main`；GitHub Release `v1.1.0` 已覆盖上传更新后的 DMG 资源。
- 涉及文件：`Package.swift`、`Sources/SunMemo/LineView.swift`、`Sources/SunMemo/PeggedView.swift`、`scripts/build-app.sh`、`TASKLOG.md`。

## 2026-10-10 16:55 CST — 建立项目进度记录（TASKLOG.md）与动态版本号构建机制

- 用户原话或需求摘要：「在项目里加一个Tasklog吧记录我要求了什么 改了什么 看看练境那个项目的tasklog咋写的 把之前的补上 然后每次更新是不是需要增加版本号」。
- 完成内容与技术实现：
  1. 项目全生命周期回溯审计：参考 `neurolift-pro`（练境）项目的 TASKLOG 治理规范，按「用户原话或需求摘要 / 完成内容与技术实现 / 验证结果 / 生产与发布边界 / 涉及文件」严格结构建立 `TASKLOG.md`，完整回补从 v1.0.0 正式发布到历次界面、动效、拉绳、比例系统的 7 个里程碑记录。
  2. 版本治理与自动化构建规范：确立 macOS 桌面应用版本递增规范。在项目根目录建立 `VERSION` 作为单一真相来源（升级至 `1.1.0`）；重写 `scripts/build-app.sh`，动态读取 `VERSION` 文件注入 `CFBundleShortVersionString`，并由 Git 提交总数自动生成自增的 `CFBundleVersion`，确保每次构建具备单调递增性与可追溯性。
- 验证结果：`TASKLOG.md` 语法校验无异常；`VERSION` 文件（`1.1.0`）生效；打包流水线动态回读版本。
- 生产 / 发布边界：本地文件新增 `TASKLOG.md`、`VERSION`，修改 `scripts/build-app.sh`。
- 涉及文件：`TASKLOG.md`、`VERSION`、`scripts/build-app.sh`。

## 2026-10-10 16:45 CST — 手拨扑克牌扇面让位、伸缩绳精细重塑与多比例便签系统（方案 B + 思路 1）

- 用户原话或需求摘要：「1按方案 B：手拨扑克牌『扇面推开 / Peeking 让位』修改；2关于『晾衣绳不好看』这说的是我们做的伸缩绳不好看，不是原来的晾衣绳；3按思路 1（便签比例支持用户自行调整）。」
- 完成内容与技术实现：
  1. 动效重塑（方案 B）：彻底移除生硬卡顿的 Dock 鱼眼缩放，改为 120Hz 丝滑物理手拨扑克牌让位（`peekingTransform`）。悬停卡片保持 1:1 尺寸不放大失真，微迈半步（`yOffset: 8pt`，`zIndex: 1000`）；左侧相邻卡片依距离优雅向左推开让位（`±28pt`、`±14pt`、`±5pt`）并伴随 `-2.2°`、`-1.2°` 扇形侧倾；右侧相邻卡片同理向右推开；末尾「+」号按钮联动右推，整条绳子呈现指尖拨动扑克牌的自然物理手感。
  2. 伸缩拉绳精细重塑：重构预览展开时的牵引系统，彻底告别原先突兀的粗黑硬线与上下双大木夹。拉绳细化为 `1.3pt` 亚麻灰高光双色超细自然悬链曲线（Catenary Cubic Bezier）；绳端顶部固定于 `13×24pt` 迷你小木夹；卡片端采用微型金属吊环（`7pt`）与轻量化固定夹（`18×36pt` `SuspensionPeg`），拉绳自然穿环咬合，还原轻盈、松弛、被轻柔牵引的物理呼吸感。
  3. 便签多比例系统（思路 1）：新增 `MemoAspectRatio` 体系，支持宽版（`wide` 16:10，默认）、方版（`square` 1:1）与竖版（`tall` 3:4）。在输入窗口增加 `[▭ 宽版] [□ 方版] [▯ 竖版]` 药丸切换器并支持窗口平滑动画缩放；绳上卡片动态计算对应宽高；右键菜单新增「切换比例」子菜单；大图预览顶部内置实时比例切换器，伴随弹簧阻尼自适应伸缩变形并持久化至 JSON。
- 验证结果：`swift build` 编译通过（耗时 4.10s，0 错误 0 警告）；`scripts/build-app.sh release` 构建通用架构产物（arm64 + x86_64）；`scripts/make-dmg.sh` 产出 `build/SunMemo-1.0.0.dmg`；本地 `SunMemo.app` 自动重启并实测手拨让位、拉绳外观及三种比例无缝切换无异常。
- 生产 / 发布边界：Git 提交为 `ef46f1c feat: playing card peeking parting animation, refined suspension cord, and multi-aspect ratio memos`，已推送至 `origin/main`；Release `v1.0.0` 中的 DMG 资源已通过 `gh release upload --clobber` 更新替换。
- 涉及文件：`Sources/SunMemo/MemoAspectRatio.swift`、`Sources/SunMemo/Line.swift`、`Sources/SunMemo/LineView.swift`、`Sources/SunMemo/PeggedView.swift`、`Sources/SunMemo/QuickMemoWindow.swift`、`Sources/SunMemo/MemoPreviewWindow.swift`、`Sources/SunMemo/AppDelegate.swift`。

## 2026-10-10 16:23 CST — 截图卡片交互对齐（单双击）、预览保持晾衣架展开与宽屏伸缩拉绳

- 用户原话或需求摘要：「图片逻辑要和便签一致 单击放大 双击复制」「还有查看的时候不应该收起晾衣架 甚至可以有个伸缩绳的感觉与晾衣绳一直在牵着这种感觉 松弛的感觉」「晾衣绳上是宽屏比例 拿下来变竖屏 不舒服」。
- 完成内容与技术实现：
  1. 截图卡片与便签交互对齐：`GrabArea` 中将截图点击重构为单击呼出 Hero 大图预览，双击执行复制到剪贴板并弹出「已复制 ✓」气泡反馈。
  2. 预览常驻防收起：在 `AppDelegate.tick()` 中接入 `MemoPreviewWindowController.shared.isOpen` 状态感知，大图查看期间晾衣绳常驻展开，不再因鼠标移出屏幕顶部而收起。
  3. 宽屏比例预览：便签大图卡片采用与绳上相同的宽屏比例（`510×320`），避免“宽屏便签拿下来变竖屏”的撕裂感。
  4. 伸缩拉绳原型接入：在晾衣绳与下拉放大的卡片之间绘制牵引拉绳，建立拉出预览的物理从属感。
- 验证结果：截图单击展开大图、双击复制图片通过；查看图片/便签期间晾衣绳稳定吸顶展开；Esc / 空白处点击正常收起。
- 生产 / 发布边界：Git 提交 `30cf0b0`，推送至 `origin/main`。
- 涉及文件：`Sources/SunMemo/GrabArea.swift`、`Sources/SunMemo/PeggedView.swift`、`Sources/SunMemo/AppDelegate.swift`、`Sources/SunMemo/MemoPreviewWindow.swift`、`Sources/SunMemo/Line.swift`、`Sources/SunMemo/LineView.swift`。

## 2026-10-10 16:13 CST — 新便签发射抛物线飞行挂绳动效、大图沉浸查看与拍立得双卡图标

- 用户原话或需求摘要：「我们的便签挂上没有动画诶 请沿用系统截图那个挂到晾衣绳上 的动画 展开也是如此」「便签单击查看大图 就是一个完整的便签 双击点进去才是编辑 先讨论讨论 另外这个图标现在是挂了俩便签 能不能把右边那个改成照片的感觉」。
- 完成内容与技术实现：
  1. 便签抛物线发射挂绳动画：实现 `hangMemoFlight`，便签保存后从编辑器原位截取快照，以三次抛物线平滑飞向晾衣绳上的目标卡槽位，落地后无缝替换为真实交互卡片，并伴随木夹咬合声音。
  2. Hero 预览大卡片（`MemoPreviewWindow`）：单击卡片从绳上位移形变展开为全屏居中大图；支持 Markdown 待办勾选、一键复制全文、快速归档、双击/回车继续编辑，Esc/空白收起。
  3. 拍立得照片应用图标重塑：更新 `scripts/make-icon.swift`，右侧卡片由纯色便签改为经典拍立得相纸（雪山晴空、高光覆膜质感、下部留白与木夹咬合），凸显“便签+截图”双核心定位。
- 验证结果：便签发射飞行轨迹与截图捕获一致，飞行到位准确定位到绳上目标点；图标多尺寸渲染与 ICNS 重建成功。
- 生产 / 发布边界：Git 提交 `fc34756`，推送至 `origin/main`。
- 涉及文件：`scripts/make-icon.swift`、`Sources/SunMemo/AppDelegate.swift`、`Sources/SunMemo/Line.swift`、`Sources/SunMemo/MemoPreviewWindow.swift`、`Sources/SunMemo/PeggedView.swift`、`Sources/SunMemo/QuickMemoWindow.swift`。

## 2026-10-10 15:55 CST — DMG 安装盘镜像布局重构与 Retina 安装指引对齐

- 用户原话或需求摘要：「这个需要指示 把图标拖到文件里」。
- 完成内容与技术实现：
  1. 盘符背景指引图绘制：更新 `scripts/make-dmg-background.swift`，生成 Retina 双倍分辨率 `background.tiff`，居中绘制指示箭头与高可读性中文指引「拖移 SunMemo 到 Applications 安装使用」。
  2. Finder 挂载视口与图标绝对定位：调整 `scripts/make-dmg.sh` 中的 AppleScript 坐标，确保左侧 SunMemo.app 图标（x: 175, y: 190）与右侧 Applications 替身（x: 485, y: 190）精确对准背景插图。
  3. 挂载卷名防冲突：修复多次挂载打包时出现 `SunMemo 1` 卷名叠加导致的 AppleScript 注入失败问题。
- 验证结果：本地挂载 DMG 验证视口尺寸 `660×400`、图标大小 128pt、隐藏状态栏/工具栏与安装指引完美契合。
- 生产 / 发布边界：Git 提交 `91a7848`，推送至 `origin/main`。
- 涉及文件：`scripts/make-dmg.sh`、`scripts/make-dmg-background.swift`、`Sources/SunMemo/WelcomeWindow.swift`。

## 2026-10-10 15:37 CST — 菜单栏收纳（更多子菜单）与 ⌃⌥Space 快捷键注册修复

- 用户原话或需求摘要：菜单栏堆叠过多项目，快捷键在部分系统环境下偶现不响应；推文与功能页排版优化（减少不必要 emoji，去掉冗长快捷键清单，优化排版换行）。
- 完成内容与技术实现：
  1. 菜单流线化收纳：将次要选项归入「更多」二级子菜单，主菜单精简至核心便签与状态操作。
  2. 快捷键监听强化：`HotKeyManager` 强化对 `Control + Option + Space` 全局热键的抢占式注册与防冲突兜底。
  3. 文案与宣传页润色：更新营销推文与功能说明，去除生硬列点与多余 emoji，提升阅读体感。
- 验证结果：状态栏菜单视觉干净精炼，全局快捷键随按随唤起。
- 生产 / 发布边界：Git 提交 `6035c88`，打上 `v1.0.0` 初始版本标签。
- 涉及文件：`Sources/SunMemo/AppDelegate.swift`、`Sources/SunMemo/HotKeyManager.swift`、`Sources/SunMemo/KeyHelper.swift`。

## 2026-10-10 15:32 CST — 状态栏自定义晾衣绳便签模版图标重构

- 用户原话或需求摘要：原生太阳图标辨识度不够强，需要更具辨识度、能直观体现“晾衣绳便签”产品心智的状态栏图标。
- 完成内容与技术实现：
  1. 状态栏 Template 图标绘制：使用 CoreGraphics 原生绘制 `20×18pt` 模版图标，呈现微微下垂的晾衣绳与两张挂着的微型卡片夹。
  2. 暗色/浅色自适应：标记为 `isTemplate = true`，随 macOS 系统菜单栏自动反色。
- 验证结果：菜单栏在暗黑模式与浅色模式下清晰锐利，无模糊失真。
- 生产 / 发布边界：Git 提交 `d6e88cf`。
- 涉及文件：`Sources/SunMemo/AppDelegate.swift`、`Sources/SunMemo/LineView.swift`、`Sources/SunMemo/SettingsWindow.swift`、`Sources/SunMemo/WelcomeWindow.swift`。

## 2026-10-10 15:28 CST — SunMemo (晾想法) v1.0.0 正式发布与全面重构

- 用户原话或需求摘要：将原开源项目 Tendedero 全面重构升级为中文原生独立产品 **SunMemo (晾想法)**，集成便签、Markdown、待办清单、双向同步与独立品牌。
- 完成内容与技术实现：
  1. 品牌全面重构：由 Tendedero 重构并命名为 SunMemo（晾想法），更新包名、Bundle ID `com.zhangkaiming.SunMemo`、仓库组织 `km-open-lab/SunMemo`。
  2. 便签与待办核心：引入 `QuickMemoWindow`（支持 Markdown、Todo Checklist `- [ ]`、回车自动续接、⌘+Enter 快捷提交）。
  3. 桌面晾衣绳融合：便签与截图并排挂绳，支持随风微风摇摆（`gust`）、轻拉撕下归档、声音音效。
  4. 双向文件同步：内置 `MemoSyncManager`，自动同步本地 Markdown 备份。
  5. 自动化构建体系：建立完整的 `build-app.sh` 编译签名与 `make-dmg.sh` 自动打包脚本。
- 验证结果：SwiftPM 单 target 编译通过，应用签名就绪，本地双击运行通过。
- 生产 / 发布边界：Git 提交 `7128eb4`，正式开源发布。
- 涉及文件：`Package.swift`、`README.md`、`Sources/SunMemo/` 全套源码、`scripts/` 打包套件。
