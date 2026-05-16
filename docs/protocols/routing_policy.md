# Routing Policy 协议

> **状态**：已确认核心设计（2026-05-10），次级问题见第六节。
> **上位文档**：`docs/architecture/system-design.md`、`docs/project/project_guidance_full_zh.md`
> **对应 ADR**：`docs/decisions/ADR-003-routing-pure-system-signals.md`（待创建）
> **谁依赖本文档**：control-plane（RoutingEngine、policy-engine）、所有 runtime（能力注册）、web-console（route timeline 展示）、Codex（实现 RoutingEngine 前必读）

---

## 一、Routing 的设计原则

### 1.1 纯系统信号路由（已决策，方案 A）

RoutingEngine 的路由决策**完全基于客观系统信号**，不依赖任何模型输出的"建议路由目标"。

- FunctionGemma 在 mobile 端的职责是：解析用户意图 → 生成结构化 TaskDraft。**不产出路由建议**。
- TaskDraft 里**不包含** `suggested_runtime` 字段。
- 所有路由决策由 control-plane 的 RoutingEngine 根据系统信号独立做出。

**理由**：
- 模型输出不可审计——路由决策必须有明确的、可复现的依据，不允许"模型觉得应该去 cloud"这类不透明决策。
- 系统信号（设备状态、权限、工具能力）是客观的、可验证的、可记录的。
- 符合文档已确立的原则："routing 不能纯模型化"。

### 1.2 每次路由必须产生 Event

每次路由决策（成功或失败）都必须产生 event 记录，包含：决策结果、评估过的 runtime 列表、每个 runtime 的排除原因或得分。详见 `event_and_observability.md` 中的 `route.decided` 和 `route.failed` 事件定义。

### 1.3 路由是 control-plane 的职责

Runtime 不参与路由决策，只负责：
- 向 control-plane 注册自身能力（工具列表、模型列表、当前状态）
- 接受或拒绝 HandoffPayload（拒绝时说明原因）

RoutingEngine 在 control-plane 内部运行，消费 runtime 注册的能力信息和当前状态快照做出决策。

---

## 二、RoutingEngine 的输入信号

RoutingEngine 在做路由决策时，消费以下**四类系统信号**：

### 2.1 Task 本身的约束（来自 TaskDraft / Task 对象）

| 信号字段 | 类型 | 含义 | 如何影响路由 |
|---------|------|------|------------|
| `permission_level` | enum | `local_only` / `private_lan` / `cloud_ok` | **硬性过滤**：直接排除不满足权限要求的 runtime |
| `required_tools` | list | Task 执行所需的 tool 名称列表（由 TaskDraft 携带）| **硬性过滤**：排除不具备所需 tool 的 runtime |
| `required_capabilities` | list | 非工具能力需求（如 `file_system` / `browser` / `gpu_inference`）| **硬性过滤** |
| `complexity_hint` | enum | `light` / `medium` / `heavy`（由 FunctionGemma 在解析时评估）| **软性偏好**：heavy 任务优先路由到 desktop/cloud |
| `estimated_duration` | string? | 预估执行时长（可选）| 长任务偏好 cloud（有持久化保障）|

### 2.2 Runtime 的当前状态（来自 runtime heartbeat）

每个 runtime 定期向 control-plane 上报心跳，携带以下状态快照：

| 状态字段 | 类型 | 含义 | 如何影响路由 |
|---------|------|------|------------|
| `runtime_id` | string | Runtime 的唯一标识（device_id + runtime_type）| 标识目标 |
| `is_online` | bool | Runtime 是否在线 | **硬性过滤**：离线的 runtime 不参与路由 |
| `battery_level` | int? | 电量百分比（移动设备）| 低电量时降低移动端优先级 |
| `network_type` | enum | `wifi` / `cellular` / `offline` | cellular 时降低 cloud 路由优先级 |
| `cpu_load` | float? | 当前 CPU 负载（0-1）| 高负载时降低优先级 |
| `available_memory_mb` | int? | 可用内存 | 不足时降低优先级 |
| `active_run_count` | int | 当前正在执行的 Run 数量 | v1 约束：只有 0 才可接收新任务（单 Run 约束）|
| `last_heartbeat_at` | timestamp | 最后心跳时间 | 超过阈值（建议 30s）视为离线 |

### 2.3 Runtime 的能力注册（来自 runtime 启动时的注册接口）

每个 runtime 在启动时向 control-plane 注册其能力，注册信息在能力变化时可更新：

| 能力字段 | 类型 | 含义 |
|---------|------|------|
| `runtime_type` | enum | `mobile` / `desktop` / `cloud` |
| `supported_tools` | list | 该 runtime 支持的 tool 名称 + schema_version |
| `supported_capabilities` | list | 非工具能力列表（`file_system`、`browser`、`terminal`、`gpu_inference` 等）|
| `supported_models` | list | 可用的本地/云端模型列表（model_id + quantization）|
| `permission_scope` | enum | 该 runtime 能接受的最高权限级别（`local_only` / `private_lan` / `cloud_ok`）|

