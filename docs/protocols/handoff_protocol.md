# Handoff 协议

> **状态**：骨架草稿，待人工决策后补充细节。
> **上位文档**：`docs/architecture/system-design.md`、`docs/project/project_guidance_full_zh.md`
> **谁依赖本文档**：control-plane（HandoffService）、desktop-runtime（handoff 接收）、cloud-runtime（handoff 接收）、mobile-host（发起 handoff / 接收回流）、policy-engine（handoff 权限校验）

---

## 一、Handoff 的定义与语义

Handoff 是指将一个正在执行或待执行的 Task 从一个 runtime 移交给另一个 runtime 的完整协议过程。

- 发起方可以是：control-plane（RoutingEngine 决策）、用户（手动 override）、runtime（自报能力不足）。
- 接收方必须能够从 checkpoint_data 恢复执行上下文，不得要求重新开始。
- Handoff 必须是幂等的：重复发送同一 HandoffPayload 不应导致重复执行。
- 每次 handoff 必须产生完整的 event 记录，不可绕过 control-plane。

---

## 二、HandoffPayload 最小字段集

以下字段是 HandoffPayload 的**必需字段**，缺少任何一个都无法保证接收方正确接续执行。

| 字段名 | 类型 | 语义 | 来源 | 被谁使用 |
|--------|------|------|------|---------|
| `handoff_id` | string (UUID) | 本次 handoff 的唯一标识，用于幂等校验 | control-plane 生成 | HandoffService、接收方去重 |
| `task_id` | string (UUID) | 被移交的 Task 标识 | Task 对象 | 接收方创建 Run 时关联 |
| `source_run_id` | string (UUID) | 发起 handoff 的 Run 标识 | 当前 active Run | 事件追踪、replay |
| `target_runtime` | enum | 目标 runtime：`mobile` / `desktop` / `cloud` | RoutingEngine 决策 | 路由、接收方身份验证 |
| `permission_level` | enum | `local_only` / `private_lan` / `cloud_ok` | Task 对象 | 接收方校验是否允许接收 |
| `checkpoint_data` | object | 序列化的执行上下文，包含：已完成步骤、中间结果、当前工具状态 | 源 runtime 回写 | 接收方恢复执行 |
| `task_context` | object | Task 目标描述、原始 intent、memory 摘要，接收方理解任务所需的最小上下文 | Task 对象 + SummaryMemory | 接收方的 LLM/执行器 |
| `initiated_by` | enum | `system`（routing 决策）/ `user`（手动 override） | 触发方 | 审计、observability |
| `initiated_at` | timestamp | Handoff 发起时间 | control-plane | 事件时序、SLA 计算 |
| `reason` | string | 人可读的 handoff 原因（如"设备电量不足"、"任务需要文件系统访问"）| RoutingEngine / runtime | web-console 展示 |

### 可选扩展字段（v1 可不实现，留接口）

| 字段名 | 类型 | 语义 |
|--------|------|------|
| `artifact_refs` | list | 已生成的 Artifact 引用，接收方可选择性拉取 |
| `tool_results_cache` | object | 已完成 tool call 的缓存结果，避免重复调用 |
| `preferred_model` | string | 建议接收方使用的模型（非强制）|
| `deadline` | timestamp | Task 的用户期望完成时间（如有）|
| `schema_version` | string | HandoffPayload schema 版本 |

---

## 三、checkpoint_data 的内容约定（草稿）

checkpoint_data 是 handoff 的核心，其结构由源 runtime 填写，接收方必须能解析。

checkpoint_data 应包含（具体 schema 在 packages/schemas/ 中定义）：

- `steps_completed`：已完成步骤的列表（含步骤 ID、输出摘要）
- `current_step`：当前卡住或需要继续的步骤描述
- `tool_call_history`：已执行 tool call 的列表（含结果）
- `variables`：执行过程中产生的中间变量
- `pending_actions`：尚未执行的动作列表

**已决策（Option C，2026-05-10）**：通用基础字段 + `runtime_specific` 扩展对象。接收方只需读懂通用字段即可接续执行，`runtime_specific` 内容接收方可选择性使用或忽略。v1 各 runtime 的 `runtime_specific` 内容先留空，实现阶段按需填充。

---

## 四、task_context 的内容约定（草稿）

task_context 是接收方理解任务目标所需的最小上下文，与 checkpoint_data 分离是为了让接收方可以独立理解任务，即使 checkpoint 损坏。

task_context 应包含：

- `intent`：用户原始意图的自然语言描述
- `goal`：结构化目标（由 FunctionGemma 解析后的 TaskDraft 核心字段）
- `memory_summary`：SummaryMemoryService 产出的用户偏好与上下文摘要（如存在）
- `constraints`：任务约束，如 `permission_level`、`deadline`、`allowed_tools`

---

## 五、Handoff 触发条件

以下任一条件成立时，control-plane 或 runtime 应发起 handoff：

1. **能力不匹配**：当前 runtime 缺少执行所需的 tool 或能力（如需要文件系统但在 cloud runtime）。
2. **设备状态变化**：当前 runtime 报告电量不足、网络断开、资源不足等。
3. **用户手动 override**：用户在 web-console 或 mobile-host 主动切换执行位置。
4. **任务升级策略**：task 复杂度超过当前 runtime 能力阈值（由 RoutingPolicy 定义）。
5. **权限升级需求**：任务执行过程中发现需要 `cloud_ok` 权限，而当前 runtime 无云端能力。

⚠️ **开放问题**：runtime 主动申请 handoff 的接口如何设计？是 runtime 调用 control-plane API，还是 control-plane 主动轮询 runtime 状态？

---

## 六、Handoff 必需的 Event 记录

每次 handoff 必须产生以下 Events（详细结构见 `event_and_observability.md`）：

| Event 类型 | 时机 | 发出方 |
|-----------|------|--------|
| `handoff.initiated` | HandoffPayload 创建完成，尚未发送 | control-plane |
| `handoff.dispatched` | HandoffPayload 已发送给目标 runtime | control-plane |
| `handoff.received` | 目标 runtime 确认收到 payload | 目标 runtime |
| `handoff.accepted` | 目标 runtime 确认可以执行，新 Run 创建 | 目标 runtime |
| `handoff.rejected` | 目标 runtime 拒绝（含拒绝原因）| 目标 runtime |

拒绝后，control-plane 必须将 Task 返回 `routing` 状态，重新评估路由。

---

## 七、Handoff 幂等性要求

- 接收方在收到 HandoffPayload 时，必须先用 `handoff_id` 检查是否已处理过。
- 若已处理，直接返回成功（不重复创建 Run）。
- 幂等校验状态必须持久化，不可仅存内存。
