# AI 协作开发规则模板

## 目标

确保 Codex、Claude Code、Kimi 在同一项目中协作时，始终围绕同一套产品定义、协议和工程约束工作，避免输出漂移、重复造轮子、越层实现和 schema 失控。

## 单一真相源

任何 AI 开发工具开始工作前，必须读取并遵循：

1. `docs/architecture/system-design.md`
2. `docs/project/product-requirements.md`
3. `docs/protocols/*.md`
4. `packages/schemas/*.json`
5. `docs/decisions/*.md`
6. 当前 issue / PR / task 描述

## 工具分工

### Codex

负责：
- 代码施工
- schema 文件落地
- service skeleton
- adapter 实现
- 测试初稿

禁止：
- 自行更改产品边界
- 自行发明 schema 字段
- 绕过 control-plane API

### Claude Code

负责：
- 架构审查
- PR review
- 分层边界检查
- 风险评估
- 协议一致性审查

禁止：
- 未经约束大规模重写模块

### Kimi

负责：
- 中文文档整理
- 会议纪要
- issue 草稿
- ADR 中文摘要
- 中文规范文档改写

禁止：
- 直接定义核心架构
- 直接改动系统协议

## 所有 AI 输出的基本规则

- 必须说明修改了哪些文件。
- 必须说明是否影响 schema / protocol。
- 必须说明是否影响 control plane、runtime adapter 或 tool schema。
- 必须列出未解决风险。
- 必须与现有文档版本对齐。

## PR 规则

- 所有 AI 生成代码必须走分支和 PR。
- 所有核心模块 PR 必须经过 Claude Code 审查。
- 所有 schema / protocol 变更必须同步更新 docs。
- 所有影响架构边界的改动必须先补 ADR。
