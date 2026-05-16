# Task 与 Run 生命周期协议

> **状态**：骨架草稿，待人工决策后补充细节。
> **上位文档**：`docs/architecture/system-design.md`、`docs/project/project_guidance_full_zh.md`
> **谁依赖本文档**：control-plane（Task API、Run API）、mobile-host（任务入口与状态显示）、desktop/cloud runtime（Run 接收与状态回写）、web-console（任务详情与历史视图）

---

## 一、Task 与 Run 的概念区别

### Task

Task 是用户意图的结构化表达，是系统的核心信息单元。

- 不是聊天消息，不是 prompt 字符串。
- 由 mobile-host 的本地 parser（FunctionGemma）从用户输入中提取，形成 TaskDraft。
- 经用户确认或自动提交后进入 control plane，成为正式 Task 对象。
- Task 的生命周期由 control plane 统一管理；runtime 不得直接修改 Task 状态。
- 一个 Task 代表一个完整的用户目标，可以跨多个 runtime 接续执行。

### Run

Run 是 Task 在某一具体 runtime 上的一次执行尝试。

- 每次 routing 决策将 Task 分配给一个 runtime，即创建一个新的 Run。
- Run 是有界的：它在某个 runtime 上开始，以 completed / failed / handed_off 终止。
- Run 不跨 runtime：一旦需要切换 runtime，当前 Run 终止，新 Run 在目标 runtime 创建。
- Run 的状态由执行它的 runtime 回写给 control plane；control plane 据此更新 Task 状态。

### 关键约束（已确认，ADR-001 记录）

- **v1 约束**：同一 Task 在任意时刻最多有一个 active Run（无并发执行）。并发执行能力留给 v2+。
- **重试语义（已决策：Option A）**：每次重试创建新 Run。理由：审计更清晰，每个 Run ID 唯一对应一次执行尝试，便于 replay 和 debug。`attempt_index` 字段在 Run 对象上自增，用于关联同一 Task 的多次尝试。

---

## 二、Task State Machine

### 状态列表

| 状态 | 含义 | 持有者 |
|------|------|--------|
| `draft` | 由 parser 产出的 TaskDraft，尚未提交给 control plane | mobile-host 本地 |
| `pending` | 已提交给 control plane，等待路由决策 | control-plane |
| `routing` | RoutingEngine 正在评估目标 runtime | control-plane |
| `scheduled` | 路由决策已完成，等待目标 runtime 接受 HandoffPayload | control-plane |
| `running` | 目标 runtime 已接受，至少有一个 active Run 正在执行 | runtime + control-plane |
| `paused` | 执行被暂停，等待用户 approval 或手动继续 | control-plane |
| `completed` | Task 已成功完成，所有产出（Artifact）已持久化 | control-plane |
| `failed` | Task 无法继续执行，已穷尽重试或被系统/用户终止 | control-plane |
| `cancelled` | 用户主动取消 | control-plane |

注：`draft` 状态存在于 mobile-host 本地，不进入 control plane；Task 进入 control plane 时直接从 `pending` 开始。

### 合法状态转移

```
draft         → pending       触发方：用户提交 / 自动提交
pending       → routing       触发方：control-plane（RoutingEngine 开始评估）
routing       → scheduled     触发方：control-plane（路由决策完成）
routing       → failed        触发方：control-plane（无可用 runtime，或权限阻断）
scheduled     → running       触发方：runtime（接受 HandoffPayload，Run 开始执行）
scheduled     → routing       触发方：control-plane（目标 runtime 拒绝，重新路由）
running       → paused        触发方：approval 请求触发 / 用户手动暂停
running       → running       触发方：handoff（跨 runtime 切换，Task 保持 running，Run 切换）
running       → completed     触发方：runtime 回写 Run 完成
running       → failed        触发方：runtime 回写 Run 失败 + 已穷尽重试
running       → cancelled     触发方：用户请求取消
paused        → running       触发方：approval 通过 / 用户手动继续
paused        → failed        触发方：approval 被拒绝 / approval 超时
paused        → cancelled     触发方：用户在 paused 状态下取消
```

### 每个状态必须记录的 Event

- `pending`：`task.submitted`
- `routing`：`route.started`
- `scheduled`：`route.decided`（含决策原因、目标 runtime）
- `running`：`run.started`
- `paused`：`approval.requested`（含触发原因）
- `completed`：`run.completed`、`task.completed`
- `failed`：`run.failed` 或 `route.failed`、`task.failed`（含失败原因）
- `cancelled`：`task.cancelled`

---

## 三、Run Lifecycle

### Run 字段草稿（待补充完整 schema）

| 字段名 | 类型 | 语义 | 被谁使用 |
|--------|------|------|---------|
| `run_id` | string (UUID) | Run 唯一标识 | control-plane、runtime、Event |
| `task_id` | string (UUID) | 所属 Task | control-plane、Event |
| `runtime` | enum | 执行 runtime：mobile / desktop / cloud | control-plane、observability |
| `state` | enum | Run 当前状态（见下） | runtime 回写、UI 展示 |
| `attempt_index` | integer | 第几次尝试（从 1 开始）| observability、重试逻辑 |
| `created_at` | timestamp | Run 创建时间 | observability |
| `started_at` | timestamp | Run 实际开始执行时间 | metrics |
| `ended_at` | timestamp | Run 终止时间（含 handed_off）| metrics |
| `checkpoint_count` | integer | 已保存的 checkpoint 数量 | observability、handoff 决策 |
| `handoff_payload_id` | string? | 发起 handoff 时关联的 HandoffPayload ID | handoff 追踪 |
| `error_detail` | string? | 失败原因描述 | observability、重试策略 |

### Run 状态列表

| 状态 | 含义 |
|------|------|
| `created` | HandoffPayload 已发送，runtime 尚未确认 |
| `started` | Runtime 已开始执行 |
| `step_completed` | 中间步骤完成，checkpoint 已保存（⚠️ 是否作为独立状态，还是仅作为 Event？待决策） |
| `paused` | 执行暂停，等待 approval 或用户操作 |
| `completed` | 执行成功，Task 目标达成 |
| `failed` | 执行失败 |
| `handed_off` | 本 Run 结束，任务已移交给新 runtime（触发新 Run 创建） |
| `cancelled` | 被用户或 control-plane 强制终止 |

### Task 与 Run 的状态联动规则（草稿）

- Task 变为 `running` 的条件：有一个 Run 进入 `started` 状态。
- Task 变为 `paused` 的条件：active Run 进入 `paused` 状态。
- Task 变为 `completed` 的条件：有一个 Run 进入 `completed` 状态。
- Task 变为 `failed` 的条件：所有 Run 均已失败 + 重试策略已穷尽。
- 发生 handoff 时：当前 Run → `handed_off`，Task 保持 `running`，新 Run 被创建并进入 `created` → `started`。

### 已确认决策（无遗留开放问题）

1. **重试创建新 Run（已决策）**：每次重试新建 Run，`attempt_index` 自增。
2. **`step_completed` 是纯 Event（已决策）**：不作为 Run 的独立状态。Run 状态保持简洁（started / paused / completed / failed / handed_off / cancelled），步骤进度通过 event stream 的 `run.step_completed` 事件观察。
3. **Handoff 时 Task 保持 `running`（已决策：Option A）**：Task 不经过 routing 中间状态，直接保持 `running`。当前 Run 进入 `handed_off`，新 Run 在目标 runtime 创建并进入 `created` → `started`。路由决策本身通过 `route.decided` event 记录，满足审计要求。
