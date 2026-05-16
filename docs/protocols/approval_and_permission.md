# Approval 与权限边界协议

> **状态**：骨架草稿，待人工决策后补充细节。
> **上位文档**：`docs/architecture/system-design.md`、`docs/project/project_guidance_full_zh.md`
> **谁依赖本文档**：control-plane（ApprovalService、policy-engine）、mobile-host（审批入口页面）、web-console（approval 视图）、所有 runtime（执行前权限校验）

---

## 一、Approval 的定位

Approval 是系统在执行高风险或权限敏感动作前，强制等待用户明确同意的机制。

- Approval 不是可选的 UX 增强，而是系统安全边界的一部分。
- 任何被标记为 `requires_approval: true` 的 tool 调用，或进入 approval 触发条件的 routing 决策，都必须暂停执行并等待用户响应。
- Approval 请求由 control-plane 的 ApprovalService 创建和管理；runtime 不得自行跳过 approval。
- 每个 approval 的创建、结果都必须产生 event 记录（见 `event_and_observability.md`）。

---

## 二、Approval 触发条件

以下任一条件成立时，必须创建 approval 请求并暂停 Run：

### 2.1 工具级触发（Tool-level）

由 tool schema 中的 `requires_approval` 字段声明：

- 文件删除、批量写入、格式化等不可逆文件操作
- 外部 API 调用（有副作用：发送邮件、提交表单、POST 请求）
- 系统级命令（终端命令执行、进程管理）
- 任何涉及真实金融操作的 tool call（支付、转账等 — 系统应拒绝执行，不仅仅是 approval）

### 2.2 路由级触发（Routing-level）

由 RoutingEngine 在路由决策时评估：

- 路由决策将 Task 发往 cloud runtime，但 Task 的 `permission_level` 为 `local_only` 或 `private_lan`（⚠️ 此情形应直接 block 而非 approval，见权限边界规则）
- 路由决策将 Task 发往非用户预期的 runtime（如用户明确指定了 desktop，但系统决策为 cloud）
- 首次跨设备 handoff（用户尚未在当前会话中授权该目标设备）

### 2.3 Task 属性触发（Task-level）

由 Task 创建时的属性或 TaskDraft 中的标记：

- Task 被标记为 `sensitive: true`（用户主动声明敏感）
- Task 的 intent 被 FunctionGemma parser 评估为高风险（parser 返回 risk_level: high）

### 2.4 用户显式触发（User-initiated）

- 用户在 web-console 或 mobile-host 点击"要求审批"手动发起

---

## 三、Approval 状态机

### 状态列表

| 状态 | 含义 |
|------|------|
| `pending` | Approval 请求已创建，等待用户响应 |
| `approved` | 用户明确批准，Run 可继续执行 |
| `rejected` | 用户明确拒绝，Run 进入 `failed`，Task 根据重试策略处理 |
| `expired` | 超时未响应（超时时长待定义），Run 进入 `failed` |
| `superseded` | Task 已被取消或已完成，approval 请求作废（无需用户操作）|

### 合法状态转移

```
pending  → approved     触发方：用户在 mobile-host 或 web-console 批准
pending  → rejected     触发方：用户在 mobile-host 或 web-console 拒绝
pending  → expired      触发方：control-plane 的 ApprovalService（超时轮询）
pending  → superseded   触发方：control-plane（Task 被取消或 Run 被终止）
```

### Approval 对 Run 状态的影响

- Approval 请求创建时：Run 进入 `paused`，Task 进入 `paused`（见 `task_and_run_lifecycle.md`）
- `approved`：Run 从 `paused` 恢复为 `started`，Task 恢复为 `running`
- `rejected` 或 `expired`：Run 进入 `failed`，Task 根据重试策略决定是否重试或进入 `failed`

---

## 四、Approval 对象字段草稿

| 字段名 | 类型 | 是否必填 | 语义 | 被谁使用 |
|--------|------|---------|------|---------|
| `approval_id` | string (UUID) | 必填 | 唯一标识 | event 关联、UI 查询 |
| `task_id` | string (UUID) | 必填 | 所属 Task | 按 Task 查询 approval |
| `run_id` | string (UUID) | 必填 | 所属 Run | Run 状态联动 |
| `state` | enum | 必填 | 当前 approval 状态 | UI 展示、Run 恢复 |
| `trigger_type` | enum | 必填 | 触发来源：`tool` / `routing` / `task_attribute` / `user` | 审计、风险分析 |
| `trigger_detail` | object | 必填 | 触发的具体内容（工具名 / 路由决策 / 标记来源）| UI 展示给用户 |
| `action_description` | string | 必填 | 人可读的待审批动作描述，直接展示给用户 | mobile-host 审批页面 |
| `requested_at` | timestamp | 必填 | 请求创建时间 | SLA 计算、超时判定 |
| `expires_at` | timestamp | 必填 | 超时时间（`requested_at` + 超时时长）| ApprovalService 超时轮询 |
| `responded_at` | timestamp | 条件填 | 用户响应时间（approved/rejected 时填写）| 审计 |
| `responded_by` | string | 条件填 | 响应用户的 device_id | 审计 |
| `response_note` | string | 可选 | 用户拒绝时的说明（可选填写）| 审计 |

