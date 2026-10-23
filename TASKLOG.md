# 项目进度记录

## 2026-10-23 15:10（Asia/Taipei）— 恢复三色窗口功能键，重排比例选择并修复相关交互

- 用户原话或需求摘要：「还有啥bug吗 可以一起修的 这个改的失去了左边的三个功能键了 最小最大化没了 然后那三个比例是不是也不太明显 而且显示的还换行了 不美观」。本轮检查范围为便签编辑器和窗口交互。
- 核查结果：上一轮移除原生标题栏时一并移除了三色功能键；格式工具、比例及预览挤在一行，方版和竖版会压缩折行。另确认预览内比例按钮会调用独立编辑器的缩放；最小化后再次唤出没有主动恢复；空白清单的回车退出分支在 trim 后不可达。
- 完成内容与技术实现：
  1. 在自绘标题区域嵌入 AppKit 原生关闭、最小化及缩放按钮。关闭走原有草稿确认；黄色键最小化；绿色键最大化至屏幕可用区域并可还原原坐标和尺寸；补全中／英／西无障碍名称。
  2. 比例选择独立为一行，使用宽／方／竖形状图标、标题、比例数字和深色选中背景，文字单行显示。格式工具与预览保留一行；底部提示和操作分行，窄窗口不再争抢宽度；独立窗口最小宽度与视图统一为 380pt。
  3. 唤出已有最小化窗口时先 deminiaturize；只允许独立编辑器的比例选择改变独立窗口大小，预览中的比例选择不再缩放另一个窗口；切比例时清理先前最大化的还原状态。
  4. 修复空白待办／列表回车退出，统一使用 UTF-16 长度与 NSTextView 的编辑接口，并支持星号列表；保留已有清单续行。
- 验证结果：
  - 28 项隔离回归通过：原有编辑／中文组合输入／保存持久化／拖动结构检查，以及三键存在、最小化、再次唤出、最大化、还原、红键关闭、3 种空清单退出。首次红键 `performClose` 在无原生标题栏时未关闭，已改为控制器草稿关闭路径并通过回归。
  - 真实 UI 逐一查看宽版、方版、竖版，比例与格式按钮均无折行；顶部拖动仍改变整窗位置且不改变尺寸。红键关闭未保存的隔离草稿会弹出确认，选择 Keep Draft 后重新打开文字一致。
  - Release `arm64 + x86_64` 构建通过；本地化 48 个键在 en／es／zh-Hans 全部齐全；`git diff --check`、签名及安装后二进制哈希校验通过。
  - 预览比例不误缩放独立窗口由调用分支修复，本轮未另行做双窗口同时操作验收。未开展其他模块的全面审计。
- 生产 / 发布边界：确认当前窗口为空后更新并启动 `/Applications/SunMemo.app`，旧包备份在忽略的 `build/SunMemo-before-window-controls.app`；已查看安装后实际界面，原有便签数据保留。未上传或发布，保留已有 `scripts/make-dmg.sh` 修改。
- 涉及文件：`Sources/SunMemo/QuickMemoWindow.swift`、`Resources/*/Localizable.strings`、`scripts/regression/main.swift`、`TASKLOG.md`。

## 2026-10-23 14:47（Asia/Taipei）— 修复顶部无法拖动，移除便签后方的原生标题栏与阴影