### 2.4 Policy 配置（来自 policy-engine，管理员/用户可配置）

| 配置项 | 类型 | 含义 | 默认值 |
|--------|------|------|-------|
| `prefer_local` | bool | 在能力相当时优先本地 runtime | `true` |
| `cloud_fallback_enabled` | bool | 是否允许 fallback 到 cloud | `true`（需 `cloud_ok` 权限）|
| `mobile_as_primary_parser` | bool | 移动端始终承担解析和轻执行 | `true` |
| `policy_version` | string | 当前生效的 policy 版本，写入 `route.decided` event | `"1.0.0"` |

---

## 三、路由决策算法（v1）

v1 采用**分阶段硬过滤 + 优先级软排序**的确定性算法，不使用评分模型。

### 阶段一：硬过滤（任一条件不满足则排除）

对每个在线 runtime 依次检查：

1. `is_online == true` 且 `last_heartbeat_at` 在 30s 内
2. `active_run_count == 0`（v1 单 Run 约束）
3. `permission_scope` 满足 Task 的 `permission_level` 要求
4. `supported_tools` 包含 Task 的所有 `required_tools`
5. `supported_capabilities` 包含 Task 的所有 `required_capabilities`

通过硬过滤的 runtime 进入软排序阶段。若没有 runtime 通过，路由失败，产生 `route.failed` event。

### 阶段二：软排序（优先级规则，按顺序应用）

在通过硬过滤的 runtime 中，按以下规则选出优先级最高的：

| 优先级 | 规则 | 说明 |
|--------|------|------|
| 1 | Task 的 `permission_level == local_only` | 强制选当前发起设备，无需排序 |
| 2 | `complexity_hint == light` | 优先移动端（local-first 原则）|
| 3 | `prefer_local == true`（policy 配置）| 优先选 desktop > mobile > cloud |
| 4 | `battery_level` 充足（>= 20%）| 低电量设备降级 |
| 5 | `cpu_load` 最低 | 负载最轻的 runtime 优先 |
| 6 | `runtime_type == cloud`（最后 fallback）| 仅在无本地 runtime 可用时选 cloud |

**平局处理**：若两个 runtime 优先级相同，选 `runtime_type` 字母序较小的（确定性，可复现）。

### 阶段三：输出

RoutingEngine 输出：
- `target_runtime`：选中的 runtime_id
- `decision_reason`：人可读的决策原因（如 `"desktop runtime selected: local-first policy, sufficient capability"`）
- `considered_runtimes`：所有参与评估的 runtime 列表，含每个 runtime 的评估结果（通过/排除原因）
- `policy_version`：本次使用的 policy 版本

以上全部字段写入 `route.decided` event payload。

---

## 四、路由失败处理

当没有 runtime 通过硬过滤时，产生 `route.failed` event，Task 进入 `failed` 状态。

| 失败原因 | `failure_reason` 值 | 后续处理 |
|---------|---------------------|---------|
| 所有 runtime 离线 | `no_runtime_online` | 等待 runtime 上线后可由用户触发重试（创建新 Run）|
| 权限阻断（无满足权限的 runtime）| `permission_blocked` | Task 进入 `failed`，不自动重试，用户需重新创建 Task |
| 能力缺口（所有 runtime 都缺少必要 tool）| `capability_gap` | Task 进入 `failed`，用户需在合适设备上安装对应 tool 后重试 |
| cloud fallback 被禁用且无本地 runtime | `local_only_no_runtime` | 同权限阻断 |

---

## 五、Policy 版本管理

- Policy 配置存储在 `packages/policy-engine/` 中，带版本号。
- Policy 更新不需要 ADR，但需要 changelog 记录。
- 每次路由决策在 `route.decided` event 中记录 `policy_version`，确保历史路由决策可溯源。
- policy 的 MAJOR 变更（改变路由结果的变更）必须写 ADR。

---

## 六、开放问题（次级，不阻断 v1 schema 编写）

1. **Heartbeat 间隔与离线阈值**：runtime 多久上报一次心跳？超过多久算离线？建议心跳 15s，超过 30s 视为离线。实现时确认。
2. **`complexity_hint` 的评估方式**：`light` / `medium` / `heavy` 由谁评估、怎么评估？建议 v1 由 FunctionGemma 在生成 TaskDraft 时根据 intent 复杂度简单分类，实现时给出分类规则。
3. **用户触发重路由**：任务 `failed` 后，用户重试是否重走 RoutingEngine，还是用户可以指定目标 runtime？建议 v1 先重走 RoutingEngine，用户 override 留 v2。
4. **`required_tools` 的来源**：TaskDraft 里的 `required_tools` 字段由 FunctionGemma 填写吗？还是 control-plane 根据 intent 推断？建议由 FunctionGemma 在 TaskDraft 中直接声明，control-plane 不重复推断。
