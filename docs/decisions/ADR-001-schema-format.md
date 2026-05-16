# ADR-001: Schema 格式选择 — JSON Schema Draft 2020-12

## 状态

**已确认** — 2026-05-10

---

## 背景

本项目（跨设备 Gemma 任务系统）需要为六个核心对象（Device / Task / Run / Event / Artifact / HandoffPayload）以及 Approval、Tool、FunctionCall、TaskDraft 等辅助对象定义 schema。

Schema 格式的选择对以下方面有深远影响：

- **多语言消费**：control-plane 使用 TypeScript，移动端使用 Kotlin（Android）和 Swift（iOS）。
- **AI 工具可读性**：Codex 和 Claude Code 需要直接阅读和生成 schema 文件，格式需对 LLM 友好。
- **运行时校验**：control-plane 需要在 HTTP middleware 层对 request payload 做 schema validation。
- **代码生成**：TypeScript 类型、Kotlin data class 等需要从 schema 自动生成，避免手写类型与 schema 不同步。
- **版本管理**：schema 需要支持向后兼容的版本演进，并能追踪 breaking change。

---

## 决策

**选择 JSON Schema Draft 2020-12** 作为所有核心对象的规范 schema 格式。

具体约束：

1. **文件位置**：所有 schema 文件放在 `packages/schemas/` 目录下，命名为 `{object}.schema.json`。事件 payload schema 放在 `packages/schemas/events/` 子目录，tool schema 放在 `packages/schemas/tools/` 子目录。
2. **TypeScript 类型**：使用 `json-schema-to-typescript` 从 JSON Schema 自动生成 TypeScript 类型，**不允许手写类型**。手写类型与 schema 不同步是禁止的。
3. **Runtime validation**：control-plane 在 HTTP middleware 层统一做 request schema validation，使用 `ajv`（Another JSON Schema Validator）库，不在各 handler 内部重复校验。
4. **版本字段**：所有 schema 文件顶层包含 `schema_version` 字段（语义版本字符串，如 `"1.0.0"`），所有 API payload 和 Event payload 均携带此字段。
5. **$ref 使用**：核心对象之间的引用使用 JSON Schema `$ref` 和 `$defs` 机制，不允许在不同 schema 文件中重复定义相同字段。

---

## 考虑的其他方案

### TypeScript Zod schema

- **优势**：类型安全与运行时校验合一，对 TypeScript 开发体验极好。
- **为何未选**：项目是多语言系统（Kotlin/Swift 移动端），Zod 仅限 TypeScript 生态，无法直接被移动端消费。若以 Zod 为规范源，移动端需要手写类型，产生维护负担和不一致风险。

### Protobuf 3

- **优势**：高效序列化，天然支持多语言代码生成，版本兼容性强。
- **为何未选**：需要额外的 proto 工具链（`protoc` + 各语言插件）；.proto 文件对 LLM（Codex / Claude Code）的可读性和生成质量不如 JSON；AI 协作成本高。本项目的 AI 协作开发需求权重高于序列化性能需求。

### OpenAPI 3.1 components

- **优势**：schema 定义与 API 文档合一，生态工具丰富。
- **为何未选**：OpenAPI 偏向 REST API 接口描述，不适合纯内部对象（如 HandoffPayload、Event payload）的定义。强制绑定 API 文档格式会增加内部协议的描述复杂度。

---

## 后果

### 好处

- JSON Schema 文件是纯 JSON，对所有 LLM 高度可读，Codex 生成和 Claude Code 审查都能精确操作。
- 语言无关：通过 `json-schema-to-typescript`、`jsonschema2pojo` 等工具可为 TypeScript 和 Kotlin 生成类型，未来 Swift 也有 `JSONSchema` 库支持。
- `ajv` 是业界标准的 JSON Schema validator，在 Node.js/TypeScript 生态中性能和成熟度均有保障。
- 版本演进清晰：JSON Schema 的 `$ref`、`oneOf`、`allOf` 机制支持向后兼容的扩展。

### 代价与风险

- JSON Schema 文件较冗长，复杂对象的 schema 可能需要拆分多个文件管理。
- TypeScript 类型需要通过工具链生成，需要在 CI 中加入生成步骤，确保生成类型与 schema 同步（防止有人修改 schema 但忘记重新生成类型）。
- 移动端（Kotlin/Swift）需要各自配置 schema-to-type 工具链，属于一次性初始化成本。

---

## 后续行动

- [ ] 在 `packages/schemas/` 下创建所有核心对象 schema 文件（由 Codex 负责初稿）。
- [ ] 在 control-plane 项目中集成 `ajv` 并实现 middleware 层 schema validation。
- [ ] 在 CI pipeline 中加入 `json-schema-to-typescript` 生成步骤，并用 git diff 检查是否有未提交的类型变更。
- [ ] 为移动端配置 `jsonschema2pojo`（Kotlin）的工具链。

---

## 相关文档

- `docs/protocols/schema_format_and_versioning.md`：Schema 版本规则与 ADR 模板
- `docs/protocols/README.md`：协议文档索引与 Codex 必读顺序
- `docs/architecture/system-design.md`：系统设计总纲