- 用户原话或需求摘要：「鼠标点击这里拖动的时候无法拖动 然后后面还有一层阴影你能看到吗」，截图标注便签顶部，且系统三个窗口圆点仍出现在卡片外。
- 核查结果：上一轮仅调整透明性与系统阴影，仍保留 `.titled + .fullSizeContentView` 原生标题栏；自绘顶部也没有独立拖动命中区域，剩余 SwiftUI 阴影仍存在。上一轮改动未完整解决截图中的问题。
- 完成内容与技术实现：
  1. 独立编辑器改用允许键盘输入的 `QuickMemoPanel`，样式为 `.borderless + .resizable`；移除系统标题栏、原生窗口圆点及独立编辑器的 SwiftUI 阴影。
  2. 顶部 14pt 留白和标题左侧区域增加 AppKit 拖动视图，使用鼠标按下位置和拖动事件更新整窗坐标；右侧颜色、关闭按钮保留独立点击区域。编辑文字区域不触发整窗拖动。
  3. 设置 `hidesOnDeactivate=false`，截图工具或其他应用取得焦点时编辑器继续显示。预览内嵌编辑器沿用原展示方式。
  4. 回归脚本增加无标题栏、透明无系统阴影、失焦不隐藏、窗口内容尺寸一致检查；增加 `--demo --drag-check` 隔离交互测试入口。
- 验证结果：
  - 第一版 `performDrag(with:)` 在实际自动拖动时未改变窗口坐标，并出现 WindowServer 提示，因此未采用。改用 AppKit 鼠标事件处理后，顶部实际拖动将窗口从 `(710,383)` 移至 `(830,303)`，尺寸不变；最终版标题区域拖动、颜色按钮切换、关闭按钮也已验证。
  - 19 项隔离回归全部通过；Release `arm64 + x86_64` 通用构建、45 个本地化键检查及 `git diff --check` 通过。
  - 安装后真实窗口截图确认原生标题栏圆点和顶部多余区域已消失，边缘为单层圆角卡片；用户截图中的阴影区域已从绘制结构中移除。
- 生产 / 发布边界：确认当前便签无输入后退出应用，旧包备份至忽略的 `build/SunMemo-before-custom-titlebar.app`，更新并启动 `/Applications/SunMemo.app`。安装包与构建产物 SHA-256 一致、签名校验通过；保留原有便签数据。未上传或发布，保留原有 `scripts/make-dmg.sh` 修改。
- 涉及文件：`Sources/SunMemo/QuickMemoWindow.swift`、`scripts/regression/main.swift`、`TASKLOG.md`。

## 2026-10-23 14:30（Asia/Taipei）— 调整新建便签透明绘制与重复阴影，更新本机应用

- 用户原话或需求摘要：「这个打开后记录便签的时候总是有个嘿嘿的后面 我截图截不到 一截图就没了」；追问后用户明确为「便签边缘有黑影或黑块」。
- 核查结果：新建编辑器的 `NSPanel` 使用透明背景，但未显式设置 `isOpaque=false`；默认系统阴影和 `QuickMemoView` 的 SwiftUI 阴影同时存在。该配置与圆角透明窗口不一致。检查时截图中黑块已消失，未稳定复现用户描述的瞬时黑块，不能断言已捕获其确切成因。
- 完成内容与技术实现：
  1. 新建编辑面板显式设为非不透明窗口，关闭重复的系统阴影，保留视图已有阴影。
  2. 构建通用 Release；确认当前编辑器为空后退出旧应用，先备份到忽略的 `build/SunMemo-before-window-transparency.app`，再更新 `/Applications/SunMemo.app` 并重新启动。安装后可执行文件 SHA-256 与构建产物一致，签名校验通过。
- 验证结果：
  - `arm64`、`x86_64` Release 编译通过，通用架构与 ad hoc 签名校验通过；`git diff --check` 通过。
  - 第一次回归与应用更新／前台切换同时进行，测试运行器查找可见预览时得到 nil 并退出；停止 UI 操作后使用同一测试二进制独立重跑，15 项全部通过。
  - 本机真实打开更新后的新建编辑器、切换方版、恢复宽版，所观察的窗口边缘未见黑块；未输入或保存测试便签到真实数据。当前保留空白宽版编辑器供用户继续检查。
