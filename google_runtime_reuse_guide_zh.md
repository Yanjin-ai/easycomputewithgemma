# Google Runtime 轮子复用与接入说明

## 目标

本说明用于明确：哪些 Google 官方轮子需要 clone、clone 后如何研究、哪些能力可以复用、哪些不能直接照搬、以及它们如何接入本项目。

## 需要 clone 的官方资产

- `google-ai-edge/LiteRT-LM`
- `google-ai-edge/gallery`
- `google-ai-edge/litert`
- `gemma-cookbook` 中 FunctionGemma / Mobile Actions 相关内容

## clone 原则

- clone 进入 `references/`，用于研究与实验。
- 不直接把第三方仓库当成产品主仓库。
- 不直接在第三方仓库中写业务逻辑。
- 如确需长期依赖，使用 `third_party/` 或 submodule/vendor 固定版本。

## 各轮子复用定位

### LiteRT-LM

用于：
- 本地推理 runtime 底座
- 推理接口抽象参考
- benchmark 与模型能力探测

不用于：
- control plane
- task 生命周期管理
- routing policy

### Edge Gallery

用于：
- 宿主容器思路
- 模型导入流程
- 模型管理面板
- benchmark 面板
- BYOM 组织方式

不用于：
- 产品信息架构直接照搬
- task-native 页面结构
- control plane 逻辑

### FunctionGemma

用于：
- parser/router
- function call 生成
- task draft 生成
- 本地动作识别

不用于：
- 全局路由决策
- 全局任务状态管理
- 跨设备调度总控

## clone 后必须完成的工作

1. 跑通最小 demo。
2. 记录关键源码路径。
3. 编写阅读笔记。
4. 抽取 adapter 设计。
5. 明确可复用模块与不可复用模块。
6. 形成本项目的接入设计文档。

## 接入前必须先定义的接口

- `InferenceAdapter`
- `ModelManager`
- `ParserRouterService`
- `RuntimeAdapter`
- `ToolAdapter`
- `TaskDraft` schema
- `FunctionCall` schema
- `BenchmarkMetrics` schema

## 最终接入原则

- 所有第三方能力通过 adapter 接入。
- 业务层不直接调用底层 SDK。
- control plane 不依赖第三方产品结构。
- 所有复用都以本项目协议为中心。
