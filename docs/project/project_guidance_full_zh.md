# 跨设备 Gemma 任务系统：完整项目指导文档

## 文档定位

本文档用于把跨设备 Gemma 任务系统从“想法和原则”收束成可执行、可协作、可审计的开发指导体系。目标不是写一个抽象愿景，而是明确：产品到底要实现什么、哪些轮子必须复用、哪些能力必须自研、开发过程如何管理、不同模型与开发工具如何分工、哪些部分必须严格冻结、哪些部分允许灵活迭代。[cite:91][cite:144][cite:106][cite:53]

这份文档可以作为后续专业开发软件中的“项目总纲”，并作为架构、schema、任务拆解、AI 协作开发和第三方轮子接入的统一上位文档。[cite:53][cite:60]

## 一、项目完整清单

## 1. 产品需要实现什么

这个产品不是聊天产品，也不是单端本地 AI demo，而是一个统一账号下的多运行时任务系统。它要实现的不是“不同端都能跑模型”，而是“同一个任务可以在手机、本地电脑、云端之间按策略路由、接续执行、统一观察、统一接管”。[cite:33][cite:53][cite:60]

### 产品必须实现的核心能力

- 统一身份：同一用户下管理 phone / desktop / cloud / web 等设备节点。[cite:33]
- 统一任务对象：任务是结构化对象，不是聊天消息。[cite:60]
- 统一路由决策：任务能按隐私、复杂度、工具需求、设备状态在不同 runtime 间调度。[cite:33]
- 统一执行状态：任何 runtime 的执行都必须回写为统一事件流。[cite:91]
- 统一接管机制：用户可在任一端审批、暂停、继续、终止、重试。[cite:66]
- 统一可观测性：用户和开发者都能看到 route reason、run history、checkpoint、artifact 和 replay。[cite:33]
- 本地优先：手机先做本地理解和轻执行，复杂任务再升级到桌面或云端。[cite:91][cite:106]

### 产品不应该被定义成什么

- 不是单纯的 AI chat app。
- 不是单纯的“本地大模型 App”。
- 不是 Edge Gallery 的二次改皮。
- 不是把三个客户端简单拼在一起。

## 2. 产品设计与实现需求

### 产品设计需求

- 信息架构必须围绕 Task，而不是 Chat。[cite:60]
- 手机端必须是宿主容器 + 任务入口 + 本地 parser + 轻执行器，而不是纯消息入口。[cite:33][cite:111]
- 桌面端必须是主要本地执行节点，承载文件、终端、浏览器和更重工具链。[cite:33]
- 云端必须是重任务与长任务 fallback，而不是默认所有任务都上云。[cite:33]
- Web 端必须优先承担 control plane 和 observability 控制台职责。[cite:53]

### 实现需求

- 建立 control plane 作为系统大脑，集中管理 Task、Run、Event、Artifact、Approval、Routing 和 Handoff。[cite:91]
- 建立 mobile / desktop / cloud 三类 runtime adapter。[cite:60]
- 建立 schema-first 的协议层，而不是 prompt-first 的散装系统。[cite:60]
- 建立 AI 协作开发规则，确保 Codex、Claude Code、Kimi 的输出始终对齐系统文档与协议。[cite:53]

## 3. 项目约束规范

### 必须卡死的部分

这些部分必须严格冻结，任何变更都要走 ADR 与版本更新流程：

- 产品定义。
- 系统分层边界。
- 核心对象：Device / Task / Run / Event / Artifact / HandoffPayload。[cite:60]
- Task state machine。
- RoutingPolicy 输入字段。
- Handoff payload 最小字段。
- Tool schema 与 function schema。
- Runtime adapter interface。
- 权限边界：`local_only / private_lan / cloud_ok`。[cite:33]

### 允许灵活迭代的部分

这些部分可以在 v1 之后逐步优化，但仍应在上位协议约束之内：

- UI 样式与页面细节。
- 本地模型 profile 的具体调参。
- Mobile Actions 是否做微调以及何时做微调。[cite:112][cite:150]
- Desktop / cloud 的具体工具接法。
- observability 的展示深度。
- memory 的增强策略。

## 4. 复用接口准则

Google 当前官方与开源生态最值得复用的轮子有：LiteRT-LM、Gemma 官方移动部署路径、AI Edge Gallery 源码与组织方式、FunctionGemma 与 Mobile Actions guide。[cite:91][cite:38][cite:144][cite:106]

### 复用准则

