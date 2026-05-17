# EasyCompute: Personal AI That Never Leaves Your Home Network

*Kaggle Writeup — Gemma 4 Good Hackathon · LiteRT Special Technology Track*

---

## Problem

Every AI assistant you use today makes the same architectural choice: your data goes to a remote server. This creates a compounding privacy tax — your files, queries, and habits become training data, logs, or both. Beyond privacy, there is a capability gap: cloud AI assistants can answer questions, but they cannot execute actions on your local machine. They cannot read your files, run shell commands, or create calendar events on your behalf — not without routing everything through infrastructure you do not own or control.

Apple Silicon has changed the hardware equation. A 2023 MacBook Pro delivers over 10 TFLOPS of GPU throughput. Google's Gemma 4 runs in under 4 GB of RAM. The missing piece was a production-quality runtime that turns local inference into real local action.

---

## Solution

EasyCompute is a cross-device task orchestration system. You describe what you want on your iPhone in natural language. Your Mac runs Google's Gemma 4 via LiteRT-LM on Apple Silicon GPU, executes multi-step tool calls — reading files, running shell commands, fetching URLs, creating calendar events — and returns the result to your phone. No API keys. No subscriptions. No outbound network traffic.

The system is built around three principles. **Task-first**: work is represented as structured Tasks with full state machines and event logs, not as ephemeral chat turns that vanish on refresh. **Local-first**: the default path is phone → desktop; cloud is an explicit opt-in, never a default. **Control-plane-first**: all state transitions flow through a single event-sourced coordinator, making every action auditable and replayable.

This is not a chatbot demo. It is a production-grade distributed system designed around the insight that privacy-preserving AI requires a different architecture — not just a different server location.

---

## How Gemma 4 Powers Every Task

Gemma 4 is the execution engine for every task that reaches the Desktop Runtime. When the Control Plane dispatches a task, the Desktop Worker constructs a structured prompt containing: (1) the user's intent extracted from the Task object, (2) a JSON schema listing all available tools, (3) conversation history restored from a SQLite checkpoint for resumable tasks, and (4) a short memory context drawn from recent completed tasks.

Gemma 4 then runs an agentic loop. It either issues a tool call or signals completion with a `task_completed` sentinel. After each tool result, the output is fed back to the model in Gemma 4's native `<|tool_response>` format, and the model decides the next action. This loop continues until the task concludes or a maximum step limit is reached.

Two model sizes are supported:

| Model | File | Size | Best For |
|---|---|---|---|
| Gemma 4 E2B | `gemma-4-E2B-it.litertlm` | ~2.6 GB | Most tasks, fast response |
| Gemma 4 E4B | `gemma-4-E4B-it.litertlm` | ~3.7 GB | Complex multi-step reasoning |

Gemma 4's output format required careful handling. The model can produce tool calls using either its native `<|tool_call>call:name{...}<tool_call|>` token format, or the JSON-based `[TOOL_CALL] {"name": ..., "arguments": ...}` format specified in the system prompt. A dual-format parser handles both: a regex path for native token calls, a JSON extractor as fallback. Gemma 4 also outputs `<|channel>thought` thinking blocks that must be stripped before returning results to users. Our token stripper handles both `<|channel>` and `<|channel|>` variants across model versions.

---

## LiteRT Implementation

The inference layer is built on Google AI Edge's `litert-lm` Python package, wrapped in a `LiteRTInferenceAdapter` that implements a clean abstract interface.

**Engine lifecycle.** A single `litert_lm.Engine` instance is loaded at startup and shared across all task Runs. On Apple M3 with the E2B model, the cold start takes approximately 28 seconds; all subsequent tasks reuse the warm engine at zero reload cost. The engine is initialized with `litert_lm.Backend.GPU`, routing matrix operations through Metal on Apple Silicon.

**Session isolation.** Every task Run creates a new `LiteRTConversationSession` via `engine.create_conversation()`. This gives each task an independent message history while sharing the loaded model weights in memory. Conversations are scoped to one Run and released on completion, preventing context contamination between tasks.

**Model format.** Models ship as `.litertlm` files from the `litert-community` organization on Hugging Face. The installation script downloads `gemma-4-E2B-it.litertlm` and validates its checksum before first use, with an optional `MODEL=e4b` flag for the larger variant.

