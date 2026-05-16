# 系统设计当前共识总结

> **文档状态**：架构审查产出，由 Claude Code 于 2026-05-10 基于四份上位文档生成。
> **上位真相源**：`docs/project/project_guidance_full_zh.md`、`docs/architecture/system-design.md`、`docs/playbooks/ai-collaboration-rules.md`、`docs/integrations/google-runtime-reuse.md`
> **用途**：供 Codex 写 schema 前对齐共识；供人工在编写协议前确认空白与歧义。

---

## 一、当前已确立的核心共识

### 1. 产品定性（已冻结）

这是一个**统一账号下的多运行时任务系统**，不是聊天产品、不是单端本地 AI demo。核心价值是：同一个结构化任务可以在 phone / desktop / cloud / web 之间按策略路由、接续执行、统一观察、统一接管。

### 2. 四条不可妥协的设计原则（已冻结）

| 原则 | 含义 |
|------|------|
| Task-first | 信息架构围绕 Task 对象，不围绕 Chat/消息流 |
| Schema-first | 协议层优先于 prompt 与业务实现，schema 变更先于代码变更 |
| Control-plane first | 全局任务状态由 control plane 唯一管理，runtime 不得绕过 control-plane API 修改任务状态 |
| Local-first | mobile → desktop → cloud 升级路径，cloud 不是默认路径而是 fallback |

### 3. 系统分层（已冻结，目录映射明确）

```
apps/
  mobile-host/       # 宿主容器 + 任务入口 + 本地 parser + 轻执行器
  web-console/       # control plane 与 observability 控制台

services/
  control-plane/     # 系统大脑：Task/Run/Event/Artifact/Approval/Routing/Handoff
  desktop-runtime/   # 本地主执行节点：文件/终端/浏览器/重工具链
  cloud-runtime/     # 重任务/长任务 fallback runtime

packages/
  schemas/           # 核心 JSON schema（或等价 schema 文件）
  runtime-adapters/  # RuntimeAdapter interface + 各 runtime 接入
  policy-engine/     # 路由策略、权限边界、policy evaluation
  shared-types/      # 跨模块共享类型
```

### 4. 六个核心对象（名称已冻结，内容待定义）

`Device` / `Task` / `Run` / `Event` / `Artifact` / `HandoffPayload`

任何变更都需要 schema/protocol 更新与 ADR。

### 5. 五条必须冻结的协议边界（已命名，内容待补）

- Task state machine（状态名与转移规则）
- RoutingPolicy 输入字段
- Handoff payload 最小字段集
- Tool schema 与 function call schema
- Runtime adapter interface
- 权限边界：`local_only` / `private_lan` / `cloud_ok`

### 6. Google 轮子复用定位（已冻结）

| 轮子 | 用于 | 禁止用于 |
|------|------|---------|
| LiteRT-LM | 本地推理 runtime 底座、benchmark 参考 | control plane、任务生命周期、routing |
| Edge Gallery | 宿主容器思路、模型导入/管理/benchmark 面板 | 产品信息架构照搬、task-native 页面、control plane |
| FunctionGemma | parser/router、function call 生成、task draft 生成、本地动作识别 | 全局路由决策、全局任务状态管理、跨设备调度总控 |

所有第三方能力必须通过统一 schema 和 adapter 接入，业务层不得直接耦合底层 SDK。

### 7. AI 协作分工（已冻结）

- **Codex**：代码施工、schema 文件初稿、service skeleton、adapter、测试。
- **Claude Code**：架构审查、PR review、分层边界检查、协议一致性审查。
- **Kimi**：中文文档整理、会议纪要、issue 草稿、ADR 中文摘要。

---

## 二、文档中的结构性空白与不一致

### 空白 A：六个核心对象均无字段定义

所有文档只命名了 Device / Task / Run / Event / Artifact / HandoffPayload，但无任何字段、类型、必填/可选、版本说明。`packages/schemas/` 目录尚不存在任何 schema 文件。

**影响**：Codex 无法写 schema 文件；所有协议讨论缺乏可操作基础。

### 空白 B：Task state machine 仅被命名，未被定义

"Task state machine 必须冻结" 出现在三份文档中，但没有任何文档列出具体状态（如 draft / pending / routed / running / paused / completed / failed / cancelled）和合法转移路径。

**影响**：Run 与 Task 的关系无法确立；approval 触发时机无法定义；checkpoint 回写位置无法确定。

### 空白 C：Run 对象的生命周期与 Task 的关系未定义

Task 和 Run 都出现在核心对象列表中，但两者的关系从未明确：一个 Task 可以有几个并发 Run？Run 的状态机是什么？Run 失败后 Task 的状态如何变化？

