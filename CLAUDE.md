# Gemma4all — Cross-Device Task System

跨设备 Gemma 任务系统。用户在手机提交自然语言任务，系统通过 RoutingEngine 决定在哪台设备（手机/桌面/云）上运行，设备间通过 HandoffPayload 传递上下文，全程通过事件流可观测。

---

## 四条不可违反的设计原则

1. **Task-first**：所有工作围绕 Task 对象，Run 是 Task 的执行尝试，Event 是唯一状态变更入口
2. **Schema-first**：所有类型从 `packages/schemas/` 中的 JSON Schema 生成，不在代码里手写类型定义
3. **Control-plane-first**：所有状态变更通过 `POST /v1/events → EventService.processStateTransition`，任何 route handler 不得直接修改 Task.current_state 或 Run.state
4. **Local-first**：默认 `permission_level = private_lan`，不经用户明确授权不上云

---

## 项目结构

```
Gemma4all(H)/
├── docs/
│   ├── protocols/          ← 七份协议文档，所有代码的上位约束，改代码前先看对应协议
│   └── decisions/          ← ADR 记录
├── packages/
│   └── schemas/            ← 40 个 JSON Schema 文件（Draft 2020-12）
│       ├── common.schema.json
│       ├── task.schema.json / run.schema.json / event.schema.json …
│       ├── event-input.schema.json   ← POST /v1/events 的输入 schema（无 event_id/recorded_at）
│       └── events/         ← 每种 event_type 的 payload schema
├── services/
│   ├── control-plane/      ← TypeScript / Node.js / Express
│   │   └── src/
│   │       ├── routes/     ← HTTP 路由层，只做 schema 校验和转发
│   │       ├── services/   ← 业务逻辑（EventService、TaskService、RoutingEngine…）
│   │       ├── repositories/ ← 数据访问接口 + InMemory 实现
│   │       └── types/      ← 从 schema 生成的类型（不要手写）
│   └── desktop-runtime/    ← Python（litert-lm-api-nightly + httpx）
│       └── src/desktop_runtime/
│           ├── adapters/   ← types.py（协议类型）、inference_adapter.py（LiteRT-LM 封装）
│           ├── client/     ← control_plane_client.py（httpx HTTP 客户端）
│           ├── worker.py   ← 推理循环（execute_run）
│           ├── handoff_receiver.py
│           ├── heartbeat_service.py
│           ├── tool_registry.py
│           └── main.py     ← asyncio 入口，从 env 读配置
└── apps/
    └── mobile-host/        ← Android / Kotlin / Jetpack Compose / Hilt / Retrofit
        └── app/src/main/java/com/gemma4all/mobilehost/
            ├── models/     ← Kotlin data class，字段与 JSON Schema 对齐
            ├── services/   ← HeartbeatService、ParserRouterService（FunctionGemma 调用）
            ├── client/     ← ControlPlaneApi（Retrofit）
            └── ui/         ← screens + viewmodels（Compose）
```

---

## 协议文档速查（改代码前必须读对应文档）

| 你要改的 | 先读 |
|---------|------|
| Task/Run 状态机 | `docs/protocols/task_and_run_lifecycle.md` |
| EventService、所有 event_type | `docs/protocols/event_and_observability.md` |
| HandoffPayload、HandoffService | `docs/protocols/handoff_protocol.md` |
| RoutingEngine、心跳、能力注册 | `docs/protocols/routing_policy.md` |
| ApprovalService、权限边界 | `docs/protocols/approval_and_permission.md` |
| Device 注册、permission_scope | `docs/protocols/device_and_identity.md` |
| 任何 schema 文件 | `docs/protocols/schema_format_and_versioning.md` |

---

## 关键规则

### 事件溯源（不可绕过）
- Task.current_state 和 Run.state **只能**通过 `EventService.processStateTransition(event)` 修改
- Route handler 收到请求后，调用 service 方法，**不得**直接调用 `taskService.updateState()` 或 `runService.updateState()`
- Desktop runtime 通过 `EventReporter.report()` → `POST /v1/events` 回写状态，不走其他路径

### Schema 使用规则
- `POST /v1/events` 的 body 用 `event-input.schema.json` 校验（无 event_id、recorded_at）
- `event_id` 和 `recorded_at` 由 `EventService.append()` 服务端赋值
- Kotlin DTO 字段必须与对应 JSON Schema 字段名（snake_case）和类型完全对齐

### 函数调用格式
- FunctionGemma 输出格式：`{"name": "tool_name", "arguments": {...}}`
- 字段名是 `arguments`，不是 `parameters`（与 `function-call.schema.json` 对齐）

### 心跳字段
- 心跳 POST 必须包含：`device_id`, `is_online`, `network_type`, `active_run_count`, `supported_tools`, `supported_capabilities`
- 这 6 个字段是 required，遗漏会导致 schema 校验 400

---

## 当前开发阶段

```
Phase 1 — 协议文档        ✅ 完成（7 份文档，所有决策锁定）
Phase 1 — JSON Schema     ✅ 完成（40 个文件）
Phase 2 — 代码骨架        ✅ 完成（3 个服务，所有 bug 已修复）
Phase 3 — 核心实现        🔄 进行中
  Batch 1: 全部 ✅
  Batch 2: 全部 ✅（EventService.append/queryByTaskId，ApprovalService 含 SQLite 持久化）
  Batch 3: 全部 ✅（EventService.processStateTransition，HandoffService.create+dispatch）
  Batch 4:
    TaskService.createFromDraft（含路由触发）  ✅ 已实现
    Mobile FunctionGemma ParserRouterService  ❌ 延后（iOS 推理暂缓）

Phase 4（新增，待规划）
  iOS on-device inference（等 LiteRT-LM Metal GPU bug #6745 修复）
  实时推送（WebSocket/SSE，目前 polling）
  Memory 对象（v1 只有 task_context.memory_summary 可选字段）
  桌面 GUI（macOS menu bar app）
```

---

## 缺失的协议文档（实现前需补充）

以下三份文档还未创建，对应功能实现前必须先写：

- `docs/protocols/tooling_and_function_schema.md` — 工具分类、capability 注册格式、FunctionGemma function schema 格式
- `docs/protocols/runtime_adapter_interface.md` — RuntimeAdapter 能力注册格式
- `docs/protocols/prompt_contracts/parser-router-v1.0.md` — FunctionGemma parser-router 的 prompt contract

---

## 开放决策（实现时需确认）

| # | 问题 | 当前建议 |
|---|------|---------|
| P9 | 事件实时推送：WebSocket/SSE 还是 polling？ | v1 先 polling（GET /v1/tasks/:id/events），WebSocket 留 v2 |
| P10 | Memory 对象 v1 范围 | v1 只实现 `task_context.memory_summary` 可选字段，Memory 对象本身留 v2 |
