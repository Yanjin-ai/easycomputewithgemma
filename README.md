# EasyCompute — Run AI on Your Mac, Control from iPhone

Run Gemma 4 AI locally on your Mac. Submit tasks from your iPhone. Your data never leaves your home network.

**🔒 100% Local** — No cloud, no subscriptions, no data collection  
**📱 iPhone → Mac** — Submit natural language tasks from anywhere  
**🧠 Gemma 4** — Google's open model, running on your own hardware  

---

## What It Does

You type a task on your iPhone. Your Mac runs Google's Gemma 4 model locally and sends the result back. No API keys, no monthly fees, no data uploaded anywhere.

Examples of what you can ask:
- *"Summarize the file at ~/Documents/notes.txt"*
- *"Create a calendar event: Team meeting tomorrow at 2pm"*
- *"What's the current memory usage on my Mac?"*
- *"Translate this to Japanese: Hello, nice to meet you"*
- *"Fetch example.com and tell me what it's about"*

---

## Requirements

- **Mac**: Apple Silicon (M1/M2/M3/M4), macOS 13+, 5 GB free storage
- **iPhone**: iOS 16+
- **Network**: Both devices on the same WiFi (or [Tailscale](docs/setup/tailscale.md) for remote access)

---

## Quick Install (Mac)

```bash
curl -fsSL https://raw.githubusercontent.com/Yanjin-ai/easycompute/main/scripts/install.sh | bash
```

Installation takes 10–30 minutes (mostly model download). Installs everything and starts automatically on login.

**Options:**
```bash
# Use the larger, more capable E4B model (3.7 GB)
MODEL=e4b curl -fsSL https://raw.githubusercontent.com/Yanjin-ai/easycompute/main/scripts/install.sh | bash

# Skip model download (install dependencies only)
SKIP_MODEL=true bash scripts/install.sh
```

**Verify installation:**
```bash
bash scripts/validate_install.sh
```

---

## iOS App

*TestFlight link coming soon — currently in beta testing.*

After installing:
1. Open the app → follow the 3-screen setup guide
2. Enter your Mac's IP address when prompted  
   *(Find it: System Settings → Wi-Fi → Details → IP Address)*
3. Tap **Test Connection** → **Get Started**

The app will automatically scan for your Mac on the local network (Bonjour discovery).

---

## Cross-Network Access (not on same WiFi)

Install [Tailscale](https://tailscale.com) on both devices, then use your Mac's Tailscale IP in the app settings. Full guide: [docs/setup/tailscale.md](docs/setup/tailscale.md)

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "Cannot connect to Mac" | Check: `launchctl list \| grep gemma4all` and `tail -f /tmp/gemma4all.stderr.log` |
| Task stuck in "running" | First task loads the model (~30s). Wait and retry. |
| No Macs found in app | Open the Gemma4all menu bar app on your Mac first |
| Model download fails | Run manually: `bash scripts/check_models.sh` |
| Wrong answer / poor quality | Switch to E4B: `MODEL=e4b bash scripts/install_autostart.sh` |

---

## Architecture

```
iPhone App  →  Control Plane (Node.js, port 3000)  →  Desktop Runtime (Python)
                    ↓ routing / events                      ↓ Gemma 4 inference
                  SQLite                               LiteRT-LM (Apple Silicon)
```

- **Control Plane**: coordinates tasks, routing, events — never touches inference
- **Desktop Runtime**: runs Gemma 4 locally, calls tools, reports results
- **iOS App**: submits tasks, polls for results, shows history
- **Tools available**: file read/write, shell commands, web fetch, AppleScript (Calendar, Mail, Finder)

Protocol docs: [docs/protocols/](docs/protocols/)  
Schema definitions: [packages/schemas/](packages/schemas/)

---

## Development

```bash
# Start all services locally
bash scripts/start_all.sh

# Quick sanity check (arithmetic task)
bash scripts/e2e_test.sh --quick

# Full 5-scenario evaluation
bash scripts/eval_e2e.sh

# Build standalone control-plane binary
bash scripts/build_binary.sh
```

See [CLAUDE.md](CLAUDE.md) for architecture rules and contribution guidelines.

---

## License

MIT