- Google 的轮子只复用在 runtime 层，不复用在 control plane 层。[cite:91]
- Edge Gallery 复用的是宿主容器、模型导入、benchmark、模型管理思路，不复用其产品形态。[cite:144][cite:111]
- FunctionGemma 复用为 parser/router，不复用为全局系统大脑。[cite:106]
- 所有外部轮子必须通过统一 schema 和 adapter 接入，业务层不得直接耦合底层 SDK。[cite:60]
- clone 下来的第三方仓库原则上只用于参考、实验和提炼模式，不作为主产品仓库直接开发。[cite:144][cite:96]

## 5. 开发规范准则

### 工程结构规范

项目主仓库建议采用 monorepo，并强制分层：

- `docs/`：系统设计、协议、ADR、开发 playbook。
- `apps/`：mobile host、web console。
- `services/`：control plane、desktop runtime、cloud runtime。
- `packages/`：schemas、adapters、policy engine、shared types。
- `references/`：第三方仓库阅读笔记与参考摘录。
- `third_party/`：真实被依赖的固定版本第三方资产。

### 变更规范

- 所有核心接口改动都必须先改 schema / protocol 文档，再改代码。
- 所有架构级变更必须先写 ADR。
- 所有模型生成代码只能通过分支和 PR 合入，不允许直改主干。
- 所有 runtime 都不得直接绕过 control-plane API 去修改全局任务状态。
- 所有路由决策、handoff 和 approval 都必须有 event 记录。[cite:91]

### AI 协作规范

- Codex 负责施工：schema 文件、service skeleton、adapter、测试初稿。
- Claude Code 负责审查：架构边界、协议一致性、PR review、风险识别。
- Kimi 负责中文沉淀：会议纪要、需求整理、文档改写、issue 草稿。
- 任何模型开始工作前，都必须读取：产品定义、系统分层、schema 文档、ADR、当前 issue 与允许修改范围。[cite:53]

## 6. 利用已有东西为未来不同工具开发做准备

你现在不是只在做一个功能集合，而是在搭一个长期可扩展的 task system。为未来不同工具开发做准备，关键不是“预先把所有工具都接完”，而是建立：

- 统一 tool schema。
- 统一 function call schema。
- Runtime adapter interface。
- Tool permission gating。
- Tool audit log。
- Tool capability registry。

这样未来新增 mobile-only tools、desktop-only tools、cloud-only tools 时，都不需要改系统骨架，只需要挂新的 tool adapter 即可。[cite:60]

## 二、完整准备清单的实现 prompt，以及分别让谁来做

下面给出可以直接投喂给不同工具的 prompt 模板。原则是：每个 prompt 都必须引用上位文档，限定输入、输出和边界，避免模型自由发挥。

## 1. 给 Codex 的 prompt 模板

适用任务：代码施工、schema 文件、接口骨架、服务实现、测试初稿。

```text
你现在在一个跨设备 Gemma 任务系统项目中工作。
请先阅读以下文件，并严格以它们为唯一真相源：
1. docs/architecture/system-design.md
2. docs/protocols/*.md
3. packages/schemas/*.json
4. docs/decisions/*.md
5. 当前 issue 说明

你的任务：
- 只实现 issue 中要求的模块
- 不允许修改未授权模块
- 不允许发明 schema 字段
- 不允许绕过 control-plane API
- 所有新增接口必须与现有 schema 对齐
- 所有代码必须附带最小测试
- 输出修改文件清单、关键实现点、未解决风险

当前任务：
<在这里替换成具体模块任务>

验收标准：
<在这里替换成具体验收条件>
```

建议让 Codex 来做：

- Schema 初稿落地。
- Control plane 的 API skeleton。
- Runtime adapter 骨架。
- Mobile host 的非复杂 UI 页面骨架。
- Desktop / cloud worker 初始实现。
- 测试与 lint 修复。

## 2. 给 Claude Code 的 prompt 模板

适用任务：架构审查、PR 审查、协议边界检查、风险审查。

```text
请作为架构审查者审查以下改动。
先阅读：
1. docs/architecture/system-design.md
2. docs/protocols/*.md
3. docs/decisions/*.md
4. 当前 PR / diff

请重点检查：
- 是否违反系统分层边界
- 是否违反 schema 或协议
- 是否把 runtime 逻辑错误耦合进 control plane
- 是否引入不可审计的模型决策
- 是否破坏手动审批、handoff、observability 机制
- 是否缺少测试或迁移说明

输出格式：
1. 阻断问题
2. 高风险问题
3. 可改进问题
4. 是否建议合并
```

建议让 Claude Code 来做：

- PR review。
- 架构一致性审查。
- 状态机和 handoff 设计审查。
- 路由策略风险审查。
- 第三方轮子接入方案评审。