**Measured performance** (Apple M3, E2B model):

| Scenario | Latency |
|---|---|
| Cold start (engine load) | ~28 s |
| Warm inference, single-turn task | 4–6 s |
| Warm inference, 3-step tool task | 12–18 s |

**Stderr suppression.** The LiteRT-LM engine emits verbose C++ output to stderr during initialization. We use `os.dup2` to redirect stderr to `/dev/null` during engine construction, then restore the original file descriptor immediately — a POSIX-level technique that keeps system logs clean without suppressing legitimate Python warnings.

The `InferenceAdapter` is a formal abstract interface. A `MockInferenceAdapter` exists in the test suite to enable full integration testing on CI hardware without requiring Apple Silicon.

---

## Architecture

EasyCompute has four layers communicating exclusively through typed interfaces and a shared event log.

**Mobile App** (Kotlin/Jetpack Compose): submits tasks via `POST /v1/tasks`, polls results via `GET /v1/tasks/:id/events`. Bonjour/mDNS-based discovery finds your Mac on the local network automatically — no IP address configuration needed.

**Control Plane** (Node.js/Express/TypeScript): coordinates the system without touching inference. Validates all inputs against 40 JSON Schema files (Draft 2020-12) at the HTTP boundary. Routes tasks via `RoutingEngine` based on device capability reports from periodic heartbeats. All state changes flow through `EventService.processStateTransition` — no route handler can modify Task or Run state directly.

**Desktop Runtime** (Python): receives task `HandoffPayload` objects, runs the Gemma 4 inference loop via LiteRT, dispatches tool calls to a `ToolRegistry`, and reports all state changes back as events via `POST /v1/events`. Available tools: file read/write, shell execution, HTTP fetch, AppleScript (Calendar, Mail, Finder, system automation), and desktop screenshot.

**SQLite**: stores Task state, the full event log, per-Run checkpoints, and a rolling memory summary. Checkpoints allow interrupted tasks to resume from their last successfully completed tool step rather than starting over.

The schema-first discipline — defining 40 JSON Schemas before writing any service code — eliminated an entire class of integration bugs and made the system fully auditable. Every event in the system log has a verifiable schema.

---

## Current Status

EasyCompute is a working developer preview. The backend (Control Plane + Desktop Runtime with LiteRT-LM) installs and runs via a single shell script. Mobile and desktop client apps (iOS SwiftUI, Android Kotlin/Compose, macOS menu bar) are fully implemented in the repository and build from source via Xcode and Android Studio; binary distribution (TestFlight, APK) is in progress. All results below were verified against the running backend using the included end-to-end test suite (`scripts/test_all.sh`).

## Results and Impact

EasyCompute demonstrates that Gemma 4 via LiteRT can handle real agentic workloads on consumer hardware — not just single-turn question answering. Verified task classes include:

- Document summarization combined with calendar event creation
- Shell script execution with formatted report output
- Multi-URL fetch and content extraction
- AppleScript-based macOS automation (Calendar, Mail, Finder)

Network inspection confirms zero outbound connections during task execution. For users in regulated industries — healthcare, legal, finance — this matters more than raw benchmark numbers.

---

## Challenges Overcome

**Gemma 4 thinking tokens.** The model intermittently outputs `<|channel>thought` blocks before its final answer. We built `_strip_gemma_thinking_tokens()` to correctly identify and remove thinking blocks while preserving the final response, handling both token delimiter variants across model versions.

**Function-call format instability.** Gemma 4's tool call output format varies across inference contexts. The dual-parser approach (native token regex → JSON fallback) made the system robust to format changes without requiring prompt modifications.

**LiteRT C++ noise.** The `litert_lm.Engine` constructor emits verbose C++ diagnostics to stderr that corrupt structured logs. The `os.dup2` redirection approach solves this at the POSIX level without patching the upstream library.

**Per-Run memory management.** On a long-running engine serving many tasks, conversation objects must be explicitly released to avoid memory growth. Scoping `LiteRTConversationSession` to the Run lifecycle and calling `__exit__` on completion keeps memory stable across hundreds of sequential tasks.

---

*Code: [github.com/Yanjin-ai/easycomputewithgemma](https://github.com/Yanjin-ai/easycomputewithgemma)*
*Model: [litert-community/gemma-4-E2B-it-litert-lm](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm)*