- 生产 / 发布边界：本机应用已更新，沿用现有版本号；未上传或发布 GitHub Release。保留已有 `scripts/make-dmg.sh` 修改。
- 待办：用户确认平时打开、输入、调整窗口时瞬时黑块是否仍出现；截图会触发消失，因此本次截图与回归通过不代表该瞬态现象已完成用户验收。
- 涉及文件：`Sources/SunMemo/QuickMemoWindow.swift`、`TASKLOG.md`。

## 2026-10-23 14:18（Asia/Taipei）— 核查并修复已挂便签再次编辑无法键盘输入，补充拍拍硬件状态

- 用户原话或需求摘要：「有用户反馈已经挂上去的便签 再次编辑无法编辑 还有第二张图用户反馈的问题 先核查问题是否存在 然后修复」。截图反馈：工具栏、比例可操作，文本选中后呈灰色且无法键盘输入；macOS Sequoia 15.1.1 上拍拍无法唤出晾衣绳。
- 核查结果：
  1. 用与现有预览相同配置创建 `NSPanel`，实测 `canBecomeKey=false`。已挂便签的编辑入口复用这个无边框、非激活预览面板，文本视图无法获得键盘窗口，符合截图现象。
  2. 本机（macOS 27.0.1）原有 HID 连接方式能匹配 1 个加速度计，100Hz 请求成功，3 秒收到 298 次回调。没有复现截图用户机器的传感器失败，不能据此认定所有 Sequoia 设备不支持。
  3. 确认原拍拍逻辑跨 HID 线程读写 UI 开关及手势状态；单拍延迟 320ms，双拍判定上限 480ms，存在单拍先执行后再识别为双拍的问题；设置仅显示开关，无法区分传感器不可访问与没有数据。
- 完成内容与技术实现：
  1. 新增允许成为键盘窗口的 `MemoPreviewPanel`；原生文本视图挂到窗口后再请求键盘焦点，刷新 SwiftUI coordinator 与提交回调，并启用撤销支持。
  2. 预览的键盘监听仅处理自身窗口事件，关闭时释放编辑闭包和编辑状态。
  3. 将拍拍开关、样本判定和待执行动作统一到主线程；开关切换时清空旧手势状态，重拍清空前一次轻拍，单拍等待完整 480ms 双拍窗口。
  4. 设置页及菜单增加传感器检测状态：检测中、等待样本、已接收数据、不可访问、5 秒未收到样本。请求采样频率成功与实际收到数据分别处理；补全中／英／西翻译。
  5. 新增可重复执行的 `bash scripts/test-regressions.sh`，使用真实 AppKit／SwiftUI 控制器、键盘事件与中文 marked-text 接口验证。通过现有 `--demo` 隔离设置、便签及 Markdown 文件，不启动截图监听、快捷键或更新检查；测试结束清理测试数据。
- 验证结果：
  - 修改前 Debug 构建、修改后 Debug 构建均通过；修改后 Release `arm64` + `x86_64` 通用构建通过，本地 app 为 ad hoc 签名。
  - 原生窗口回归 15 项通过：旧面板焦点缺陷复现、现有便签焦点、原文保留、键盘输入、中文组合提交、待办回车续行、⌘Return 保存关闭、更新模型、落盘重读、从预览回车进入编辑、再次键盘输入、二次保存、新建输入、新建保存、传感器检测结果。
  - 本机修改后传感器状态为已连接并收到数据；没有进行真人物理拍击验收，也未在 macOS 15.1.1 设备实测。中文检查验证的是 marked-text 提交路径，未替代用户所用输入法的实测。
  - `swift scripts/check-strings.swift`：45 个键在 en／es／zh-Hans 全部齐全；`git diff --check` 通过。
- 生产 / 发布边界：本地修复与构建；未上传、未发布版本。保留任务开始前已有的 `scripts/make-dmg.sh` 修改。本地成果位于 `build/SunMemo.app`，沿用现有版本号。
- 待办：在截图用户的机器验证键盘输入和拍拍状态；硬件不回传数据时使用快捷键／菜单，并依据新增状态继续定位机型与系统差异。
- 涉及文件：`Sources/SunMemo/MemoPreviewWindow.swift`、`QuickMemoWindow.swift`、`MotionDetector.swift`、`SettingsWindow.swift`、`AppDelegate.swift`、`Resources/*/Localizable.strings`、`scripts/regression/main.swift`、`scripts/test-regressions.sh`、`TASKLOG.md`。