## 3. 给 Kimi 的 prompt 模板

适用任务：中文文档整理、会议纪要、需求归纳、issue 拆分草稿。

```text
请根据以下材料，整理成清晰、结构化、专业的中文文档。
必须以项目现有文档为准，不得自行改动架构定义。
输入材料：
1. docs/architecture/system-design.md
2. docs/protocols/*.md
3. 会议纪要 / 对话摘录
4. 指定目标文档类型

输出要求：
- 中文表达清晰
- 不改变已有系统边界
- 保持术语统一
- 输出适合进入 docs/ 或项目管理系统

当前任务：
<在这里替换>
```

建议让 Kimi 来做：

- 中文系统设计整理。
- issue 描述改写。
- ADR 中文摘要。
- backlog 文本整理。
- 会议纪要转可执行条目。

## 三、Google 轮子复用说明、衔接说明与 clone 实施说明

## 1. 需要 clone 的对象

建议 clone 下来的官方资产：

- `google-ai-edge/LiteRT-LM`：用于研究 runtime API、模型加载、跨平台组织方式。[cite:96]
- `google-ai-edge/gallery`：用于研究宿主容器、模型导入、benchmark、BYOM 组织方式。[cite:144]
- `google-ai-edge/litert`：用于理解更底层 LiteRT 方向。[cite:109]
- `gemma-cookbook` 中的 FunctionGemma / Mobile Actions notebook：用于 parser/router 微调与数据格式参考。[cite:112][cite:152]

## 2. clone 的实施原则

- 这些仓库应被 clone 到 `references/` 或独立研究区，不进入主产品代码树。
- clone 的目的首先是阅读、跑通、摘取模式，而不是直接二次开发。
- 只有当某一部分确实要长期依赖第三方源代码时，才放入 `third_party/` 或以 submodule/vendor 方式引入。
- 不建议直接 fork AI Edge Gallery 当产品主仓库，因为它的定位是 showcase app，不是跨设备任务 control plane。[cite:144][cite:91]

## 3. clone 以后要做什么

### 对 LiteRT-LM

- 跑通官方最小 demo。
- 识别其跨平台 API 结构。
- 提炼出你自己的 `InferenceAdapter` 接口。
- 识别 model manager、session manager、benchmark provider 应该怎样包起来。[cite:91][cite:96]

### 对 Edge Gallery

- 阅读 app 结构与页面组织。
- 记录 model import、benchmark、runtime host、developer resource 入口如何组织。[cite:144]
- 提炼出哪些是“宿主容器思路”，哪些是“产品 demo 页面”。
- 设计你的 Model Catalog 和 Benchmark Panel，明确哪些页面保留思路，哪些全部重写为 task-native 页面。[cite:111]

### 对 FunctionGemma / Mobile Actions

- 研究 function schema。
- 研究 action 数据格式与训练方式。[cite:112][cite:150]
- 提炼出你自己的 `ParserRouterService` 输入/输出。
- 决定第一阶段用基础版 + 规则兜底，还是进入定向微调。

## 4. 复用前必须先产出的内容

在真正复用前，你必须先写出以下内容，否则 clone 下来的轮子无法稳定接入：

- `InferenceAdapter` 设计文档。
- `ModelManager` 设计文档。
- `ParserRouterService` 设计文档。
- `RuntimeAdapter` 接口文档。
- `TaskDraft` 数据结构。
- `Tool schema` 与 `FunctionCall schema`。
- `Benchmark metrics` 字段定义。
- `Model profile` 规范。

没有这些，你只会停留在“看懂了别人的 repo”，而不会变成自己的系统资产。[cite:60]

## 5. 复用时的衔接原则

- Google 的轮子只进入 runtime 层，不进入 control plane。[cite:91]
- Edge Gallery 的设计只借宿主和模型管理，不借产品信息架构。[cite:144][cite:111]
- FunctionGemma 只做 parser/router，不做全局路由决策。[cite:106]
- 所有第三方能力必须通过 adapter 接入，不允许上层业务代码直接调用第三方 SDK。[cite:60]

## 四、全景图和实施计划应该放在哪些文档里

你问 A 到 K 的这些内容更适合放在哪。答案是：它们不应该只是一张零散 checklist，而应该被放进一个专业的文档体系里。

## 推荐文档体系

### 1. `docs/architecture/system-design.md`

这是项目总纲，放：

- 产品定义。
- 分层架构。
- 模块分工。
- 动态时序。
- 为什么这样设计。

### 2. `docs/protocols/`

放：

- task protocol
- handoff protocol
- routing policy
- approval protocol
- event protocol
- observability field dictionary

### 3. `packages/schemas/`

