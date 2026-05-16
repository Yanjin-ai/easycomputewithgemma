# Cross-Device Gemma Task System / 跨设备 Gemma 任务系统

一个统一账号下的多运行时任务系统，让同一个结构化任务可以在 phone、desktop、cloud、web 之间按策略路由、接续执行、观察与接管。

This repository is for a task system, not a chat product. The core unit is a structured `Task`, and all runtimes report execution through shared protocols, schemas, events, and control-plane boundaries.

## Repository Structure / 仓库结构

- `docs/architecture/`: system design and architecture entry points.
- `docs/project/`: project-level guidance and product truth sources.
- `docs/protocols/`: protocol documents for task, runtime, handoff, tools, and events.
- `docs/playbooks/`: AI collaboration and development playbooks.
- `docs/decisions/`: ADRs and architecture decisions.
- `docs/integrations/`: third-party runtime reuse and integration notes.
- `apps/mobile-host/`: mobile host, local parser, and light execution entry.
- `apps/web-console/`: control-plane and observability console.
- `services/control-plane/`: system brain for Task, Run, Event, Artifact, Approval, Routing, and Handoff.
- `services/desktop-runtime/`: desktop runtime node.
- `services/cloud-runtime/`: cloud runtime node.
- `packages/schemas/`: schema-first protocol definitions.
- `packages/runtime-adapters/`: runtime adapter interfaces and implementations.
- `packages/policy-engine/`: routing and permission policy logic.
- `packages/shared-types/`: shared project types.

## Truth Sources / 文档真相源

Current project truth sources live under:

- `docs/project/project_guidance_full_zh.md`
- `docs/architecture/system-design.md`
- `docs/protocols/`
- `packages/schemas/`
- `docs/decisions/`

All core interface changes must update schema/protocol documents first. Architecture-level changes must be recorded as ADRs before implementation.