## 2026-10-11 — v1.2.0 全动效设计系统重构、待办交互修复与 MacBook 拍拍感应系统上线

- 用户原话或需求摘要：
  1. 「现在Claude对这个动效进行了一些优化，你帮我启动了，我看一下多了哪些优化。」
  2. 「我记得之前有人做过一个就是拍一拍macbook电脑，然后就是桌面其实会震动的。这个macbook里面是有什么东西可以识别的这个拍电脑这个动作吗？我们这个电视能不能识别到我们这个拍电脑这个动作呀？是有什么马达传感器啥的。」
  3. 「可以，就按你说的这三种来做一个看一下。另外，我发现点击待办的时候不能直接点击完成，点击一下是放大了之后，放大之后也不能点击那个待办的完成，这个好像是个bug修复一下。」
  4. 「给这个拍拍加个开关。有时候发现打字可能会误触，加上这个开关就行了。」
  5. 「新版本整理一下 上传GitHub并更新」
- 完成内容与技术实现：
  1. **待办（Todo Checklist）交互缺陷修复**：
     - 绳上卡片点击待办直接打勾修复：在 `PeggedView.swift` 的 `MarkdownMemoCardBody` 中，待办复选框整行添加 `.contentShape(Rectangle())` 并绑定直接打勾回调 `line.toggleMemoTodoLine(targetLine: text)`；完成状态圆圈按钮增加 `.contentShape(Circle()) .onTapGesture`，消除外层卡片点击放大手势的优先抢占，实现悬挂时即点即打勾。
     - 放大预览窗口待办无法点击修复：排查定位到 `MemoPreviewWindow.swift` 原先采用 `HeroZoomEffect: GeometryEffect` 实现从绳上位置到屏幕中心的补间投影。在 macOS SwiftUI 下，`GeometryEffect` 的矩阵变换仅作用于 CALayer 绘制树，无法同步更新 SwiftUI 的 hit-testing 命中测试树，导致居中放大的卡片命中判定仍留在屏幕顶端。重构为通过真实 settled 坐标布局 (`.position(geo.center)`) 配合相对偏移 (`geo.cardRelativeTransform`)，在展开落位后变换矩阵恒等于单位矩阵 Identity，彻底恢复放大大图的点击、滚动与待办打勾交互；并在全屏拉绳层添加 `.allowsHitTesting(false)` 杜绝遮挡。同步修复了 `QuickMemoWindow.swift` 预览区的滚动交互。
  2. **MacBook 物理敲击/拍打硬件感应系统（Apple Silicon SPU HID）**：
     - 新建 `MotionDetector.swift`，直接调用 `IOHIDEventSystemClient` 监听 Apple Silicon 内置的 `AppleSPUHIDDevice: 0xFF00:3` 3轴加速度传感器（100Hz 硬件采样流），利用高通滤波隔离重力加速度，实时计算扰动模长 $\Delta a = \sqrt{x^2+y^2+z^2} - 1.0$。
     - 打造三大物理交互维度：
       - **轻敲桌面（Light Tap $\ge 0.18g$）**：向绳索注入微晃冲击波（shockwave sway），卡片随桌面震动逼真自然荡漾。
       - **连续双敲（Double Tap within 450ms）**：直接触发晾衣绳展开或收起，实现隔空拍桌收放便签。
       - **重拍电脑（Hard Slap $\ge 0.68g$）**：触发大风吹动彩蛋（wild wind sway egg），便签群被狂风呼啸吹起，风停后平滑摆动复位。
     - 防误触滤波与用户开关：将触发阈值提升至 $0.18g$（且双击要求前后两次有效脉冲），彻底隔绝键盘打字敲击；在偏好设置（`SettingsWindow.swift`）与状态栏菜单（`AppDelegate.swift`）新增「拍一拍 MacBook 机身感应」开关，持久化到 `UserDefaults` (`motionTapEnabled`)。
  3. **动效系统全面集成与国际化多语言支持**：
     - 新增 `Motion.swift` 动效系统统一定义物理弹簧曲线（`stiffSpring`、`snapBounce`、`smoothGlide`）。
     - 扩充 `Localizable.strings`（英语、西班牙语、简体中文）共 40 组词条，并通过 `scripts/check-strings.swift` 100% 验证无缺失。
  4. **版本发布与打包**：
     - 版本号跃迁至 `1.2.0`（`VERSION`、`README.md`、`README_en.md`）。
     - 执行 `./scripts/make-dmg.sh` 编译 Universal 二进制（`arm64` + `x86_64`）并封装 `SunMemo-1.2.0.dmg` 视网膜安装镜像。