放所有正式 schema 文件：

- `device.schema.json`
- `task.schema.json`
- `run.schema.json`
- `event.schema.json`
- `artifact.schema.json`
- `handoff-payload.schema.json`

### 4. `docs/decisions/`

放 ADR：

- 为什么选 LiteRT-LM
- 为什么不直接 fork Edge Gallery
- 为什么 FunctionGemma 只做 parser/router
- 为什么 routing 不能纯模型化

### 5. `docs/project/implementation-master-checklist.md`

这份文档最适合承载你 A 到 K 的完整实施条目。它是“实施总清单”，作用是把系统设计转成工程待办。

### 6. `docs/playbooks/ai-collaboration-rules.md`

放：

- Codex/Claude/Kimi 分工
- AI 协作开发规范
- 输入输出模板
- PR / issue / ADR 规范

所以，你问的一、二确实可以视为对项目的“完整需求整理和归纳”，但建议拆成：

- **项目总纲文档**：讲全景图和边界。
- **实施总清单文档**：讲 A 到 K 的落地任务。
- **AI 协作规范文档**：讲怎么让不同模型对齐。
- **第三方轮子接入文档**：讲 clone、研究、适配、接入。[cite:53][cite:60]

## 五、A 到 K 的实施落地：应该如何组织成专业开发指导

下面把你列的 A 到 K，整理成更适合项目管理和开发指导的结构。

## A. 系统定义层 TODO

建议放入：`docs/project/implementation-master-checklist.md` 的 `System Definition` 章节。

必须完成：

- 明确一句话产品定义：任务系统，不是聊天系统。
- 冻结系统分层：mobile host / local runtime / control plane / desktop runtime / cloud runtime。
- 冻结核心对象：Device / Task / Run / Event / Artifact / HandoffPayload。
- 冻结 task state machine。
- 冻结 routing policy v1 输入维度。
- 冻结 handoff payload 最小字段。
- 冻结 approval 机制边界。
- 冻结 observability 的最小可见字段。

建议工具分工：

- Kimi 先整理中文定义稿。
- Claude Code 做边界审查。
- 人最终拍板。

## B. Schema 层 TODO

建议放入：`packages/schemas/` + `docs/protocols/schema-governance.md`

必须完成：

- 编写 `device.schema.json`
- 编写 `task.schema.json`
- 编写 `run.schema.json`
- 编写 `event.schema.json`
- 编写 `artifact.schema.json`
- 编写 `handoff-payload.schema.json`
- 编写 schema versioning 规则
- 编写 prompt contract / tool contract versioning 规则

建议工具分工：

- Codex 负责 schema 文件初稿。
- Claude Code 做 schema consistency review。
- Kimi 负责中文版 schema 说明文档。

## C. Google 轮子接入设计 TODO

建议放入：`docs/integrations/google-runtime-reuse.md`

### LiteRT-LM / Gemma

- 设计 `InferenceAdapter`
- 设计 `ModelManager`
- 设计本地模型 profile
- 确定移动端模型文件组织方式
- 确定 benchmark 指标字段
- 把本地推理封装为独立服务，不散落在 UI 中

### Edge Gallery 借鉴

- 阅读 Gallery 源码结构
- 抽取其 model import / benchmark / runtime host 设计
- 定义保留宿主思路的页面
- 定义替换成 task-native 的页面
- 设计自己的 Model Catalog 和 Benchmark Panel

### FunctionGemma

- 设计 `ParserRouterService`
- 定义 function schema 格式
- 定义 task draft 输出格式
- 定义 parser 失败时的规则兜底
- 评估基础版 vs fine-tune
- 预留 Mobile Actions fine-tuning 数据接口

建议工具分工：

- Codex 负责接入 adapter 雏形。
- Claude Code 负责接口边界和架构评审。
- Kimi 负责阅读笔记整理和中文接入说明。

## D. Control Plane TODO

建议放入：`services/control-plane/README.md` + `docs/project/implementation-master-checklist.md`

- 实现用户与设备注册
- 实现 Task API
- 实现 Run API
- 实现 Event API
- 实现 Artifact API
- 实现 RoutingEngine
- 实现 ApprovalService
- 实现 HandoffService
- 实现 SummaryMemoryService
- 实现 ObservabilityService
- 实现 route history 持久化
- 实现 task replay 所需事件存储
- 实现权限边界：`local_only / private_lan / cloud_ok`

建议工具分工：

- Codex 主施工。
- Claude Code 做 PR 与分层审查。

## E. Mobile Host TODO

建议放入：`apps/mobile-host/README.md`

