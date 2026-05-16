# Device 与身份协议

> **状态**：已确认核心字段，次级问题见第五节。
> **上位文档**：`docs/architecture/system-design.md`、`docs/project/project_guidance_full_zh.md`
> **谁依赖本文档**：control-plane（设备注册 API）、mobile-host（注册流程）、desktop-runtime（注册流程）、RoutingEngine（permission_scope 消费）、web-console（设备列表视图）、Codex（写 device.schema.json 前必读）

---

## 一、Device 的定义与定位

Device 是一个已向 control-plane 注册的、属于某一用户账号的物理或逻辑计算节点。

- Device 是**身份对象**，记录"这个节点是谁、属于谁、被允许做什么"。
- Device 不记录实时运行状态（电量、负载、是否在线）——那些是 **runtime heartbeat** 的职责（见 `routing_policy.md` §2.2）。
- Cloud runtime **不是** Device：cloud 是一个服务端点，不通过 Device 注册，由 control-plane 直接管理其可用性。
- 一个用户账号下可以有多个 Device（例如 iPhone + MacBook）。

---

## 二、Device 对象字段定义

| 字段名 | 类型 | 是否必填 | 语义 | 被谁使用 |
|--------|------|---------|------|---------|
| `schema_version` | string | 必填 | schema 版本，格式 `"1.0.0"` | 兼容性解析 |
| `device_id` | string (UUID) | 必填 | 设备全局唯一标识，注册时由 control-plane 生成 | 所有对象引用（Run.runtime、Event.source、heartbeat）|
| `account_id` | string (UUID) | 必填 | 所属用户账号 ID，一个账号下可有多台设备 | control-plane 多设备隔离、RoutingEngine |
| `device_name` | string | 必填 | 用户可读的设备名称（如 "Yanjin's iPhone"），注册时用户填写，可修改 | web-console 设备列表、审批通知 |
| `runtime_type` | enum | 必填 | 设备承载的 runtime 类型：`mobile` / `desktop` | RoutingEngine 软排序、observability |
| `permission_scope` | enum | 必填 | 该设备允许处理的最高权限级别：`local_only` / `private_lan` / `cloud_ok` | RoutingEngine 硬过滤（设备侧约束）|
| `registered_at` | timestamp (ISO 8601) | 必填 | 设备首次注册时间 | 审计、设备列表排序 |
| `last_seen_at` | timestamp (ISO 8601) | 必填 | 最近一次 heartbeat 的时间，由 control-plane 在收到 heartbeat 时更新 | RoutingEngine 判断在线状态的基础数据 |
| `is_active` | bool | 必填 | 设备是否处于激活状态（用户可手动停用，停用后不参与路由）| RoutingEngine 硬过滤 |

### 字段说明

**`permission_scope` 与 `permission_level` 的关系**：

- `permission_level` 是 **Task 的属性**：声明某个任务的数据隐私要求（这个任务的数据最高可以到哪里）。
- `permission_scope` 是 **Device 的属性**：声明这台设备被允许处理的最高权限级别（这台设备最高可以接什么任务）。
- RoutingEngine 在硬过滤时同时检查两者：Task 的 `permission_level` 不能超过目标 Device 的 `permission_scope`。

例：用户把家里的台式机设置为 `permission_scope: local_only`（不想让这台机器接云端数据），即使任务本身是 `cloud_ok`，也不会路由到这台机器。

**`runtime_type` 枚举说明**：

- `mobile`：手机端，承担任务入口、本地 parser 和轻执行。
- `desktop`：桌面端，承担主要本地执行、文件系统、终端工具链。
- 注：cloud 不在此枚举中，cloud 是服务端点，不通过 Device 注册。

---

## 三、Device 生命周期

### 3.1 注册（Register）

- mobile-host 首次启动时，向 control-plane 的设备注册 API 提交注册请求。
- desktop-runtime 首次启动时，同样向 control-plane 注册。
- control-plane 生成 `device_id`，返回给设备，设备持久化存储。
- 注册后，设备需要立刻发送第一次 heartbeat，以建立在线状态。

注册请求携带的字段：`device_name`、`runtime_type`、`permission_scope`。

### 3.2 Heartbeat（心跳）

- 设备在线时，runtime 每 **15 秒**向 control-plane 发送一次 heartbeat。
- Heartbeat 携带实时状态（`is_online`、`battery_level`、`cpu_load`、`network_type`、`active_run_count` 等，字段定义见 `routing_policy.md` §2.2）。
- control-plane 收到 heartbeat 时，更新 Device 的 `last_seen_at`。
- 超过 **30 秒**未收到 heartbeat，RoutingEngine 将该设备视为离线（不在 Device 对象上存储 `is_online`，由 RoutingEngine 在路由时实时计算 `last_seen_at < now - 30s`）。

### 3.3 停用（Deactivate）

- 用户在 web-console 可以将某台设备标记为 `is_active: false`。
- 停用的设备不参与路由（RoutingEngine 硬过滤），但历史 Run、Event、Artifact 记录保留。
- v1 不实现设备删除（保留历史可追溯性）。

---

## 四、Observability 视图字段（设备列表）

web-console 的设备列表视图每行展示：

| 字段 | 来源 |
|------|------|
| `device_name` | Device 对象 |
| `runtime_type` | Device 对象 |
| `permission_scope` | Device 对象 |
| `is_online` | 实时计算（`last_seen_at < now - 30s` → offline）|
| `registered_at` | Device 对象 |
| `active_run_count` | 最新 heartbeat 数据 |

---

## 五、开放问题（⚠️ 不阻断 v1 schema，实现前需确认）

1. **设备认证机制**：设备向 control-plane 注册和发送 heartbeat 时，如何证明自己的身份？建议 v1 使用简单的 API Key（注册时生成，设备持久化存储），不依赖 OAuth/PKI。认证机制不影响 Device 对象 schema，但影响注册 API 的请求头设计。

2. **account_id 的来源**：用户账号系统是否已有定义？control-plane 是否需要管理账号注册，还是 account_id 由外部身份系统（如 Firebase Auth、自研账号系统）提供？v1 可以先将 account_id 视为外部输入，不在本项目中实现账号注册。

3. **`permission_scope` 的可修改性**：用户是否可以在设备注册后修改 `permission_scope`？建议允许，修改后对新 Task 生效，不影响已在执行的 Run。