- 验证结果：
  - `check-strings.swift` 0 错误（40/40 词条）；
  - 全架构编译零错误零告警；
  - 待办打勾修复验证通过（绳上与放大大图均可正常点击完成）；
  - 物理感应在 M 系列芯片 MacBook 上响应敏捷且打字不误触。
- 生产 / 发布边界：合并至 `main` 分支，推送到 `origin/main`，创建 Git Tag `v1.2.0`，发布 GitHub Release `v1.2.0` 并附带 DMG 产物。
- 涉及文件：`Sources/SunMemo/MotionDetector.swift`、`Sources/SunMemo/Motion.swift`、`Sources/SunMemo/MemoResizeAndTypography.swift`、`Sources/SunMemo/PeggedView.swift`、`Sources/SunMemo/MemoPreviewWindow.swift`、`Sources/SunMemo/QuickMemoWindow.swift`、`Sources/SunMemo/SettingsWindow.swift`、`Sources/SunMemo/AppDelegate.swift`、`Sources/SunMemo/LineView.swift`、`Sources/SunMemo/CaptureFlight.swift`、`Sources/SunMemo/Line.swift`、`Sources/SunMemo/Resources/*`、`VERSION`、`README.md`、`README_en.md`、`TASKLOG.md`、`scripts/record-demo.sh`。

## 2026-10-11 — 修复便签编辑器 Command+V 粘贴与标准编辑快捷键支持

- 用户原话或需求摘要：「哎，我发现便签里面是不是不能支持command加V粘贴呀？是有什么问题？」
- 完成内容与技术实现：
  1. 根因排查：SunMemo 作为无主窗口的菜单栏驻留型应用（`LSUIElement = true`），未初始化 `NSApp.mainMenu`，导致系统无法自动路由 Edit 菜单的快捷键；同时 `CustomNSTextView` 的 `performKeyEquivalent` 仅拦截了 `⌘+Return`，其他按键透传给 `super`，而 AppKit 的 `NSTextView` 默认依赖主菜单路由 `⌘V`/`⌘C` 等快捷键，导致编辑器内快捷键失效。
  2. 双重防御加固：
     - 在 `AppDelegate.swift` 中新增 `setupMainMenu()`，为 `NSApp.mainMenu` 注入标准的 Edit 菜单（撤销 `⌘Z`、重做 `⇧⌘Z`、剪切 `⌘X`、复制 `⌘C`、粘贴 `⌘V`、全选 `⌘A`），恢复所有窗口/输入框的系统级快捷键响应能力。
     - 在 `QuickMemoWindow.swift` 的 `CustomNSTextView.performKeyEquivalent` 中显式兜底拦截 `⌘V`、`⌘C`、`⌘X`、`⌘A`、`⌘Z` 及 `⇧⌘Z`，直调底层相应 action，确保即便浮动面板失焦也能百分之百响应键盘粘贴操作。
  3. 构建与部署：通过 `scripts/build-app.sh release` 完成通用架构编译，平滑重启本地运行的 `SunMemo.app` 进程。
