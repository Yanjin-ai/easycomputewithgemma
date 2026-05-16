# docs/protocols/ — 协议文档索引

> 本目录是跨设备 Gemma 任务系统的**协议层**，所有 schema、代码、AI 工具的工作必须以本目录文档为上位约束。
> **变更规则**：协议文档的修改必须先于对应的代码变更，重大修改必须同步在 `docs/decisions/` 中创建 ADR。

---

## 协议文档清单与职责

| 文档 | 职责 | 谁必须读 |
|------|------|---------|
| [task_and_run_lifecycle.md](task_and_run_lifecycle.md) | 定义 Task 和 Run 的概念区别、Task state machine（状态 + 转移规则）、Run lifecycle 及其与 Task 的关系 | Codex（control-plane）、所有 runtime 开发者、web-console |
| [handoff_protocol.md](handoff_protocol.md) | 定义 HandoffPayload 最小字段集、handoff 触发条件、幂等性要求、必需的 event 记录 | Codex（HandoffService）、desktop runtime、cloud runtime |
| [event_and_observability.md](event_and_observability.md) | 定义 Event 分类（taxonomy）、每种 event 的必需字段、observability 视图的最小字段集 | Codex（Event API）、所有 runtime（事件回写）、web-console |
| [approval_and_permission.md](approval_and_permission.md) | 定义 Approval 触发条件和状态机、权限边界（local_only / private_lan / cloud_ok）及其对 routing 和 handoff 的影响 | Codex（ApprovalService、policy-engine）、所有 runtime、mobile-host |
| [schema_format_and_versioning.md](schema_format_and_versioning.md) | 定义 schema 格式选择（JSON Schema 推荐）、版本字段规范、prompt contract 和 tool contract 的版本管理方式、ADR 模板 | **Codex 写 schema 文件前必须最先阅读**、Claude Code（PR review）|
| [routing_policy.md](routing_policy.md) | 定义 RoutingEngine 的四类输入信号、硬过滤规则、软排序优先级、路由失败处理、policy 版本管理 | Codex（RoutingEngine、policy-engine）、control-plane、所有 runtime（能力注册接口）|
| [device_and_identity.md](device_and_identity.md) | 定义 Device 对象字段（device_id / account_id / runtime_type / permission_scope 等）、Device 生命周期（注册 / heartbeat / 停用）、permission_scope 与 permission_level 的区别 | Codex（device.schema.json）、control-plane（注册 API）、RoutingEngine、web-console（设备列表）|

---

## Codex 写 schema 前的必读顺序

在 `packages/schemas/` 目录下创建任何 schema 文件之前，Codex **必须按以下顺序**阅读协议文档，并确认每份文档中标注 `⚠️ 待人工决策` 的问题已有明确答案：

```
1. schema_format_and_versioning.md  ← schema 格式（已定：JSON Schema 2020-12）
2. task_and_run_lifecycle.md        ← Task/Run 字段和状态枚举（所有决策已锁定）
3. handoff_protocol.md              ← HandoffPayload 最小字段集（已锁定）
4. event_and_observability.md       ← Event 分类和必填字段（已锁定）
5. approval_and_permission.md       ← Approval 状态枚举和权限枚举值（已锁定）
6. routing_policy.md                ← RoutingEngine 输入信号与 runtime 能力注册字段
7. device_and_identity.md           ← Device 对象字段（device.schema.json 的直接来源）
```

**当前状态：以上所有阻断性问题均已决策，`ADR-001` 已创建。Codex 可以开始写 schema 文件初稿。**

---

## 决策状态追踪

### ✅ 已决策（2026-05-10 确认，ADR-001 记录）

| # | 问题 | 决策结果 |
|---|------|---------|
| P1 | schema 格式选择 | **JSON Schema Draft 2020-12**，TypeScript 类型从 schema 生成 |
| P2 | 重试是否创建新 Run | **是（Option A）**：每次重试创建新 Run，`attempt_index` 自增 |
| P3 | `step_completed` 是状态还是 Event | **纯 Event**：不作为 Run 的独立状态 |
| P4 | Handoff 时 Task 的中间状态 | **保持 `running` 直通（Option A）**：不经过 routing 中间状态 |
| P5 | 默认权限级别 | **`private_lan`**（保守优先）|

### 🟡 仍然开放（不阻断 v1 schema 初稿，但实现前需确认）

| # | 问题 | 相关文档 | 建议 |
|---|------|---------|------|
| P6 | ~~Approval 超时时长~~ | **已决策（2026-05-10）**：默认 24 小时，超时自动 `failed` | [approval_and_permission.md](approval_and_permission.md) |
| P7 | ~~权限升级~~ | **已决策（v1 保守）**：不允许，需重建 Task | [approval_and_permission.md](approval_and_permission.md) |
| P8 | ~~checkpoint_data 结构~~ | **已决策（Option C）**：通用基础 + `runtime_specific` 扩展对象 | [handoff_protocol.md](handoff_protocol.md) |
| P9 | **事件实时推送**：WebSocket/SSE 还是 polling？ | [event_and_observability.md](event_and_observability.md) | 建议 v1 先 polling，WebSocket 留 v2 |
| P10 | **Memory 对象 v1 范围**：SummaryMemoryService 是否进 v1？ | [handoff_protocol.md](handoff_protocol.md) | 建议 v1 先实现 HandoffPayload 的 `task_context.memory_summary` 为可选字段，Memory 对象本身留 v2 |

---

## 目录下尚缺的文档（后续补充，不阻断 v1 schema）

以下协议文档在对应功能实现前需补充，但不阻断当前 schema 初稿编写：

- `tooling_and_function_schema.md`：tool schema 格式、mobile / desktop / cloud 工具分类、tool capability registry
- `runtime_adapter_interface.md`：RuntimeAdapter 接口定义、各 runtime 的 capability 注册格式
- `prompt_contracts/parser-router-v1.0.md`：FunctionGemma parser-router 的 prompt contract
