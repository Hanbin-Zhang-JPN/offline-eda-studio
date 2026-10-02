# v0.1 验证记录

验证日期：2026-10-03（Asia/Tokyo）。环境：Apple Silicon arm64，Swift 6.4 / macOS SDK 26.5；系统原生编译。工作台目标 macOS 14+，最低系统与 Intel 仍需硬件验收。

## 实际检查

- Swift release/debug 编译与 app 打包，ad-hoc 签名严格校验。
- 打包 app 原生 UI：启动、资源加载、新建项目、双层/3 元件摘要、真实 PCB 预览、采购 DNP 保存/恢复、点对点线束页面；详见 ui-smoke.json。
- 18 个核心测试：路径越界/符号链接/格式/拒绝覆盖、快照哈希/篡改/排除生成目录、BOM/DNP/重复位号/价格/CSV、线束、阻抗参考值、解析器/预览非有限几何、进程大输出/退出码/超时、错误报告拒绝。
- 官方 KiCad 10.0.6 universal DMG，SHA-256 校验：ef4dcd4278c46d3efcd28c8db273d5957d68efda028f6bf79b4811fc5302dc68；只读挂载执行，不修改系统 KiCad 安装。
- 自包含原创 LED 夹具：ERC 零违规、DRC 零违规/零未连接/零原理图一致性问题。
- 集成测试：12 种真实 CLI 作业、冻结源的制造发布、源/输出 SHA-256、中文/空格路径、断线拒绝发布、四层板拒绝发布、快照篡改拒绝。结果以 integration.json 为准。

## 如何重现

```bash
./scripts/prepare-resources.sh
./scripts/swift.sh build
EDA_TEST_REPORT=reports/core-tests.json ./scripts/swift.sh run EDASelfTests
KICAD_CLI=/path/to/kicad-cli python3 scripts/integration-test.py
./scripts/build-app.sh
python3 scripts/check-coverage.py
```

## 本证据的边界

单个双层演示项目。输出非空和可重算哈希不等于所有专业格式被独立制造工具验证。复杂多层板、SPICE 模型、完整图形编辑、SI/PI、刚柔、多板、正式变体、代工 DFM、最低系统、Intel、签名公证和系统封网/抓包尚未完整验收。因此没有把任意矩阵功能提前标记 verified，也没有宣称达到 Altium 90%。

引擎 stderr 有 Fontconfig 缓存版本提示，未阻止实际检查/导出；属于官方安装包资源环境提示，日志仍保留。固定引擎版本与测试输入随仓库说明，复跑结果可能包含时间戳差异。