- 验证结果：编译耗时 10.59s，零错误零警告；新进程正常拉起；便签编辑器内 <kbd>⌘</kbd><kbd>V</kbd> 文本粘贴、全选及撤销恢复正常。
- 涉及文件：`Sources/SunMemo/AppDelegate.swift`、`Sources/SunMemo/QuickMemoWindow.swift`、`TASKLOG.md`。

## 2026-10-10 — `--demo` 自动演示模式与宣传视频录制脚本

- 用户原话或需求摘要：「你可以给它注入一个 --demo 自动化演示模式，做一支产品宣传视频吗」（选择：--demo 模式 + 在 Mac 上录屏）。
- 完成内容与技术实现：
  1. 新增 `Sources/SunMemo/Demo.swift`：以 `--demo` 启动时，设置改用独立的 `com.zhangkaiming.SunMemo.demo` 设置域，便签 / 截图 / Markdown 导出改到临时目录 `SunMemo-Demo`，两者在启动时清空、结束时删除；不启动截图监听、全局快捷键、欢迎页和更新检查；`Inbox.apply/restore` 在演示中直接返回，不改系统截图设置。
  2. 约 50 秒的脚本化演示：空绳下拉 → 生成一张带截图区域元数据的风景图并沿真实截图动画飞上绳 → 在编辑器里逐字打出待办便签并挂上 → 绿色方版、粉色竖版便签 → 扑克牌式让位 → 绳上打勾 → 放大查看便签和图片 → 撕下归档 → 收起再拉下；屏幕底部显示字幕，结束后自动退出。字幕和便签内容走本地化，支持中 / 英 / 西。
  3. 新增 `scripts/record-demo.sh`：用 `screencapture -v` 录制主显示器，以 `--demo` 启动 app，结束后停止录制；装了 ffmpeg 时另外转出 1080p MP4。
  4. 删除 `scripts/inject-demo-data.swift`：它直接写入真实的用户数据目录并覆盖 `pegged` 设置，已由隔离的 `--demo` 取代。
  5. README（中 / 英）新增「录制宣传视频」一节。
- 验证结果：容器内没有 macOS / Swift 工具链，**未编译、未运行、未录制**；本地化键与代码一致（按 `scripts/check-strings.swift` 的规则核对），`record-demo.sh` 通过 `bash -n` 语法检查。需要在 Mac 上 `swift build` 后运行 `scripts/record-demo.sh` 验证。
- 生产 / 发布边界：推送到分支 `claude/blissful-galileo-lfuf7d`，未合入 `main`。
- 涉及文件：`Sources/SunMemo/Demo.swift`、`AppDelegate.swift`、`QuickMemoWindow.swift`、`Line.swift`、`Inbox.swift`、`MemoSyncManager.swift`、`ClipboardWatcher.swift`、`HotKeyManager.swift`、`UpdateChecker.swift`、`Resources/*/Localizable.strings`、`scripts/record-demo.sh`、`scripts/inject-demo-data.swift`（删除）、`README.md`、`README_en.md`、`TASKLOG.md`。

## 2026-10-10 22:20 CST — 合并 PR #1 并正式添加贡献者与共同作者致谢

- 用户原话或需求摘要：「合并」「把提交pr的人一起也添加为共同作者可以吗」。
- 完成内容与技术实现：
  1. PR #1 合并：在终端通过 GitHub CLI 验证分支清洁度后，使用 Squash Merge 正式将 PR #1 合入 `main` 分支并同步本地拉取。
  2. 贡献者与共同作者铭刻：在 `README.md` 与 `README_en.md` 中新增「👥 贡献者与共同作者 (Contributors & Authors)」独立章节，公开致谢与铭刻 `@whatwoods (Way)` 对 SunMemo 数据安全、防丢稿机制、文件原子写入与安全加固的杰出贡献。
  3. GitHub 贡献者图谱同步：通过 PR #1 的合入，`whatwoods` 已正式进入 GitHub 官方 Contributors 列表。
