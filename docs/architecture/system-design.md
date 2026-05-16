# System Design / 系统设计

## 文档定位

本文档是跨设备 Gemma 任务系统的系统设计入口。当前版本只建立设计骨架，后续协议、schema、ADR 与实现必须以 `docs/project/project_guidance_full_zh.md` 为上位真相源。

## 产品定义

本项目不是聊天产品，也不是单端本地 AI demo，而是统一账号下的多运行时任务系统。

核心目标是：同一个结构化任务可以在手机、本地电脑、云端与 Web 控制台之间按策略路由、接续执行、统一观察、统一接管。

## 核心原则

- Task-first：信息架构围绕 `Task`，不是围绕 Chat。
- Schema-first：协议层优先于 prompt 与业务实现。
- Control-plane first：全局任务状态由 control plane 管理，runtime 不得绕过 control-plane API。
- Runtime adapter：mobile、desktop、cloud runtime 都必须通过统一 adapter 接入。
- Local-first：手机优先做本地理解与轻执行，复杂任务再升级到 desktop 或 cloud。
- Observable by default：routing、handoff、approval、run history、checkpoint、artifact 和 replay 都必须可观察、可审计。

## 系统分层

- `apps/mobile-host/`：手机端宿主容器、任务入口、本地 parser、轻执行器。
- `apps/web-console/`：control plane 与 observability 控制台。
- `services/control-plane/`：系统大脑，管理 Task、Run、Event、Artifact、Approval、Routing、Handoff。
- `services/desktop-runtime/`：桌面本地执行节点，承载文件、终端、浏览器和较重工具链。
- `services/cloud-runtime/`：重任务和长任务 fallback runtime。
- `packages/schemas/`：核心对象、事件、工具、handoff 与 adapter schema。
- `packages/runtime-adapters/`：runtime adapter interface 与具体 runtime 接入。
- `packages/policy-engine/`：路由策略、权限边界与 policy evaluation。
- `packages/shared-types/`：跨模块共享类型。

## 核心对象

以下对象属于必须冻结的核心边界，任何变更都需要 schema/protocol 更新与 ADR：

- `Device`
- `Task`
- `Run`
- `Event`
- `Artifact`
- `HandoffPayload`

## 必须冻结的协议边界

- Task state machine
- RoutingPolicy 输入字段
- Handoff payload 最小字段
- Tool schema 与 function schema
- Runtime adapter interface
- 权限边界：`local_only`、`private_lan`、`cloud_ok`

## Runtime 定位

- Mobile runtime：宿主容器、本地理解、轻执行、任务发起与用户接管入口。
- Desktop runtime：主要本地执行节点，负责文件、终端、浏览器与更重工具链。
- Cloud runtime：重任务与长任务 fallback，不作为默认执行路径。
- Web console：控制台与可观测性入口，不承担 runtime 产品形态。

## Google Runtime 复用边界

Google 官方与开源生态只复用在 runtime 层，不复用为 control plane。

- LiteRT-LM：本地推理 runtime 底座与 benchmark 参考。
- Edge Gallery：宿主容器、模型导入、benchmark、模型管理组织方式参考。
- FunctionGemma：parser/router、function call 生成、task draft 生成、本地动作识别。

所有第三方能力必须通过统一 schema 和 adapter 接入，业务层不得直接耦合底层 SDK。

## 变更规则

- 核心接口改动必须先改 schema/protocol 文档，再改代码。
- 架构级变更必须先写 ADR。
- runtime 不得直接修改全局任务状态。
- routing、handoff、approval 必须产生 event 记录。
- AI 生成代码必须通过分支与 PR 合入。

## 后续待补

- `docs/protocols/`：Task、Run、Event、Artifact、Approval、Routing、Handoff、Tool、Runtime adapter 协议。
- `packages/schemas/`：核心 JSON schema 或等价 schema 文件。
- `docs/decisions/`：ADR 模板与首批架构决策。
- runtime adapter interface 初稿。
- control-plane API skeleton 设计。
