# Offline EDA Studio

面向 MacBook 的原生、离线 EDA 工作台。项目目标是在明确的验收矩阵上达到 Altium Designer **90% 以上**功能覆盖；当前交付是 **v0.1 可运行基础版本与完整开发设计，不是已经达到 90% 的替代软件**。

原理图、PCB 编辑、交互布线、3D 与仿真使用本地 KiCad 引擎。SwiftUI 工作台补充项目管理、采购 BOM、点对点线束、SHA-256 快照和制造发布流水线。工作台没有网络客户端、云账号、遥测或在线激活。

## 当前可运行的功能

- 原生中文 macOS 界面与 CLI，打开/创建自包含项目，启动 KiCad 原理图和 PCB 编辑器。
- PCB 简化只读预览：真实文件里的直线、走线和矩形焊盘，前/后铜层切换。
- 本地采购元件增删、搜索、计划 DNP、分组 CSV。采购计划不自动同步原理图；设计 BOM 从 KiCad 导出。
- 点对点线束检查与裁线 CSV：未知连接器、越界引脚、重复占针、自连接及长度检查。
- 复制前后校验的项目快照，SHA-256 清单与篡改检测。
- KiCad 作业：ERC、DRC/原理图一致性、Gerber、Excellon、坐标、STEP、SVG、PDF、网表、设计 BOM、IPC-2581、ODB++。
- 双层板制造发布：冻结输入 → 检查 → 输出 → 校验，失败保留诊断。多层板明确拒绝，避免遗漏内层铜。
- 薄导体微带阻抗初估，带参数检查与模型限制。
- 12 类、122 项功能矩阵及每项验收条件。矩阵中的继承能力、代码实现与完整验收分开记录。

## 获取和安装

要求 macOS 14 或更高。当前发布的工作台二进制为 Apple Silicon（arm64）；Intel 需自行编译，尚未完成硬件验收。

1. 从 [Releases](https://github.com/Hanbin-Zhang-JPN/offline-eda-studio/releases) 下载工作台 ZIP，解压，将 `Offline EDA Studio.app` 放进“应用程序”。
2. 从 [KiCad 官方 macOS 下载页](https://www.kicad.org/download/macos/) 获取 KiCad 10.x，按官方说明安装完整 KiCad 文件夹，保留内置符号、封装及 3D 模型。验证基线为 10.0.6。
3. 打开工作台，默认自动查找 `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli`。自定义安装位置可用“选择 EDA 引擎”。
4. 点击“新建示例”，选择新目录；打开原理图或 PCB 编辑器，编辑并保存后回到工作台刷新。
5. 准备好本地模型后断网，检查、快照、CSV 和制造输出仍可运行。演示项目自带原创符号与封装，演示检查不依赖外部元件库。

工作台包使用本地 ad-hoc 签名，尚未 Developer ID 签名和公证。首次启动可在 Finder 右键“打开”，由 macOS 安全设置决定是否允许；不要求关闭系统保护。工作台 ZIP 不含 KiCad 二进制，完整离线安装需提前准备 **两个包**及所需模型。仓库提供固定版本下载和 SHA-256 校验脚本。

## 从源码编译

安装 Xcode Command Line Tools（或 Xcode）、Python 3；Swift 5.9+。无 npm、第三方 Swift 包或在线运行时依赖。首次安装开发工具需要网络；准备好的源码可离线编译。

```bash
./scripts/prepare-resources.sh
./scripts/swift.sh build
./scripts/swift.sh run EDASelfTests
./scripts/build-app.sh
open "dist/Offline EDA Studio.app"
```

`scripts/swift.sh` 会在本机 CLT 的预览 SDK 缺少 State 宏插件时选择已安装的稳定 SDK；可通过 `EDA_SDK=/path/to/sdk` 显式指定。产物在 `dist/`。测试程序不依赖完整 Xcode 中的 XCTest，可在 CLT 环境运行。

## CLI

```bash
.build/debug/eda create /tmp/led-design "我的 LED 板" examples/led-demo
.build/debug/eda doctor
.build/debug/eda inspect /tmp/led-design
.build/debug/eda snapshot /tmp/led-design "布局完成"
.build/debug/eda bom /tmp/led-design /tmp/planning-bom.csv
.build/debug/eda harness /tmp/led-design /tmp/wires.csv
.build/debug/eda job /tmp/led-design drc /tmp/check
.build/debug/eda release /tmp/led-design --step
.build/debug/eda impedance 0.30 0.18 4.2
```

可以用 `KICAD_CLI=/path/to/kicad-cli` 指定引擎。制造发布的 `release.json` 包含源哈希、输出哈希、引擎版本、命令、日志与退出码。`outputs/job-*` 是单项输出，**不等于通过发布**。`outputs/failed-*` 是诊断目录。

## 实现边界

高级 SI/PI 场求解、复杂刚柔结合、多板 3D 装配、正式装配变体、受管元件库、Draftsman 等效文档和原生 Altium 无损往返尚未完成。上游编辑器的功能存在不意味着本仓库已经逐项验收。当前预览不显示全部 PCB 几何；采购计划 DNP 不修改 KiCad 变体；输出检查不能替代独立 DFM 或器件电气验证。

v0.1 发布流水线只支持双层板，使用启用的 KiCad 规则。报告中的 `ignored_checks` 列出关闭的检查；没有“自动绕过检查”的按钮。复杂项目中的外部库/3D/SPICE 依赖目前需手工准备，完整依赖锁定属于后续阶段。

## 仓库地图

|路径|内容|
|---|---|
|`Sources/EDACore`|项目、BOM、快照、线束、解析预览、KiCad 适配与制造门禁|
|`Sources/EDAStudio`|原生 SwiftUI 桌面应用|
|`Sources/EDACLI`|命令行入口|
|`Tests/EDACoreTests`|可独立运行的核心测试|
|`examples/led-demo`|可复生成的原创、自包含 KiCad 示例|
|`Resources`|功能矩阵数据和类别权重|
|`docs`|需求、系统架构、各高级模块规格、路线图、离线打包及验收|
|`scripts`|构建、校验、引擎下载、真实集成测试和资源同步|
|`reports`|本次验证证据及限制|

## 设计与验收文档

从 [产品需求](docs/PRODUCT_REQUIREMENTS.md)、[系统架构](docs/ARCHITECTURE.md)、[122 项功能矩阵](docs/FEATURE_MATRIX.md) 和 [分阶段路线图](docs/ROADMAP.md) 开始。具体模块规格位于 [docs/specs](docs/specs)，当前运行说明见 [macOS 安装](docs/MACOS_INSTALL.md)、[离线使用](docs/OFFLINE.md)、[测试方案](docs/TESTING.md)。

本项目与 Altium、KiCad 官方无从属关系。原创代码和示例为 MIT 许可；外部引擎保留各自许可证，见 [第三方说明](THIRD_PARTY.md)。
