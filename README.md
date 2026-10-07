# 搞邮件

原生 macOS 邮箱客户端，当前正式版本 V1.03。要求 Apple Silicon、macOS 14+。

功能包括 IMAP / SMTP 收发、Google / Microsoft OAuth、邮箱身份分类、手动关联网站与 App、历史记录、附件、草稿、资料备份和 CSV 导入导出。没有内置真实账户或共享 OAuth 客户端身份。

[下载安装包](https://github.com/UCASerYff/GaoYouJian/releases/latest) · [源代码](https://github.com/UCASerYff/GaoYouJian)

V1.03 新增原生悬浮窗：缓存未读数、邮箱切换、可选最近三封未读预览、收件箱 / 同步 / 写信快捷入口。鼠标离开后贴边收成细条，移入展开；支持固定展开、拖动吸附、紧凑模式、透明度和位置记忆。从菜单栏信封、工具栏或 ⌃⌘M 打开。默认隐藏邮件预览，展开悬浮窗不会将邮件标为已读。

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

构建在 `/private/tmp` 创建自己的临时目录，结束后清理。安装会正常退出旧应用并替换到 `/Applications/搞邮件.app`；成功启动后清理旧应用和此项目的历史安装包，失败时尝试回滚。用户资料与钥匙串不删除。临时测试 App 可用 `build.sh --app-only /绝对路径/测试.app` 构建，支持 `--data-dir /绝对测试目录` 隔离资料；正式版不接受此参数。

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

实际服务商兼容性还取决于账号权限、服务商设置与组织策略，不能用本地模拟测试替代真实账号验收。账号授权属于用户操作。

详细操作和限制见 `使用说明.txt`。
