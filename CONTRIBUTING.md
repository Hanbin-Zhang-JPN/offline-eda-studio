# 贡献指南

先阅读功能矩阵与 ADR。提交的功能需要明确 status：planned/inherited/implemented/verified。继承能力或简单 smoke test 不得直接标专业 verified。

运行 prepare-resources、核心测试、功能数据校验和 build-app。修改引擎适配/门禁时必须真实运行 KiCad integration-test，并增加代表错误行为的夹具。避免仅镜像实现的测试；关注漏层、单位、位号/网络、变体与源覆盖风险。

功能数据由 scripts/generate-features.py 生成；修改源脚本，再生成 JSON/Markdown。示例由 generate-demo.py 复生成，原创库的网格/网络/封装/实例映射要保持一致。GUI 资源通过 prepare-resources.sh 同步，不能从开发机绝对路径读取。

代码与文档明确哪些模块尚未实现。PR 说明触发问题、最终行为、测试和材料限制。用户原生文件不覆盖；输出任务失败必须非零并保留诊断。证书/令牌/真实敏感设计不能提交到仓库。
