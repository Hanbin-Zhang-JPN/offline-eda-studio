# 格式兼容与插件接口

## 导入语义

KiCad 支持的第三方格式由当前引擎确定。工作台 v0.1 不提供完整 Altium importer；用户在原生 KiCad 导入后添加工作台 manifest。原始文件永远保留。只声称已验证的版本/文件类型，未支持的对象/规则必须进入 ImportLossReport。

报告分别比较符号/位号/引脚、网络连通、封装/焊盘映射、板框/层叠、铜与过孔、规则/变体/3D。成功解析不等于电气等价；设计规则与高级刚柔信息不可静默丢弃。Altium 原生文件无损往返是单独关键项目，当前不承诺。

## 插件协议（目标）

Descriptor 含 id、版本、支持 schema/API、capabilities、输入/输出类型、权限（read-project/write-proposal/network/execute-tool）和可执行文件哈希。插件以独立进程读取冻结输入，返回结构化结果/变更提案，不直接写权威源。

握手：protocolVersion、toolVersion、capabilities、units、licenseState；作业：jobID、revisionHash、inputFiles、parameters、timeout；结果：status、diagnostics、outputHashes、proposal、provenance。未知能力显式 unsupported，schema 错误为失败。

权限默认按本地最小能力配置，网络需用户显式操作授权；插件异常不可破坏主服务。任何写提案必须经过 expectedRevision/差异预览/批准/提交，不执行项目携带的任意脚本。

## CLI 与 IPC

现有 CLI 的退出码用于自动化：失败为非零，缺引擎/版本错误/报告违规不能返回成功。参数数组和 Unicode 路径需要负测试。IPC 应只用官方文档化 API，查询版本与支持对象；原理图或功能尚不支持时走原生 GUI，不能用脆弱鼠标宏宣称内核能力。

## 验收

坏 schema、旧/未来版本、超时/取消、日志大输出、恶意路径、未声明网络、修改已变更 revision、错误单位、插件崩溃和签名/许可缺失。导出和导入需独立工具互验证，不能仅由同一解析器自证。