**影响**：control plane 的 Task API 和 Run API 设计无法展开。

### 空白 D：Event 的类型分类（taxonomy）完全缺失

Event 被定性为所有路由决策、handoff、approval 的审计记录，但从未定义事件类型有哪些、每种类型的必填字段是什么、事件是否有版本号。

**影响**：observability 和 replay 功能无法设计；audit log 无法落地。

### 空白 E：HandoffPayload 最小字段集未定义

文档多次提到 "Handoff payload 最小字段必须冻结"，但没有任何地方列出这些字段（task_id、run_id、checkpoint_data、target_runtime、context、auth_token 等均未确认）。

**影响**：desktop runtime 和 cloud runtime 的 handoff 接收接口无法设计。

### 空白 F：FunctionGemma 输出（TaskDraft）到 RoutingEngine 的边界不清

`project_guidance` 和 `google-runtime-reuse.md` 都说 FunctionGemma 用于 "parser/router"，但 `system-design.md` 也列了独立的 RoutingEngine。两者的职责边界未定义：FunctionGemma 产出什么格式的 TaskDraft？TaskDraft 如何进入 control plane？RoutingEngine 从哪里消费 TaskDraft？

**影响**：ParserRouterService 的输入/输出 schema 无法写；mobile-host 与 control plane 的对接接口无法设计。

### 空白 G：Approval 机制的触发条件与状态未定义

ApprovalService 被列为 control plane 的组成部分，"approval 必须产生 event 记录" 也是冻结规则，但 approval 的触发条件（何种任务需要审批？由谁决定？）、approval 对象的状态机（pending / approved / rejected / timed_out）、approval 超时行为均未定义。

**影响**：mobile host 的审批页面无法设计；Run 的暂停/恢复逻辑无法实现。

### 空白 H：SummaryMemoryService 不在六个核心对象中，但其存在已被假设

`project_guidance` 的 control plane TODO 中列出了 SummaryMemoryService，但 "memory" 既不在核心对象清单中，也没有任何 schema 描述。它是 v1 范围内的对象还是 v2 扩展？

**影响**：memory 的 schema 和存储位置不明，Codex 实现 control plane 时会产生歧义。

### 不一致 I：schema 格式在文档中有歧义

`system-design.md` 写的是 "JSON schema 或等价 schema 文件"，而 `project_guidance` 的 schema 目录举例全为 `*.schema.json`。但没有任何 ADR 声明为什么选 JSON Schema 而不是 TypeScript / Zod / Protobuf，这会影响 Codex 选择 schema 工具链。

### 不一致 J：ToolAdapter 在 `google-runtime-reuse.md` 中存在，但在 `system-design.md` 的 packages 目录中缺失

`google-runtime-reuse.md` 列出了接入前必须定义的接口，包括 `ToolAdapter`，但 `system-design.md` 的 `packages/` 目录中只有 `runtime-adapters/`，没有单独的 `tool-adapters/` 或对 ToolAdapter 的任何描述。ToolAdapter 是 RuntimeAdapter 的子类还是独立接口？

### 不一致 K：Web Console 的后端归属不明确

Web Console 被定性为 "control plane 与 observability 控制台"，但没有文档说明 web console 是否有自己的后端服务，还是直接对接 `services/control-plane/` 的 API。这会影响 `apps/web-console/` 的技术选型和部署模型。

---

## 三、编写 schema 与实现代码前必须先澄清的问题（共 9 条）

### Q1：Task state machine 的完整状态与转移规则是什么？

必须列出所有合法状态名称、每个状态允许的转移目标、每个转移的触发方（system / user / runtime）。这是所有其他协议的基础。

### Q2：Run 对象的生命周期与 Task 的关系如何定义？

一个 Task 在同一时刻最多有几个活跃 Run？Run 失败后 Task 是否自动进入 failed 状态，还是等待重试？Run 的状态机是否独立于 Task？

### Q3：HandoffPayload 的最小字段集是什么？

哪些字段是 handoff 语义上的必填项（不可缺少否则接收方无法接续执行）？哪些是可选的扩展字段？字段命名采用什么风格（snake_case / camelCase）？

### Q4：Event 的类型分类（taxonomy）是什么，每种类型的必填字段有哪些？

建议先列出 v1 范围内必须覆盖的事件类型：如 `task.created`、`route.decided`、`run.started`、`handoff.initiated`、`approval.requested`、`artifact.uploaded`、`run.completed` 等，以及每种类型的 payload 结构。

### Q5：FunctionGemma 的输出（TaskDraft）与 control plane RoutingEngine 的边界在哪里？

FunctionGemma 在 mobile 端产出 TaskDraft 后，是由 mobile host 直接提交给 control plane 的 Task API，还是先经过本地 ParserRouterService 做规则兜底，再提交？TaskDraft 与 Task 是同一个 schema 对象还是两个不同对象？

