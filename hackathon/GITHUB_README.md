# EasyCompute — Gemma 4 on Your Mac, Controlled from Your Phone

> **Gemma 4 Good Hackathon · LiteRT Special Technology Track**

**🔒 100% Local** · No cloud · No API keys · No data leaves your network  
**📱 Any Device** · iOS · Android · macOS menu bar · All connected  
**🧠 Gemma 4 via LiteRT** · Metal GPU · Apple Silicon M1–M4  
**⚙️ Real Agentic Tasks** · Files · Shell · Web · AppleScript · Calendar  

---

## What It Does

You describe a task in natural language on your phone. Your Mac runs **Gemma 4** locally using **LiteRT-LM with Metal GPU acceleration**, executes multi-step tool calls, and returns the result — entirely on your local network.

```
"Read my notes file, summarise it, and create a calendar event for next Friday"
```

Gemma 4 reads the file, reasons about the content, calls AppleScript to create the calendar event, and returns a summary. Zero internet traffic. Zero API calls. Zero subscriptions.

---

## LiteRT at the Core

Every task execution flows through `litert_lm.Engine`. LiteRT is not a wrapper — it is the **only inference path** in the system.

```python
import litert_lm

# One engine, loaded once, shared across all tasks
engine = litert_lm.Engine(
    model_path="gemma-4-E2B-it.litertlm",
    backend=litert_lm.Backend.GPU,   # Metal on Apple Silicon
).__enter__()

# Fresh conversation per task — isolated history, shared weights
conv = engine.create_conversation()
response = conv.send_message({"role": "user", "content": prompt})
```

| Design choice | Why |
|---|---|
| Single engine, reused across Runs | 28s cold start paid once; subsequent tasks 4–6s |
| New `Conversation` per Run | Clean history per task, no cross-task contamination |
| `Backend.GPU` | Metal dispatch on Apple Silicon M1–M4 |
| `.litertlm` format | LiteRT-native quantized format from `litert-community` on HuggingFace |

---

## Architecture

```
Phone (iOS/Android)
    │  POST /v1/tasks
    ▼
Control Plane (Node.js)          ← 42 JSON Schemas · Event-Sourced State Machine
    │  HandoffPayload             ← Routing · Approval · Heartbeat
    ▼
Desktop Runtime (Python)
    │  litert_lm.Engine
    │  Backend.GPU
    ▼
Tool Registry                    ← file · shell · web · AppleScript · screenshot
    │
    └─ Events → POST /v1/events → Control Plane → Phone (polled)
```

**Event sourcing**: every state change is an immutable event. Task history is always fully reconstructible from the event log. No direct state mutations anywhere in the system.

**42 JSON Schemas**: all inter-component contracts are defined in `packages/schemas/` before code is written. Zero hand-written type definitions across four languages.

---

## Clients

| Client | Tech | Key features |
|---|---|---|
| **iOS App** | SwiftUI | Bonjour discovery · Voice input · Event timeline · Siri Shortcuts |
| **Android App** | Kotlin · Jetpack Compose | Task submission · Approval screen · State chips |
| **macOS Menu Bar** | Swift | Model download UI · Service health · Task history |
| **Terminal** | bash | `test_all.sh` · `eval_e2e.sh` · `install.sh` |

---

## Tools Available to Gemma 4

| Tool | What it does |
|---|---|
| `read_file` / `write_file` | Read and write local files (home directory) |
| `list_directory` | Browse directory contents |
| `run_shell_command` | Execute any shell command (60s timeout) |
| `web_fetch` | Fetch a URL, strip HTML, return clean text |
| `web_search` | DuckDuckGo search, return top results |
| `run_applescript` | Control macOS apps (Calendar, Mail, Finder, Music…) |
| `take_screenshot` | Capture desktop, describe what's visible |

---

## Performance

Measured on Apple M3, Gemma 4 E2B model:

| Scenario | Time |
|---|---|
| Cold start (engine load) | ~28 s |
| Warm inference, no tools | 4–6 s |
| Warm, 3-step tool task | 12–18 s |

---

## Quick Start

```bash
# Install backend + download Gemma 4 E2B (~2.6 GB)
curl -fsSL https://raw.githubusercontent.com/Yanjin-ai/easycomputewithgemma/main/scripts/install.sh | bash

# Start services
bash scripts/start_all.sh

# Verify everything works (13 scenarios)
bash scripts/test_all.sh
```

For the larger E4B model (~3.7 GB, better reasoning):
```bash
MODEL=e4b bash scripts/install.sh
```

---

## Requirements

- **Mac**: Apple Silicon (M1–M4), macOS 13+, ~5 GB storage
- **Phone**: iOS 16+ or Android — or submit tasks via curl
- **Network**: Same WiFi, or [Tailscale](docs/setup/tailscale.md) for remote access

---

## Repository Structure

```
services/
  control-plane/      Node.js · TypeScript · 10 HTTP endpoints
  desktop-runtime/    Python · LiteRT-LM · Tool execution
apps/
  ios-host/           SwiftUI · Bonjour · Voice · App Intents
  mobile-host/        Kotlin · Jetpack Compose · Hilt
  macos-menubar/      Swift · Model download · Health monitor
packages/
  schemas/            42 × JSON Schema Draft 2020-12
docs/
  protocols/          7 architecture protocol documents
scripts/              19 scripts · install · test · release · DMG
```

---

## Why LiteRT Matters Here

LiteRT-LM is not an optional acceleration layer — it is what makes the privacy guarantee concrete. There is no fallback cloud API. If LiteRT runs, the task runs locally. The `.litertlm` format with Metal GPU dispatch is what makes Gemma 4 fast enough on consumer hardware for interactive, multi-step agentic use.

---

## License

MIT · *Submitted to the [Gemma 4 Good Hackathon](https://www.kaggle.com/competitions/gemma-4-good-hackathon) · LiteRT Special Technology Track*
