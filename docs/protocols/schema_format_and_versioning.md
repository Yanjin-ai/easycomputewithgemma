# Schema 格式与版本管理协议

> **状态**：已确认核心格式决策（JSON Schema 2020-12），次级问题见第七节。
> **对应 ADR**：`docs/decisions/ADR-001-schema-format.md`（已创建）
> **上位文档**：`docs/architecture/system-design.md`、`docs/project/project_guidance_full_zh.md`
> **谁依赖本文档**：Codex（写 schema 文件前必须阅读）、所有运行时（解析与校验）、control-plane（schema 校验中间件）、AI 协作规范（schema 变更流程）

---

## 一、Schema 格式选择

### 1.1 推荐格式：JSON Schema (Draft 2020-12)

**理由**：

- 语言无关：后端（TypeScript/Python）、移动端（Kotlin/Swift）均可消费。
- 生态成熟：支持代码生成（TypeScript types via `json-schema-to-typescript`、Kotlin data class via `jsonschema2pojo`）。
- 可扩展：支持 `$ref`、`$defs`、allOf / oneOf 组合，适合核心对象之间的引用关系。
- 可验证：控制平面可在 API 接收请求时用 JSON Schema 做 runtime validation。

**约束**：

- 所有 schema 文件放在 `packages/schemas/` 目录下，文件命名为 `{object}.schema.json`。
- schema 文件不得包含业务逻辑，只定义结构、类型、必填字段和约束。
- TypeScript 类型从 schema 生成，不手写；手写类型与 schema 不同步是不允许的。

### 1.2 已决策（ADR-001 正式记录）

**选择：JSON Schema Draft 2020-12**（已确认，2026-05-10）

| 备选方案 | 为何未选 |
|---------|---------|
| TypeScript Zod schema | 仅限 TypeScript 生态；移动端 Kotlin/Swift 无法直接消费 |
| Protobuf 3 | 需要 proto 工具链；schema 文件对 LLM（Codex/Claude）不友好，AI 协作成本高 |
| OpenAPI 3.1 components | 偏向 REST API 描述，不适合纯内部对象定义 |

**配套约束（已锁定）**：
- TypeScript 类型统一从 JSON Schema 生成（工具：`json-schema-to-typescript`），不允许手写类型。
- Control-plane 在 HTTP middleware 层统一做 request schema validation，不在各 handler 内部重复校验。
- 详细决策理由见 `docs/decisions/ADR-001-schema-format.md`。

---

## 二、核心 schema 文件清单（v1 范围）

以下文件必须在开始 control-plane 和 runtime 实现之前全部完成：

| 文件路径 | 对应对象 | 状态 |
|---------|---------|------|
| `packages/schemas/device.schema.json` | Device | 待创建 |
| `packages/schemas/task.schema.json` | Task | 待创建 |
| `packages/schemas/run.schema.json` | Run | 待创建 |
| `packages/schemas/event.schema.json` | Event（基础字段 + 类型枚举）| 待创建 |
| `packages/schemas/events/` | 各 Event 类型的 payload schema | 待创建 |
| `packages/schemas/artifact.schema.json` | Artifact | 待创建 |
| `packages/schemas/handoff-payload.schema.json` | HandoffPayload | 待创建 |
| `packages/schemas/approval.schema.json` | Approval | 待创建 |
| `packages/schemas/tools/` | Tool schema（按 tool 分文件）| 待创建 |
| `packages/schemas/function-call.schema.json` | FunctionCall（FunctionGemma 输出格式）| 待创建 |
| `packages/schemas/task-draft.schema.json` | TaskDraft（FunctionGemma → control-plane 提交格式）| 待创建 |

---

## 三、schema_version 字段规范

### 3.1 版本字段命名

- 所有 schema 文件顶层包含 `schema_version` 字段（字符串类型）。
- 所有 API 请求/响应 payload 和 Event payload 均携带 `schema_version`，标明使用的 schema 版本。
- 格式：语义版本 `"MAJOR.MINOR.PATCH"`，例如 `"1.0.0"`。

### 3.2 版本升级规则

| 变更类型 | 版本升级 | 是否需要 ADR |
|---------|---------|------------|
| 新增可选字段 | PATCH (0.0.x) | 否 |
| 新增必填字段（有默认值）| MINOR (0.x.0) | 否，但需要 changelog |
| 删除字段 / 修改字段类型 / 修改字段语义 | MAJOR (x.0.0) | **必须写 ADR** |
| 修改枚举值 | MAJOR (x.0.0) | **必须写 ADR** |

