# macOS 安装、构建和发布

## 本地运行

工作台需要 macOS 14+。当前二进制验证在 arm64 完成；最低系统及 Intel 硬件仍待矩阵验收。KiCad 10 官方支持范围以官方页面为准，本工作台的最低版本要求比引擎更严格。

正式离线准备包含工作台 ZIP、官方 KiCad DMG、器件符号/封装、三维和 SPICE 模型、用户项目。v0.1 工作台 ZIP 只有工作台、资源、示例、文档；不包含完整引擎。

将工作台拖入 Applications，将官方 KiCad 文件夹按官方说明安装。默认 CLI 路径为 `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`。自定义路径在工作台设置选择，CLI 用 KICAD_CLI。显式选择的路径失效时不会静默回退到另一引擎。

## 编译

```bash
xcode-select --install  # 仅在尚未安装开发工具时，由用户执行
./scripts/build-app.sh
```

脚本不安装系统依赖，资源本地同步，然后 SwiftPM release 编译。版本兼容问题可用 EDA_SDK 指定 SDK。产物包括 `.app`、ZIP 和 eda。完整 Xcode 不是核心测试的必要依赖；EDASelfTests 是可运行测试程序。

目前打包当前主机架构。未来 universal2 应分别在 arm64/x86_64 构建、检查依赖架构、合并，并在两种硬件运行；当前不宣称 universal2 已完成。

## 签名与公证

开发包用 `codesign --sign -` 的 ad-hoc 签名，没有 Developer ID 和公证票据。正式分发需要持有者的 Apple Developer 证书和凭据，不能伪造或随仓库提交。未来 release 作业应按顺序：资源组装 → frameworks 检查 → 内层组件签名 → 主应用签名 → 公证 → staple → 校验 → 断网安装验收。凭据使用 CI secrets/keychain，不写入代码。

## 更新/卸载

程序不会自动联网更新。手工替换 app；项目数据在用户选择的目录，删除 app 不删除工程。最近项目和引擎路径使用 macOS UserDefaults 保存。无需本地守护进程或开放 TCP 端口。

## 常见故障

- 缺引擎：检查目录布局，确保选择 `kicad-cli` 而不是 app 目录。
- 版本不支持：仅接受 10.x；9.x/未来主版本须新增验证后再放行。
- 编辑器找不到：完整 KiCad.app 内有 Contents/Applications/eeschema.app 和 pcbnew.app；不要仅复制 CLI。
- 缺模型：先安装完整资源或把自定义模型复制到工程并使用相对路径。
- 工程打不开：manifest 格式/schemaVersion 和所有设计路径必须位于项目内。
- 发布失败：查看 outputs/failed-* 的 release.json 和 ERC/DRC 报告；修复后新作业重跑。
