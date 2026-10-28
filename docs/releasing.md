# SunMemo 更新发布

从 1.3.0 起，应用使用 Sparkle 2.10.1 完成更新。旧客户端仍读取 GitHub latest API；新客户端读取最新 Release 的 `appcast.xml`，在应用内下载、校验、安装并重启。

## 密钥与构建

- `config/sparkle-public-key.txt` 只存公钥；私钥留在 macOS 登录钥匙串，account 为 `com.zhangkaiming.SunMemo`。不得提交或公开导出私钥。
- `scripts/build-app.sh release` 嵌入通用 Sparkle.framework，并由内向外签署 XPC、安装助手、框架及应用。
- `scripts/make-dmg.sh` 对应用与 DMG 分别公证并装订票据，随后调用 `scripts/make-appcast.py` 签署安装包和更新列表。若使用无 Finder UI 的独立打包路径，公证装订结束后也必须运行 `python3 scripts/make-appcast.py build/SunMemo-VERSION.dmg`。
- `CFBundleVersion` 必须高于上一个发布版。默认使用 Git 提交数；特殊构建可指定 `BUILD_NUMBER`，发布前须核对 appcast 与包内版本一致。不要重复使用已发布的构建号。

## 发布顺序

1. 更新 `VERSION`、中英文 README 及 `docs/releases/vVERSION.md`。
2. 运行回归，构建、签名、公证并验证 app 与 DMG。
3. 运行 `make-appcast.py`；该脚本先核对公钥，再签名并验证 DMG 和整个 appcast。签署后不得修改 XML 或安装包，否则必须重新签署。
4. 推送源码和版本标签。先创建 draft Release，上传 DMG、SHA-256 文件与 `appcast.xml`，全部齐全后再发布为 latest，避免客户端读取不完整更新。
5. 从公开 latest/download 地址回下载 feed 和 DMG，验证签名、摘要、版本号与下载地址。

1.2.2 及更早版本没有应用内安装能力，用户需手动安装一次 1.3.0。此后新版本仍需上传 `appcast.xml`；只上传 DMG 会使新客户端无法检查更新。

## 更新验收

`bash scripts/test-regressions.sh` 使用隔离便签和设置，覆盖编辑期间延迟重启、保存后恢复安装回调。

`scripts/regression/update-smoke-main.swift` 是独立测试应用的启动器，不属于生产 target。测试 bundle 使用 `com.zhangkaiming.SunMemo.UpdateSmoke`、单独的设置、回环 HTTP feed，更新后写出重启标记并退出，避免启动真实便签业务。测试 archive 保留生产应用的资源和框架，以测试启动器替换业务二进制；生产包另做严格签名、公证与内容核对。

验收必须覆盖：真实下载、安装替换、重启后标记；另外篡改 archive 后应拒绝安装且旧版保持不变。测试产生的 XML、包和标记均放在忽略的 `build/` 中，不能上传测试 feed。

自动检查继承旧版设置，后续由 Sparkle 保存偏好。关闭自动检查仍可手动检查；当前不默认启用后台静默安装。便签处于编辑状态时，安装重启等待保存或关闭。
