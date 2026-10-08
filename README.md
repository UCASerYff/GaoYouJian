# 搞邮件

原生 macOS 邮箱客户端，当前正式版本 V1.08。要求 Apple Silicon、macOS 14+。

功能包括 IMAP / SMTP 收发、Google / Microsoft OAuth、邮箱身份分类、手动关联网站与 App、历史记录、附件、草稿、资料备份和 CSV 导入导出。没有内置真实账户或共享 OAuth 客户端身份。

[下载安装包](https://github.com/UCASerYff/GaoYouJian/releases/latest) · [源代码](https://github.com/UCASerYff/GaoYouJian)

原生悬浮窗统一显示所有账号的缓存未读数、可选最近三封未读预览，以及收件箱 / 同步 / 写信入口。V1.08 移除“全部邮箱”选择栏及独立空白顶部，卡片直接从未读统计开始。顶部固定 80 pt 的统计区整块可原生拖动，不随下面的正文滚动；点击单封预览仍会定位其所属账号和邮件。

平时只显示淡紫色竖线，鼠标移入展开，移出快速收起，点击其他位置立即收起。拖动统计区或隐藏竖线可自由移动，靠近左右屏幕侧边 32 pt 内才自动吸附，松手保存位置。自由位置收起后，竖线仍留在原位置；再次展开和重启沿用记录。统计区下面保留预览、状态和业务按钮，长内容或小屏幕可滚动，卡片高度随内容调整。

悬浮窗不显示软件图标、名称、标题文字和版本号。预览、透明度及重置位置统一放在独立设置窗口；旧版固定 / 紧凑偏好保留但不再读取。默认隐藏邮件预览，展开悬浮窗不会将邮件标为已读。从菜单栏信封、工具栏或 ⌃⌘M 启用和隐藏悬浮窗。V1.07 引入的自由移动、近边吸附、淡紫隐藏条及真实圆角命中继续保留。

本版保留既有资料目录、偏好设置及钥匙串服务，资料格式不变，升级后直接读取原有记录。悬浮窗设置使用独立的本机偏好键，不改变原有资料格式。

## 文件

- `Sources/`：SwiftUI / AppKit 界面、资料存储、Keychain、OAuth、邮件传输和 C libcurl 桥接。
- `Assets/`：正式图标和设计记录。
- `Docs/`：OAuth 配置及验证记录。
- `Tests/`：模型、OAuth 和隔离的 TLS 邮件服务器测试。
- `Scripts/`：构建、安装、图标转换和版本更新。
- `Release/`：只保留当前正式 DMG 和 SHA-256。

## 构建和安装

需要 macOS 自带开发工具及可用的 Xcode SDK。没有第三方 Swift 包或 Node 依赖。

```sh
./Scripts/build.sh
./Scripts/install.sh
```

首次版本固定 1.00。下次正式发布前运行 `python3 Scripts/bump_version.py`，使用十进制加 0.01。调试和重建不递增版本。

构建在 `/private/tmp` 创建自己的临时目录，结束后清理。正式更新前安全备份并核验资料、设置和全部附件；资料格式不变时继续使用原数据路径并保留钥匙串。正常退出旧应用后替换到 `/Applications/搞邮件.app`，业务、悬浮窗及资料保留验证通过后清理旧程序、历史安装包和中间构建；失败时恢复旧程序，保留用户资料与安全备份。安全备份放在本项目已忽略的 `Backups/` 下，不上传 GitHub。临时测试 App 可用 `build.sh --app-only /绝对路径/测试.app` 构建，支持 `--data-dir /绝对测试目录` 隔离资料；正式版不接受此参数。

## 本地测试

```sh
./Tests/run_transport_tests.sh
./Tests/run_model_tests.sh
./Tests/run_oauth_tests.sh
./Tests/run_store_tests.sh
./Tests/run_floating_tests.sh
./Tests/run_floating_geometry.sh
```

协议测试只向本机生成的 TLS IMAP / SMTP 测试服务发送模拟消息，不访问用户邮箱。模型测试编译 `Sources/Models.swift Sources/Storage.swift Tests/ModelTests.swift`；OAuth 测试编译 `Sources/Vault.swift Sources/OAuth.swift Tests/OAuthTests.swift`，测试不访问真实授权账户。相关测试可能需要本机 loopback 和 Security 服务权限。

悬浮窗状态及几何测试还包含隐藏 AppKit 窗口的事件回归，使用随机测试偏好域，不显示窗口或投递操作系统输入。无可用显示器时明确跳过框架部分；各版本的实际验证范围记录在 `Docs/Validation-V*.txt`。

隔离测试 App 可加 `--layout-preview` 暂停离开轮询收起，方便检查布局；外部点击收起仍生效。该辅助功能仅存在于调试构建，正式版不包含。

实际服务商兼容性还取决于账号权限、服务商设置与组织策略，不能用本地模拟测试替代真实账号验收。账号授权属于用户操作。

详细操作和限制见 `使用说明.txt`。
