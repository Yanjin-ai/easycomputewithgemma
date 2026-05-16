# EasyCompute — Run Gemma 4 on Your Mac, Control from Your Phone

> **Gemma 4 Good Hackathon submission · LiteRT Special Technology Track**  
> Built with [Google AI Edge LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) · Gemma 4 E2B / E4B · Apple Silicon GPU

**🔒 100% Local** — No cloud, no API keys, no data leaves your home network  
**📱 Phone → Mac** — Submit natural language tasks from iPhone or Android  
**🧠 Gemma 4 via LiteRT** — Running on Metal GPU, accelerated by Apple Silicon  
**⚙️ Real Agentic Tasks** — File I/O, shell commands, web fetch, AppleScript automation  

---

## What It Does

You type a task on your phone. Your Mac runs Google's **Gemma 4** model locally using **LiteRT-LM** with GPU acceleration, executes multi-step tool calls, and sends the result back — entirely on your local network.

```
"Summarize ~/Documents/notes.txt and create a calendar event for next Friday"
```

Gemma 4 reads the file, reasons about the content, calls AppleScript to create the calendar event, and returns a summary. **Zero internet traffic. Zero API calls. Zero subscriptions.**

---

## How Gemma 4 + LiteRT Powers This

The inference layer wraps Google AI Edge's `litert-lm` Python package:

```python
import litert_lm

# GPU-accelerated Gemma 4 on Apple Silicon
engine = litert_lm.Engine(
    model_path="gemma-4-E2B-it.litertlm",
    backend=litert_lm.Backend.GPU,
).__enter__()

# New conversation per task — clean history, shared weights
conversation = engine.create_conversation()
response = conversation.send_message({"role": "user", "content": task_prompt})
```

**Key design decisions:**
- One `Engine` loaded at startup, reused across all tasks (no 28-second reload per task)
- One `Conversation` per task Run, giving each task isolated history
- `.litertlm` model format from [`litert-community`](https://huggingface.co/litert-community) on Hugging Face
- `Backend.GPU` routes all matrix ops through Metal on Apple Silicon M1–M4

Gemma 4's native `<|tool_call>` token format is parsed directly, with a JSON `[TOOL_CALL]` fallback for compatibility. Thinking tokens (`<|channel>thought`) are stripped before returning results.

---

## Architecture

```
Phone App  ──POST /v1/tasks──►  Control Plane  ──HandoffPayload──►  Desktop Runtime
(Kotlin)                        (Node.js)                           (Python)
                                    │                                    │
                               40 JSON Schemas                    litert_lm.Engine
                               Event-Sourced                      Backend.GPU
                               RoutingEngine                      ToolRegistry
                               SQLite                                   │
                                    ◄──POST /v1/events──────────────────┘
```

| Component | Tech | Role |
|---|---|---|
| Mobile App | Kotlin · Jetpack Compose · Retrofit | Task submission, result polling, Bonjour discovery |
| Control Plane | Node.js · Express · TypeScript | Task routing, state machine, event log, schema validation |
| Desktop Runtime | Python · litert-lm · httpx | Gemma 4 inference, tool execution, checkpoint/resume |
| Schemas | 40 × JSON Schema Draft 2020-12 | Protocol contract across all components |

**Event-sourced state machine**: all Task and Run state changes flow through `EventService.processStateTransition`. No component can mutate state directly — every transition is logged, auditable, and replayable.

---

## Supported Tasks

| Category | Examples |
|---|---|
| File operations | Summarize, search, read, write local files |
| Shell execution | Run commands, get system info, parse output |
| Web content | Fetch URLs, extract structured information |
| macOS automation | Create calendar events, draft emails, control Finder |
| Pure reasoning | Math, translation, Q&A, code explanation |

---

## Models

| Model | File | Size | Recommended For |
|---|---|---|---|
| Gemma 4 E2B | `gemma-4-E2B-it.litertlm` | ~2.6 GB | Most tasks, default |
| Gemma 4 E4B | `gemma-4-E4B-it.litertlm` | ~3.7 GB | Complex multi-step tasks |

Both available from [`litert-community`](https://huggingface.co/litert-community) on Hugging Face.

**Performance** (Apple M3, E2B model):
- Cold start: ~28s (engine load, once per session)
- Warm, single-turn task: 4–6s
- Warm, 3-step tool task: 12–18s

---

## Requirements

- **Mac**: Apple Silicon (M1–M4), macOS 13+, 5 GB free storage
- **Phone**: Android (Kotlin app) · iOS support planned
- **Network**: Same WiFi, or [Tailscale](docs/setup/tailscale.md) for remote access
- **Python**: 3.11+ with `litert-lm-api-nightly`

---

## Quick Start

```bash
# Install everything + download Gemma 4 E2B
curl -fsSL https://raw.githubusercontent.com/Yanjin-ai/easycomputewithgemma/main/scripts/install.sh | bash

# Or use the larger E4B model
MODEL=e4b curl -fsSL https://raw.githubusercontent.com/Yanjin-ai/easycomputewithgemma/main/scripts/install.sh | bash

# Verify
bash scripts/validate_install.sh
```

---

## Development

```bash
# Start all services
bash scripts/start_all.sh

# Quick sanity check
bash scripts/e2e_test.sh --quick

# Full 5-scenario eval
bash scripts/eval_e2e.sh
```

Protocol documentation: [`docs/protocols/`](docs/protocols/)  
JSON Schema definitions: [`packages/schemas/`](packages/schemas/)  
Architecture rules: [`CLAUDE.md`](CLAUDE.md)

---

## Project Structure

```
services/
  control-plane/      Node.js · Event-sourced task coordinator
  desktop-runtime/    Python · LiteRT-LM inference + tool execution
apps/
  mobile-host/        Android · Kotlin · Jetpack Compose
  macos-menubar/      macOS · Swift · menu bar client
packages/
  schemas/            40 × JSON Schema — protocol source of truth
docs/
  protocols/          7 protocol documents (state machine, events, handoff…)
```

---

## Why LiteRT

LiteRT-LM is not just a convenient wrapper here — it is the **only inference path** in the system. Every task, every tool call, every agentic step flows through `litert_lm.Engine`. This choice is what makes the privacy guarantee concrete: there is no fallback cloud API, no optional remote call. If LiteRT runs, the task runs locally. If it doesn't, the task waits.

The `.litertlm` format with GPU dispatch on Metal is what makes Gemma 4 fast enough for interactive use on consumer hardware. Without LiteRT, this project would require either a cloud backend or hardware most people don't own.

---

## License

MIT

---

*Submitted to the [Gemma 4 Good Hackathon](https://www.kaggle.com/competitions/gemma-4-good-hackathon) · LiteRT Special Technology Track*