### 3.3 向后兼容性要求

- MINOR 和 PATCH 版本必须保证向后兼容：旧版客户端发送的 payload 在新版 schema 下仍然有效。
- MAJOR 版本变更必须提供迁移说明（migration guide），并在 control-plane 保留旧版本的 API endpoint 至少一个 release 周期。

---

## 四、Prompt Contract 版本管理

Prompt contract 指 FunctionGemma 和 LLM 使用的 prompt 模板，其变更会影响输出格式。

### 4.1 存储位置

- Prompt contract 文件存储在 `docs/protocols/prompt-contracts/` 下。
- 每个 prompt contract 文件命名为 `{name}-v{MAJOR}.{MINOR}.md`，例如 `parser-router-v1.0.md`。

### 4.2 版本字段

- 每个 prompt contract 文件顶部包含 frontmatter：
  ```
  contract_version: "1.0"
  output_schema: "task-draft.schema.json@1.0.0"
  last_updated: "YYYY-MM-DD"
  ```
- Run 对象记录执行时使用的 `prompt_contract_version`，供 replay 和 debug 使用。

### 4.3 变更规则

- 输出格式（output_schema）不变的 prompt 改进：可直接更新，MINOR 版本升级。
- 输出格式变更（增删字段、修改结构）：必须同步更新对应的 output_schema，且必须 MAJOR 版本升级，写 ADR。

---

## 五、Tool Contract 版本管理

Tool contract 指 tool schema 中声明的工具接口，包括 name、description、input schema、output schema、requires_approval 等。

### 5.1 存储位置

- Tool schema 文件存储在 `packages/schemas/tools/` 下，每个 tool 一个文件：`{tool_name}.tool.schema.json`。
- 文件内包含 `schema_version` 字段。

### 5.2 Tool 注册与发现

- 每个 runtime 在启动时，向 control-plane 注册它支持的 tool 列表及各 tool 的 `schema_version`。
- RoutingEngine 在路由时，对比 Task 所需的 tool 列表与各 runtime 注册的 tool 列表，作为路由依据之一。
- Tool capability 的差异由 RuntimeAdapter 的能力声明（`ToolCapabilityRegistry`）维护。

### 5.3 变更规则

与 schema_version 规则一致：新增可选字段 PATCH；新增必填字段或行为变更 MINOR；删除、重命名、修改类型 MAJOR + ADR。

---

## 六、ADR 模板与编号规则

### 6.1 文件命名

```
docs/decisions/ADR-{NNN}-{kebab-case-title}.md
```

例如：
- `ADR-001-schema-format.md`（**第一个必须写**）
- `ADR-002-no-fork-edge-gallery.md`
- `ADR-003-functiongemma-parser-only.md`
- `ADR-004-v1-no-concurrent-runs.md`

### 6.2 ADR 模板结构

每个 ADR 文件必须包含以下章节：

```markdown
# ADR-{NNN}: {标题}

## 状态
[草案 / 已确认 / 已废弃 / 被 ADR-NNN 取代]

## 背景
为什么需要做这个决定？当前面临什么约束或问题？

## 决策
我们选择了什么？

## 考虑的其他方案
有哪些备选方案，为什么未被选择？

## 后果
这个决定带来了什么好处？有什么代价或风险？

## 相关文档
```

### 6.3 ADR-001 必须包含的内容

ADR-001-schema-format.md 是整个 schema 体系的基础，必须明确：

- 选择的 schema 格式（JSON Schema 版本 / TypeScript / Zod / Protobuf）
- 为什么不选其他格式（逐条说明）
- TypeScript 类型的生成方式（手写 vs 从 schema 生成）
- schema 文件的组织方式（单文件 vs 按对象分文件）
- schema validation 在 control-plane 中的位置（middleware vs per-handler）

---

## 七、剩余开放问题（次级，不阻断 schema 初稿编写）

1. **Response schema validation**：control-plane 对 response 是否也做 schema validation（防止自身返回不合规数据）？还是只校验 request？
2. **Schema CI 守护**：是否在 CI pipeline 中加入 schema lint / validation 步骤，防止 Codex 提交不合规 schema？建议加入，具体工具待定。