- 建立宿主 App 外壳
- 做输入入口：文本、语音、分享
- 接入本地 FunctionGemma parser
- 接入本地 Gemma 轻执行器
- 做任务列表页
- 做任务详情页
- 做审批页
- 做设备状态页
- 做模型管理页
- 做 benchmark 页
- 做与 control plane 的同步客户端
- 做断网/弱网本地缓存策略
- 做“禁止上云”本地策略 UI

建议工具分工：

- Codex 做页面和接线。
- Claude Code 审查宿主结构是否被 demo 思维带偏。

## F. Desktop Runtime TODO

建议放入：`services/desktop-runtime/README.md`

- 实现 DesktopWorker
- 实现 runtime heartbeat
- 实现 handoff payload 接收
- 实现本地工具调用适配
- 实现 artifact 上传
- 实现 checkpoint 回写
- 实现 run metrics 回写
- 实现失败重试与错误分类

## G. Cloud Runtime TODO

建议放入：`services/cloud-runtime/README.md`

- 实现 CloudWorker
- 实现重模型适配层
- 实现任务队列消费
- 实现 artifact 存储
- 实现长任务 checkpoint
- 实现回写 event / metrics
- 实现 fallback 到等待用户或桌面重新接手

## H. Web Console TODO

建议放入：`apps/web-console/README.md`

- 做设备列表
- 做任务列表
- 做任务详情
- 做 route timeline
- 做 run history
- 做 checkpoint 列表
- 做 artifact 视图
- 做 approval 视图
- 做 route override
- 做 replay

## I. Tooling TODO

建议放入：`docs/protocols/tooling-and-function-schema.md`

- 统一 tool schema
- 统一 function call schema
- 定义 mobile-only tools
- 定义 desktop-only tools
- 定义 cloud-only tools
- 实现 tool permission gating
- 实现 tool audit log

## J. 可靠性 TODO

建议放入：`docs/project/reliability-checklist.md`

- 每次 route 决策都写 event
- 每次 handoff 都幂等
- 每次 long run 都产 checkpoint
- 每个 artifact 都可版本化
- 每个 approval 都可回放
- runtime crash 后可恢复
- schema 变更可兼容
- 本地模型装载失败有 fallback
- parser 输出不合法时有规则兜底
- cloud 禁止时不能误上传敏感数据

## K. 文档与开发规范 TODO

建议放入：`docs/playbooks/development-governance.md`

- 写系统设计主文档
- 写 schema 文档
- 写 runtime adapter 文档
- 写 routing policy 文档
- 写 handoff 协议文档
- 写 observability 字段字典
- 写开发环境搭建文档
- 写测试策略文档
- 写 release / migration 文档

## 六、最关键的整合原则

这些原则必须直接写入系统设计主文档和 AI 协作开发规范中：

- Google 的轮子复用在 runtime 层，不复用在 control plane 层。[cite:91]
- Edge Gallery 复用的是宿主容器和模型管理思路，不是产品形态。[cite:144][cite:111]
- FunctionGemma 复用为 parser/router，不复用为全局大脑。[cite:106]
- 所有轮子通过统一 schema 和 adapter 接进来，不允许业务层直接耦合底层 SDK。[cite:60]
- 先把任务系统串起来，再扩场景；先把协议写清，再接更多模型。[cite:53][cite:33]

## 七、建议最终产出的项目指导文档清单

为了真正服务于后续开发，建议最终形成以下文档集：

1. `docs/architecture/system-design.md`：项目总纲。
2. `docs/project/product-requirements.md`：产品需求与范围。
3. `docs/project/implementation-master-checklist.md`：A-K 完整实施总清单。
4. `docs/integrations/google-runtime-reuse.md`：Google 轮子复用与 clone 接入说明。
5. `docs/playbooks/ai-collaboration-rules.md`：Codex / Claude / Kimi 协作规则。
6. `docs/playbooks/development-governance.md`：开发规范、PR/issue/ADR 规则。
7. `docs/protocols/`：task / run / event / handoff / routing / tool 等协议文档。
8. `packages/schemas/`：全部正式 schema 文件。
9. `docs/project/reliability-checklist.md`：可靠性与上线前检查。

## 最终结论

你现在真正要做的，不是继续扩想法，而是把项目“制度化”。制度化的核心就是：产品边界明确、系统协议冻结、第三方轮子复用规则明确、AI 协作规则明确、实施清单明确、文档归档位置明确。[cite:53][cite:60]

这样之后无论是 Codex、Claude Code、Kimi，还是未来引入新的工具和 runtime，都会围绕同一套项目真相源工作，而不是每次从对话里重新发明项目。[cite:53]