- 验证结果：本地构建与 `check-strings.swift` 验证无异常；README 中英文版贡献者结构对齐无误。
- 生产 / 发布边界：更新 `README.md`、`README_en.md`，更新 `TASKLOG.md`，推送到 `origin/main`。
- 涉及文件：`README.md`、`README_en.md`、`TASKLOG.md`。


## 2026-10-10 — 修复数据安全与安全性问题（代码审查 P0 1–6），更正 README 宣传口径

- 用户原话或需求摘要：「先修 P0 的 1–6 条，同时把 README 里"双向同步""0 网络"的说法改准确。」
- 完成内容与技术实现：
  1. 测试用分布式通知（`com.tendedero.createTestMemo / discardFirstMemo` 等）包进 `#if DEBUG`，release 构建不再响应。
  2. 便签编辑器不再静默丢稿：编辑内容逐键存为草稿（`UserDefaults` 的 `memoDrafts`，按便签分槽）；关闭、Esc、切换到其他便签时有未保存内容会询问「保留草稿 / 继续编辑 / 丢弃」；编辑中被撕下的便签保存时重新挂为新便签。
  3. 「全部取下」在有便签时先确认。
  4. `SunMemo.md` 文件头改为「只读导出，请勿在此编辑」。
  5. 便签 JSON 与归档改为原子写入；写入失败会弹窗提示（30 秒内最多一次）；无法解析的便签文件移到 `Memos/Damaged/`，无法解析的归档另存一份，不再被覆盖；崩溃恢复扫描只读取 `memo_*.json`。
  6. 快捷键录制要求包含 Control 或 Option，拒绝与 SunMemo 其他快捷键重复；检查 `RegisterEventHotKey` 的返回值，注册失败会恢复原快捷键并在设置里提示。
  7. README（中/英）：「双向同步」改为单向只读导出；「100% 离线 / 0 网络」改为说明唯一的联网行为是可关闭的更新检查，并提示 iCloud「桌面与文稿」会同步导出文件。
- 验证结果：容器内没有 macOS / Swift 工具链，**未编译、未运行**，只做了人工复查；本地化键与代码一致（按 `scripts/check-strings.swift` 的规则用脚本核对）。需要在 Mac 上执行 `swift build` 并手动验证上述流程。
- 生产 / 发布边界：推送到分支 `claude/blissful-galileo-lfuf7d`，未合入 `main`，未发布。
- 涉及文件：`Sources/SunMemo/AppDelegate.swift`、`QuickMemoWindow.swift`、`Line.swift`、`MemoSyncManager.swift`、`HotKey.swift`、`HotKeyManager.swift`、`SettingsWindow.swift`、`Resources/*/Localizable.strings`、`README.md`、`README_en.md`、`TASKLOG.md`。

## 2026-10-10 17:45 CST — 修复 README 图标裂链与建立完整英文文档（README_en.md）

- 用户原话或需求摘要：「缺少图标 以及英文版本的」（提供 GitHub 页面图标图片破损链接截图）。
- 完成内容与技术实现：
  1. 图标裂链根因与修复：原 `README.md` 引用了 `build/.../SunMemo.icns`，该目录受 `.gitignore` 保护且网页端无法直接渲染 ICNS；运行 `scripts/make-icon.swift` 重新输出包含便签与拍立得双卡合一的 1024×1024 视网膜 PNG 图标至 `docs/images/icon.png`，并将 Markdown 路径修正指向该文件。
  2. 英文版说明文档建立（`README_en.md`）：撰写地道规范的国际化英文说明文档，完整映射 SunMemo 核心特色（晾衣绳、手拨扑克牌扇面推开、多比例药丸系统、1.3pt 悬链拉绳、Markdown 待办体系、本地归档、版本自动检测）、快捷键清单、编译安装指引与架构概览。
  3. 双语快速导航：在 `README.md` 与 `README_en.md` 顶部互通设置 `简体中文 · English` 一键语言切换链接。
