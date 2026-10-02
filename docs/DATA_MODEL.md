# 数据模型与存储

## 已实现格式

项目目录至少包含 eda-project.json、设计文件、parts.json、harness.json。manifest schemaVersion=1，name 不为空，所有字段均为项目内相对路径。绝对路径、`..`、解析到根外的符号链接被拒绝。设计文件使用 KiCad 原生格式，不由工作台更改电气结构。

```json
{"schemaVersion":1,"name":"LED","projectFile":"design.kicad_pro","schematicFile":"design.kicad_sch","boardFile":"design.kicad_pcb","partsFile":"parts.json","harnessFile":"harness.json"}
```

parts.json 是 Component 数组：reference/value/footprint/mpn/manufacturer/unitPrice/dnp。每个位号一条，忽略大小写的重复位号拒绝；价格必须非负有限数。数量由分组得到，组键包含值、封装、MPN、厂商、单价及 DNP。单价当前没有币种，是采购计划字段，不能作为实时采购计算。

harness.json 包含 schemaVersion、connectors 与 wires。连接器有 id/pins/partNumber；导线有 id/from/to/net/lengthMM/awg/color。v1 是点对点模型，一个端点不允许被多根线占用；分支需要未来显式接点模型，不能靠重复占针代替。

### 快照

`.eda-snapshots/<uuid>/snapshot.json` 记录时间、标签、每个源文件路径/字节数/sha256，source/ 复制源。排除 outputs、快照自身、Git、构建产物、引擎、备份和 KiCad 临时偏好文件。复制前后输入以及复制目标必须一致，不一致则清理临时目录。校验要求文件集合也一致，新增/删除/修改均导致失败。

### 作业与发布

单项作业：outputs/job-*/command.json。发布：outputs/release-*/release.json + source/ + artifacts/；失败：outputs/failed-*。命令含参数、退出码、stdout/stderr、耗时。发布清单包含源/输出哈希、引擎版本、status 与 note。UUID 命名确保不同运行不覆盖输出。

元数据使用原子写入。当前无多进程写锁，外部同时修改 parts.json 可造成最后写入胜出；生产级项目 actor 和 expectedRevision 属于 P2，不能声称已解决并发编辑。

## 未来服务数据模型

|实体|关键字段|不变量|
|---|---|---|
|DesignRevision|source hashes、libraryLockHash、ruleHash、engineVersion|审批和结果绑定相同 revision|
|ManagedComponent|UUID、revision、symbolHash、footprintHash、modelHash、parameters、status|批准版本不可原地覆盖|
|Variant|baseRevision、component overrides、DNP、alternative ID|每种输出采用同一个变体解析结果|
|ECO|expectedRevision、operations、previewHash、author|提交前验证 revision，无静默冲突|
|Assembly|board instance ID、4x4 transform、mates|坐标/单位统一、禁止循环配合|
|FlexRegion|polygon、stackup ID、bend definitions|区域与层集合明确，展开/折叠可逆|
|ReviewEvent|object anchor、revision、identity、time、action|失效锚点不能错误指向新对象|
|JobSpec|input hashes、capabilities、tool version、outputs|缓存键包括所有设计/依赖/规则|

SQLite 仅作索引、可重建视图与审阅事件，启用 foreign keys/WAL 和事务。几何使用 KiCad 原生精度或整数 nm；求解器边界转换用显式单位，不能混用 mil/mm。文件 schema 迁移先备份再生成新版本，不原地升级用户原稿。
