# 第三方组件与来源

本仓库原创 Swift 代码、生成脚本、文档、符号/封装与示例采用 MIT。SwiftUI、AppKit、Foundation、CryptoKit 是系统框架，本仓库不分发其源码或系统运行时。

KiCad 是独立外部引擎，工作台通过文档化命令行和外部应用入口调用，不包含 KiCad 源码或可执行文件。官方 DMG 通过 fetch-engine.sh 单独获取，engine/ 被 Git 忽略，不随工作台 ZIP/GitHub 源码发布。KiCad 及其内置 Python、wxWidgets、ngspice、几何与其他资源的许可声明以官方安装包和上游源码为准；重新捆绑引擎必须保留全部相应许可和源码提供要求，不能把引擎改称本项目 MIT 代码。

固定引擎来源：

- [KiCad 10.0.6 官方 Release](https://github.com/KiCad/kicad-source-mirror/releases/tag/10.0.6)
- 文件：kicad-unified-universal-10.0.6.dmg
- SHA-256：ef4dcd4278c46d3efcd28c8db273d5957d68efda028f6bf79b4811fc5302dc68
- [KiCad macOS 安装](https://www.kicad.org/download/macos/)
- [KiCad CLI](https://docs.kicad.org/10.0/en/cli/cli.html)

Altium Designer、Altium 与 KiCad 商标属于各自权利人。没有复制 Altium 商业代码、图标、界面素材或示例，文档只进行功能范围对标，不宣称官方认可。未来第三方求解器/几何/库资源应增加 SPDX、来源和 SBOM；当前仅是设计规格，未暗中下载这些组件。