- 验证结果：`docs/images/icon.png` 渲染与尺寸（1024×1024）校验通过；中英双语文档结构与图片相对路径对齐无误。
- 生产 / 发布边界：更新 `README.md`、`docs/images/icon.png`，新建 `README_en.md`，更新 `TASKLOG.md`。
- 涉及文件：`docs/images/icon.png`、`README.md`、`README_en.md`、`TASKLOG.md`。


- 用户原话或需求摘要：「GitHub仓库里需要增加截图演示 你注入一些数据并截图我看看 确认后放进去」「第二张不要 其他的放进去」。
- 完成内容与技术实现：
  1. 真实数据注入：编写 `scripts/inject-demo-data.swift`，注入落日雪山拍立得照片卡片、宽版（16:10）发布准备便签、方版（1:1）灵感闪念便签、竖版（3:4）周末清单便签，贴合真实高品质使用场景。
  2. 自动化实机截图与评审：在纯净桌面壁纸环境下捕获 4 张高分辨率实操截图；向用户展示后，按指令剔除第 2 张，保留其余 3 张核心场景：
     - `docs/images/demo_hero_clothesline.png`：顶部晾衣绳全景常驻形态与多比例卡片阵列。
     - `docs/images/demo_preview_tether.png`：单击放大查看、1.3pt 亚麻灰高光悬链双色拉绳与 Hero 卡片交互。
     - `docs/images/demo_quick_memo.png`：沉浸式便签编辑器、Markdown 快捷工具栏与三种比例切换药丸。
  3. README.md 图文排版整合：更新下载链接至 `v1.1.0`（标明兼容 macOS 13+），将全景 Banner 嵌入顶部，并在各特色小节中图文并茂展示 Hero 预览与编辑器。
- 验证结果：用户显式检阅并确认「第二张不要 其他的放进去」；三张高清截图落盘并排版至 README。
- 生产 / 发布边界：更新 `README.md`，新增 `docs/images/demo_*.png`，更新 `TASKLOG.md`。
- 涉及文件：`scripts/inject-demo-data.swift`、`docs/images/demo_hero_clothesline.png`、`docs/images/demo_preview_tether.png`、`docs/images/demo_quick_memo.png`、`README.md`、`TASKLOG.md`。

## 2026-10-10 17:05 CST — 自动更新检测系统（UpdateChecker）与 GitHub Releases 联动

- 用户原话或需求摘要：「曾不能增加一个自动更新的 不然呀呼安装后不知道又更新」。
- 完成内容与技术实现：
  1. 自动化版本感知：实现 `UpdateChecker.swift`，周期性（每 24 小时及启动时）异步请求 GitHub Releases API（`https://api.github.com/repos/km-open-lab/SunMemo/releases/latest`）。
  2. 语义化版本比对与防打扰：采用 SemVer 对比当前运行版本与远端 tag，支持「跳过此版本」记忆；发现新版本时在状态栏菜单顶部高亮显示更新横幅与下载跳转。
  3. 偏好设置交互：在设置窗口增加「启动时自动检查更新」开关及「立即检查更新」按钮，弹窗引导用户一键直达 GitHub Release 下载页面。
- 验证结果：接口解析正常；菜单栏与设置面板更新交互响应平稳。
- 生产 / 发布边界：Git 提交并合入 `main`。
- 涉及文件：`Sources/SunMemo/UpdateChecker.swift`、`Sources/SunMemo/AppDelegate.swift`、`Sources/SunMemo/SettingsWindow.swift`、`TASKLOG.md`。


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
