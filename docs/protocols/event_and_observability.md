# Event 与 Observability 协议

> **状态**：骨架草稿，待人工决策后补充细节。
> **上位文档**：`docs/architecture/system-design.md`、`docs/project/project_guidance_full_zh.md`
> **谁依赖本文档**：control-plane（Event API、ObservabilityService）、所有 runtime（事件回写）、web-console（timeline、replay、audit 视图）、mobile-host（任务状态更新）

---

## 一、Event 的设计原则

- 所有路由决策、handoff、approval、run 状态变化都必须产生 event，不允许无 event 的静默状态变更。
- Event 是不可变的：写入后不得修改，只能追加新 event。
- Event 是 control-plane 的单一审计源：replay、timeline、可观测性均基于 event stream 重建。
- Event 由发生事件的实体（runtime 或 control-plane）产生，统一写入 control-plane 的 Event API。
- Runtime 不得直接修改 Task / Run 状态；所有状态变更必须通过回写 Event 触发。

---

## 二、Event 基础字段（所有 Event 类型共享）

| 字段名 | 类型 | 是否必填 | 语义 | 被谁使用 |
|--------|------|---------|------|---------|
| `event_id` | string (UUID) | 必填 | 全局唯一事件 ID | 去重、索引 |
| `event_type` | string (enum) | 必填 | 事件类型（见下方分类） | 路由、UI 渲染、过滤 |
| `task_id` | string (UUID) | 必填 | 所属 Task | 按 Task 查询所有 events |
| `run_id` | string (UUID) | 条件必填 | 所属 Run（若事件与 Run 相关则必填）| Run 级别 timeline |
| `schema_version` | string | 必填 | 本 event payload 使用的 schema 版本 | 兼容性解析 |
| `source` | string (enum) | 必填 | 事件来源：`control-plane` / `mobile` / `desktop` / `cloud` | 分布式追踪、debug |
| `emitted_at` | timestamp (ISO 8601) | 必填 | 事件产生时间（来源方本地时间）| 时序排序 |
| `recorded_at` | timestamp (ISO 8601) | 必填 | control-plane 接收并持久化时间 | 服务端时序基准 |
| `payload` | object | 必填 | 类型特定字段（见各事件类型说明）| 业务逻辑消费 |

---

## 三、Event 类型分类与 payload 必需字段

### 3.1 Task 生命周期事件

| event_type | 触发时机 | payload 必需字段 |
|-----------|---------|----------------|
| `task.submitted` | Task 从 `draft` 提交至 `pending` | `task_title`、`intent_summary`、`permission_level`、`submitted_by`（device_id）|
| `task.completed` | Task 进入 `completed` | `total_run_count`、`total_duration_ms`、`artifact_ids` |
| `task.failed` | Task 进入 `failed` | `failure_reason`、`last_run_id`、`total_attempt_count` |
| `task.cancelled` | Task 被用户取消 | `cancelled_by`（user / system）、`cancel_reason` |

### 3.2 路由事件

| event_type | 触发时机 | payload 必需字段 |
|-----------|---------|----------------|
| `route.started` | RoutingEngine 开始评估 | `routing_inputs`（设备状态快照、permission_level、task_capability_needs）|
| `route.decided` | 路由决策完成 | `target_runtime`、`decision_reason`（人可读）、`policy_version`、`considered_runtimes`（被评估的 runtime 列表）|
| `route.failed` | 无可用 runtime | `failure_reason`（permission_blocked / no_capable_runtime / all_offline）|

### 3.3 Run 生命周期事件

| event_type | 触发时机 | payload 必需字段 |
|-----------|---------|----------------|
| `run.created` | 新 Run 被创建（接收 HandoffPayload 后）| `runtime`、`attempt_index`、`handoff_id`（若来自 handoff）|
| `run.started` | Runtime 开始实际执行 | `model_id`（使用的本地/云端模型）、`tool_set`（本次 Run 可用 tools 列表）|
| `run.step_completed` | 一个执行步骤完成 | `step_index`、`step_description`、`tool_calls_in_step`、`checkpoint_saved`（bool）|
| `run.checkpoint_saved` | Checkpoint 持久化完成 | `checkpoint_index`、`storage_ref`（checkpoint 存储引用）|
| `run.paused` | Run 进入 paused | `pause_reason`（approval_required / user_request）|
| `run.resumed` | Run 从 paused 恢复 | `resumed_by`（user / system）|
| `run.completed` | Run 成功完成 | `duration_ms`、`step_count`、`artifact_ids` |
| `run.failed` | Run 失败 | `failure_reason`、`failure_category`（model_error / tool_error / timeout / resource）、`is_retryable`（bool）|

