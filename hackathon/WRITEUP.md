# EasyCompute: Personal AI Infrastructure Powered by Gemma 4 via LiteRT

*Kaggle Writeup — Gemma 4 Good Hackathon · LiteRT Special Technology Track*

---

## Problem

Every AI assistant you use today makes the same architectural choice: your data goes to a remote server. This creates a compounding privacy tax — your files, queries, and habits become training data, logs, or both. Cloud AI can answer questions, but it cannot act on your local machine. It cannot read your private files, run shell commands, or create calendar events without routing everything through infrastructure you do not own or control.

Apple Silicon has changed the hardware equation. A 2024 MacBook Pro delivers over 10 TFLOPS of GPU throughput. Google's Gemma 4 runs in under 4 GB of RAM. The missing piece was a production-quality system that turns local inference into real local action — across all your devices, on your own network.

---

## Solution

EasyCompute is a cross-device task orchestration system. You describe what you want in natural language on your phone. Your Mac runs Gemma 4 via LiteRT-LM on Apple Silicon GPU, executes multi-step tool calls — reading files, running shell commands, fetching URLs, creating calendar events — and returns the result. No API keys. No subscriptions. No outbound traffic.

Three architectural principles are non-negotiable. **Task-first**: work is represented as structured Tasks with full state machines and an immutable event log, not ephemeral chat turns. **Local-first**: phone → desktop is the default path; cloud is an explicit, user-authorized opt-in. **Event-sourced**: all state changes flow through an append-only event stream, making the entire system auditable and replayable from first principles.

---

## How Gemma 4 Powers Every Task

Gemma 4 is the sole execution engine for every task that reaches the Desktop Runtime. When the Control Plane dispatches a task, the Desktop Worker constructs a structured prompt containing: (1) the user's intent, (2) a JSON schema of all available tools, (3) conversation history restored from a SQLite checkpoint for resumable tasks, and (4) a rolling memory context from recent completed tasks.

Gemma 4 runs an agentic loop. It either issues a tool call or signals completion with a `task_completed` sentinel. After each tool result, output is fed back in Gemma 4's native `<|tool_response>` format and the model decides the next action.

| Model | File | Size | Best for |
|---|---|---|---|
| Gemma 4 E2B | `gemma-4-E2B-it.litertlm` | ~2.6 GB | Most tasks, fast response |
| Gemma 4 E4B | `gemma-4-E4B-it.litertlm` | ~3.7 GB | Complex multi-step reasoning |

A dual-format parser handles both Gemma 4's native `<|tool_call>call:name{...}<tool_call|>` token format and the JSON `[TOOL_CALL]` fallback, making the system robust across model updates. A purpose-built `_strip_gemma_thinking_tokens()` function cleanly removes `<|channel>thought` blocks before returning results to users.

---

## LiteRT Implementation

The inference layer wraps Google AI Edge's `litert-lm` Python package in a formal `LiteRTInferenceAdapter` abstraction with a `MockInferenceAdapter` for CI testing.

**Engine lifecycle.** A single `litert_lm.Engine` loads at startup and is reused across all task Runs. Cold start takes approximately 28 seconds on Apple M3 (E2B model); all subsequent tasks share the warm engine at zero reload cost. The engine initializes with `litert_lm.Backend.GPU`, routing matrix operations through Metal on Apple Silicon M1–M4.

**Session isolation.** Every Run creates a new `LiteRTConversationSession` via `engine.create_conversation()`, giving each task a clean message history while sharing model weights in memory. Sessions are explicitly released on Run completion, keeping memory stable across hundreds of sequential tasks on a long-running engine.

**Model format.** Models ship as `.litertlm` files from the `litert-community` organization on Hugging Face. The macOS menu bar app ships a download manager with per-file progress tracking; users can switch between E2B and E4B without touching the terminal.

**Measured performance** (Apple M3, E2B):

| Scenario | Latency |
|---|---|
| Cold start (engine load) | ~28 s |
| Warm, single-turn task | 4–6 s |
| Warm, 3-step tool task | 12–18 s |

**Stderr suppression.** The LiteRT-LM engine emits C++ diagnostics to stderr during initialization. A POSIX `os.dup2` redirect to `/dev/null` during engine construction suppresses this without patching the upstream library, preserving clean structured Python logs.

---

## Architecture

**42 JSON Schemas** (Draft 2020-12) define the protocol contract across all layers before any code is written. Every HTTP request body is validated against these schemas at the boundary. No type definitions are hand-written in any language — schemas are the single source of truth.

**Control Plane** (Node.js/TypeScript) — ten HTTP endpoints covering task lifecycle, device registration, heartbeat management, handoff dispatch, and an approval workflow. All Task and Run state mutations are gated through `EventService.processStateTransition`; no route handler can mutate state directly. An SSE broadcaster enables real-time updates to connected clients.

**Desktop Runtime** (Python) — receives `HandoffPayload` objects, runs the Gemma 4 inference loop via LiteRT, and dispatches tool calls to a `ToolRegistry` with six tool categories: file read/write, shell execution, HTTP fetch with HTML extraction, AppleScript automation (Calendar, Mail, Finder), desktop screenshot, and directory listing. SQLite checkpoints allow interrupted tasks to resume from their last successfully completed step.

**iOS App** (SwiftUI) — three-screen onboarding with Bonjour/mDNS auto-discovery, task submission with voice input, task list grouped by state, full event timeline view, and App Intents integration for Siri Shortcuts.

**macOS Menu Bar App** (Swift) — real-time service health monitoring, model download manager with E2B/E4B progress tracking, recent task list with detail popovers, and Bonjour advertisement for mobile discovery.

**Android App** (Kotlin/Jetpack Compose) — task submission, task list with state chips, an approval screen for user-gated tasks, and Hilt dependency injection.

---

## Approval Workflow

A feature uncommon in local AI systems: an `ApprovalService` backed by SQLite gates sensitive tasks behind explicit user consent. When a task requires an action above its permission threshold, an approval request is created with an expiry timer. The user grants or rejects it from their phone (iOS or Android approval screen). Only then does the Desktop Runtime proceed. Every approval decision is recorded in the immutable event log — making consent auditable, not just assumed.

---

## Results and Impact

All 13 end-to-end test scenarios in `scripts/test_all.sh` pass on Apple Silicon, covering: pure inference, shell execution, file read/write, translation, web fetch, DuckDuckGo search, AppleScript calendar automation, desktop screenshot, multi-step tool chaining, and sequential memory. Network inspection confirms zero outbound connections during any task execution.

For users in regulated industries — healthcare, legal, finance — the absence of any cloud dependency is a meaningful compliance property, not just a preference.

---

## Current Status and Challenges

**Status.** The backend installs via a single shell script. Client apps (iOS, Android, macOS menu bar) build from source; release automation scripts for DMG packaging, iOS archiving, and notarization are complete.

**Gemma 4 thinking tokens.** The model intermittently outputs `<|channel>thought` blocks. Our stripper handles both `<|channel>` and `<|channel|>` delimiter variants across model versions.

**Dual tool-call format.** Gemma 4's function-calling output format varies across inference contexts. The native token regex → JSON fallback chain handles this without prompt changes.

**iOS on-device inference.** The `ParserRouterService` for running FunctionGemma on-device is awaiting resolution of a known LiteRT-LM Metal GPU issue (upstream). The iOS app currently submits tasks to the Mac runtime; on-device processing is the next milestone.

---

*Code: [github.com/Yanjin-ai/easycomputewithgemma](https://github.com/Yanjin-ai/easycomputewithgemma)*
*Model: [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)*