### Q6：Approval 的触发条件、状态机和超时行为是什么？

哪类任务需要进入 approval 流程（是 RoutingPolicy 的输出决定，还是 Task 本身的属性）？approval 对象有哪些状态？超时后 Run 进入什么状态？

### Q7：schema 文件格式选择什么，依据是什么？

JSON Schema `.schema.json`、TypeScript 类型（`packages/shared-types/`）、Zod schema、还是 Protobuf？选择会影响 validation 工具链、代码生成方式和跨语言兼容性。必须有 ADR。

### Q8：SummaryMemoryService 的 "memory" 是否是 v1 范围内的核心对象？

如果是，需要定义 Memory 对象的 schema 和生命周期，并加入核心对象清单。如果不是，需要明确将其从 control plane v1 实现范围中移出，避免 Codex 实现时产生漂移。

### Q9：Web Console 是纯前端（直接对接 control-plane API），还是有独立 BFF 层？

这个决定影响 `apps/web-console/` 是否需要独立服务进程，以及 control-plane API 的设计是否需要同时面向 machine client（runtime）和 browser client（web console）。

---

## 四、Codex 写 schema 前必须满足的 checklist

在 `packages/schemas/` 目录下创建任何 `.schema.json` 或等价文件之前，以下条件必须全部为 **checked**：

```
[ ] 1. docs/protocols/task-protocol.md 已存在，且包含 Task state machine 的完整状态列表与转移规则
[ ] 2. docs/protocols/run-protocol.md 已存在，且明确定义了 Run 与 Task 的从属关系及 Run 的状态机
[ ] 3. docs/protocols/handoff-protocol.md 已存在，且列出了 HandoffPayload 的最小必填字段
[ ] 4. docs/protocols/event-protocol.md 已存在，且包含 v1 范围内的 Event 类型分类与每种类型的必填字段
[ ] 5. docs/protocols/approval-protocol.md 已存在，且定义了 Approval 的触发条件与状态机
[ ] 6. docs/decisions/ADR-001-schema-format.md 已存在，且声明了选用的 schema 格式（JSON Schema / TypeScript / Zod / Protobuf）与理由
[ ] 7. FunctionGemma → TaskDraft → RoutingEngine 的边界已在 docs/protocols/ 或 docs/architecture/ 中以文字形式明确（TaskDraft 是否等于 Task？提交路径是什么？）
[ ] 8. SummaryMemoryService / Memory 对象的 v1 范围已确认（in scope → 需加入核心对象；out of scope → 从 control plane v1 实现中移除）
[ ] 9. 六个核心对象（Device/Task/Run/Event/Artifact/HandoffPayload）的字段草稿已在协议文档中以文字描述列出（不要求完整，但至少列出必填字段名与类型）
[ ] 10. 上述所有协议文档已经过人工确认（不仅是 AI 产出），并在对应文档顶部标注"已确认"或类似状态
```

---

## 五、当前文档成熟度评估

| 维度 | 状态 | 说明 |
|------|------|------|
| 产品定性与原则 | ✅ 已冻结 | 四份文档高度一致 |
| 系统分层与目录结构 | ✅ 已冻结 | 分层明确，目录映射清晰 |
| 核心对象名称 | ✅ 已冻结 | 六个对象名称一致 |
| Google 轮子复用定位 | ✅ 已冻结 | 三份文档高度一致 |
| AI 协作分工 | ✅ 已冻结 | 分工清晰 |
| Task state machine | ❌ 缺失 | 只有名称，无内容 |
| Run lifecycle & Task 关系 | ❌ 缺失 | 完全未定义 |
| HandoffPayload 字段 | ❌ 缺失 | 只有名称，无内容 |
| Event taxonomy | ❌ 缺失 | 完全未定义 |
| Approval 机制 | ❌ 缺失 | 只有名称，无内容 |
| Schema 格式决策 | ⚠️ 有歧义 | 暗示 JSON Schema 但无 ADR |
| ToolAdapter 定位 | ⚠️ 有歧义 | `google-runtime-reuse.md` 提及但未入 system-design |
| Web Console 后端归属 | ⚠️ 有歧义 | 文档未说明是否有 BFF |
| Memory 对象 v1 范围 | ⚠️ 不确定 | 存在于 TODO 中但未入核心对象清单 |
| 任何 schema 文件 | ❌ 不存在 | `packages/schemas/` 目录下无文件 |
| 任何 protocol 文档 | ❌ 不存在 | `docs/protocols/` 目录下无文件 |
| 任何 ADR | ❌ 不存在 | `docs/decisions/` 目录下无文件 |