### 开放问题（⚠️ 需要人工决策）

1. **Approval 超时时长**：默认超时设为多长？是否允许 Task 级别的自定义超时？
2. **超时后行为**：超时后是自动 `failed`，还是先通知用户再等一段时间？
3. **多设备通知**：用户同一账号下有多台设备，approval 通知应发送到哪台？发起任务的设备？所有设备？用户配置的主设备？

---

## 五、权限边界定义

### 5.1 三级权限边界

权限边界由 Task 在创建时声明，写入 Task 对象并携带至 HandoffPayload，在每次 routing 和 handoff 时强制校验。

| 权限级别 | 含义 | 允许的 runtime |
|---------|------|--------------|
| `local_only` | 数据和执行必须完全在发起设备上进行，不得离开本设备 | 仅发起设备（mobile 发起则只能 mobile 执行，desktop 发起则只能 desktop 执行）|
| `private_lan` | 可以在同一受信局域网内的设备之间移动，但不得接触云端服务 | 同账号下的 mobile + desktop（需在同一局域网内）|
| `cloud_ok` | 无限制，可路由到任何 runtime 包括 cloud | mobile、desktop、cloud 均可 |

### 5.2 权限边界对 Routing 的影响

- RoutingEngine 在评估路由时，必须将 `permission_level` 作为硬性约束（不是软性偏好）。
- 若所有符合权限要求的 runtime 都不可用，Task 进入 `failed`，原因为 `permission_blocked_no_viable_runtime`。
- RoutingEngine 不得向用户推荐违反 `permission_level` 的 runtime（即使该 runtime 能力更强）。

### 5.3 权限边界对 Handoff 的影响

- HandoffPayload 必须携带 `permission_level` 字段。
- 接收方 runtime 在接受 HandoffPayload 前，必须校验自己是否满足 `permission_level` 要求。
- 若接收方不满足权限要求，必须发送 `handoff.rejected` event，并注明 `rejection_reason: permission_violation`。
- Cloud runtime 收到 `local_only` 或 `private_lan` 的 HandoffPayload 时，必须拒绝，不允许以任何理由例外。

### 5.4 权限边界与 Approval 的关系

- 权限边界是**强制阻断**，不是 approval 的触发条件。
- 区别：`permission_level: local_only` + 路由到 cloud → 直接阻断，Task 进入 `failed`，**不走 approval 流程**。
- 例外情形（⚠️ 待决策，P7）：是否允许用户主动"提升"当前 Task 的权限级别（即用户确认可以上云后，将 `local_only` 升级为 `cloud_ok`）？若允许，则此升级操作本身需要 approval。v1 保守处理：**不允许**在 Task 执行中途升级权限级别，如需上云必须重新创建 Task 并声明 `cloud_ok`。

### 5.5 权限边界的来源

| 来源 | 说明 |
|------|------|
| 用户主动声明 | 在 mobile-host 输入任务时选择隐私级别 |
| Parser 推断 | FunctionGemma 根据 intent 内容推断（含个人信息、财务信息等时自动建议 `local_only`）|
| 系统默认值 | 若用户未声明，**默认 `private_lan`**（已决策，2026-05-10）|
| 用户账号设置 | 用户账号级别可配置全局默认权限级别 |

---

## 六、开放问题

### 已决策

1. ~~**默认权限级别**~~：**已决策**：默认 `private_lan`（2026-05-10）。
2. ~~**权限升级流程**~~：**已决策（v1 保守）**：v1 不允许执行中途升级权限级别，需重新创建 Task。

### 仍然开放（不阻断 v1 schema，但实现前需确认）

3. **局域网识别机制（P-LAN）**：`private_lan` 的"受信局域网"如何定义和验证？基于相同 IP 段？基于账号绑定的设备白名单？需要 desktop runtime 在同一网络下才算？建议 v1 先用"账号绑定设备白名单"作为局域网边界，无需 IP 检测。
4. **敏感内容自动检测**：FunctionGemma 的 risk_level 推断如何校准？误判率如何控制？v1 可先保守：仅对特定关键词触发，不依赖模型推断。
5. ~~**Approval 超时时长**~~：**已决策（2026-05-10）**：默认 **24 小时**，v1 不允许 Task 级自定义。超时后自动产生 `approval.expired` event，Run 进入 `failed`，Task 根据重试策略处理。