### 3.4 Handoff 事件

| event_type | 触发时机 | payload 必需字段 |
|-----------|---------|----------------|
| `handoff.initiated` | Handoff 发起，payload 准备完成 | `handoff_id`、`source_run_id`、`target_runtime`、`initiated_by`、`reason` |
| `handoff.dispatched` | Payload 已发送给目标 runtime | `handoff_id`、`dispatched_at` |
| `handoff.received` | 目标 runtime 确认收到 | `handoff_id`、`received_at` |
| `handoff.accepted` | 目标 runtime 开始执行，新 Run 创建 | `handoff_id`、`new_run_id` |
| `handoff.rejected` | 目标 runtime 拒绝 | `handoff_id`、`rejection_reason` |

### 3.5 Approval 事件

| event_type | 触发时机 | payload 必需字段 |
|-----------|---------|----------------|
| `approval.requested` | Approval 请求创建 | `approval_id`、`trigger_reason`、`action_description`（用户可读的待审批动作描述）、`expires_at` |
| `approval.granted` | 用户批准 | `approval_id`、`granted_by`（device_id）、`granted_at` |
| `approval.rejected` | 用户拒绝 | `approval_id`、`rejected_by`、`rejection_reason` |
| `approval.expired` | 超时未响应 | `approval_id`、`expired_at` |

### 3.6 Artifact 事件

| event_type | 触发时机 | payload 必需字段 |
|-----------|---------|----------------|
| `artifact.created` | Artifact 对象在 control-plane 创建 | `artifact_id`、`artifact_type`（file / text / structured）、`created_by_run_id` |
| `artifact.uploaded` | 实际内容上传完成 | `artifact_id`、`storage_ref`、`size_bytes`、`content_hash` |

---

## 四、Observability 视图最小字段集

以下是各视图在 web-console 和 mobile-host 中展示所需的**最小字段**，其他字段可在详情页渐进加载。

### 4.1 任务列表视图

每行 Task 需要：`task_id`、`task_title`、`current_state`、`current_runtime`（若 running）、`created_at`、`last_updated_at`、`pending_approval`（bool）

### 4.2 任务详情视图

- Task 基本信息：intent_summary、permission_level、total_run_count
- Event timeline：按 `emitted_at` 排序的全量 event 列表，每条显示 `event_type`、`source`、`emitted_at`、payload 摘要
- Run 列表：每个 Run 的 `run_id`、`runtime`、`state`、`attempt_index`、`duration_ms`
- Checkpoint 列表：checkpoint_index、checkpoint_saved_at
- Artifact 列表：artifact_id、artifact_type、created_by_run_id
- Pending approvals：若有，显示 approval 请求详情

### 4.3 路由决策视图（Route Timeline）

- 每次 `route.decided` event 展开为一行：target_runtime、decision_reason、policy_version、considered_runtimes
- 支持时序滚动

### 4.4 Approval 视图

- 列出所有 `approval.requested` 且尚未处理的 approval
- 每条显示：action_description、trigger_reason、expires_at、关联的 task_id / run_id

---

## 五、Event 存储与查询要求

- Events 按 `task_id` + `emitted_at` 索引，支持按 Task 获取完整 event stream。
- Events 支持按 `event_type` 过滤（用于 timeline 和 replay）。
- Events 不可删除（append-only），只能在过期策略下归档。
- Control-plane 必须提供 replay API：给定 `task_id`，按时序返回全量 events。

---

## 六、开放问题（⚠️ 需要人工决策）

1. **事件存储选型**：使用关系型数据库（PostgreSQL）、时序数据库，还是专用 event store？这影响 replay 和 timeline 查询的性能边界。
2. **`run.step_completed` 颗粒度**：步骤是否对应 LLM 的每个 tool call，还是用户可见的更粗粒度操作？前者审计更详细，后者 event 数量更可控。
3. **事件的实时推送**：web-console 和 mobile-host 是否需要 WebSocket/SSE 实时接收 events？还是 polling 就够了？这影响 control-plane API 的设计复杂度。
