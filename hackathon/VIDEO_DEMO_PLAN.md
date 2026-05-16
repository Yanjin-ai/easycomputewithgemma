# Video Demo Plan — EasyCompute (Gemma 4 Good Hackathon)

> 这是录制真实视频之前的完整方案文档。  
> 视频时长目标：2分45秒–3分00秒（留15秒缓冲，不要超3分钟）  
> 语言：英语（评委为国际评审团）

---

## 跑通前的准备清单（录制前必须全部 ✅）

```
[ ] 1. Mac 上 desktop-runtime 已启动，模型已完成首次加载（热身好）
[ ] 2. Control Plane 已启动（port 3000），curl /v1/health 返回 200
[ ] 3. iPhone/Android App 已连接到 Mac（Test Connection 通过）
[ ] 4. 准备好三个演示任务的测试文件：
        ~/Documents/demo_notes.txt（内容：3条要点，100字左右）
[ ] 5. 屏幕录制软件就绪（Mac：QuickTime / OBS；iPhone：iOS内置录屏）
[ ] 6. 麦克风测试通过（录音室安静）
[ ] 7. 终端字体放大到 18pt 以上（评委在小屏上看视频）
[ ] 8. Wireshark 可选：如果要展示"零出站流量"的话准备好
```

---

## 视频结构总览

| 时间段 | 内容 | 说明 |
|---|---|---|
| 0:00–0:40 | 开场 + 问题 | 旁白+静态画面，不需要实时演示 |
| 0:40–2:10 | 核心演示 | 实时录屏，最重要的90秒 |
| 2:10–2:45 | 技术架构 + 结语 | 架构图 + 旁白 |

---

## Scene 1: Opening Hook (0:00–0:15)

**画面**：黑屏，白字逐字出现

**旁白台词（逐字）**：
> "Every AI assistant you use today sends your data to someone else's server."

**剪辑备注**：慢慢推入白字，音效用轻微的数字噪音（可选）

---

## Scene 2: Problem Statement (0:15–0:40)

**画面**：屏幕切割，左边显示 ChatGPT/Gemini 等竞品的隐私条款截图（模糊处理），右边是订阅费账单截图（模糊处理）

**旁白台词**：
> "Subscription fees. Terms of service. Your files becoming training data.  
> What if you could run capable AI entirely on your own hardware — no internet required?"

**剪辑备注**：竞品截图需要模糊，只显示概念，避免版权问题

---

## Scene 3: Solution Reveal (0:40–0:55)

**画面**：EasyCompute Logo + 架构图动画（iPhone → Mac → Tools → Result）

**旁白台词**：
> "EasyCompute. Run Gemma 4 locally on your Mac, controlled from your iPhone.  
> Powered by Google's LiteRT on Apple Silicon GPU. Your data never leaves your home network."

**剪辑备注**：配合 cover.svg 动画版本（或静态展示）

---

## Scene 4: LIVE DEMO — Part A: Simple Task (0:55–1:25)

> ⚠️ **这是视频的核心，必须流畅。先录制多次，保留最好的take。**

**演示任务**：`"What are the prime factors of 1847?"`（纯推理，无工具，延迟最低）

**录制步骤**：
1. 展示 iPhone App 界面（任务输入框）
2. 打字输入任务，点击 Submit
3. 切到 Mac 终端（分屏或剪切）——展示推理日志
4. 回到 iPhone，展示结果出现

**终端日志应该显示**：
```
INFO     Run abc123 started
INFO     Calling inference for run abc123 (step 0)
INFO     Inference returned 47 chars for run abc123
INFO     Run abc123 completed, summary length: 47 chars
```

**旁白台词**：
> "I submit a task from my phone. The Control Plane routes it to the Desktop Runtime.  
> Gemma 4 via LiteRT processes it — on the GPU, on this machine, right here."

---

## Scene 5: LIVE DEMO — Part B: Multi-Step Tool Task (1:25–2:05)

> ⚠️ **最有说服力的场景。先用 demo_notes.txt 多次测试确保稳定再录。**

**演示任务**：`"Summarize the file at ~/Documents/demo_notes.txt and create a calendar event called 'Review Session' for tomorrow at 3pm"`

**录制步骤**：
1. iPhone 输入任务，提交
2. 展示 Mac 终端（字体要大！）——清晰显示：
   - `Tool call: read_file({"path": "~/Documents/demo_notes.txt"})`
   - `Tool result: [file content]`
   - `Tool call: run_applescript(...)`
   - `Run completed`
3. 切换到 Mac 日历 App，展示事件已被创建
4. 回到 iPhone，展示最终摘要结果

**旁白台词**：
> "Now a multi-step task. Gemma 4 reads my file — that's a real file on this Mac.  
> Then it uses AppleScript to create a calendar event. No plugin. No cloud API.  
> The whole chain runs on this machine."

**备用方案（如果 AppleScript 不稳定）**：改用 `"Read ~/Documents/demo_notes.txt and give me a 3-sentence summary"` ——只用 read_file，无 AppleScript。

---

## Scene 6: Architecture Callout (2:05–2:35)

**画面**：静态架构图（cover.svg 的简化版，或者 Keynote/Figma 导出）

标注四个组件：
- `iPhone App` — Kotlin / Jetpack Compose
- `Control Plane` — Node.js / 40 JSON Schemas / Event-Sourced
- `LiteRT-LM Engine` — `litert_lm.Backend.GPU` · `.litertlm` format
- `Tool Registry` — file / shell / web / AppleScript

**旁白台词**：
> "Under the hood: a Node.js Control Plane with a strict JSON schema layer.  
> A Python inference runtime running LiteRT-LM with GPU acceleration.  
> And an event-sourced state machine so every action is auditable.  
> This is Gemma 4, running on LiteRT, doing real work."

---

## Scene 7: Closing (2:35–3:00)

**画面**：Logo + GitHub URL

**旁白台词**：
> "EasyCompute. Personal AI that stays home.  
> Open source. Zero cloud. Built on Gemma 4 via LiteRT.  
> github.com/Yanjin-ai/easycomputewithgemma"

---

## 录制技巧备注

- **字体大小**：Terminal 字体必须 ≥ 18pt，不然评委在 YouTube 上缩小屏幕看不清日志
- **录制分辨率**：1920×1080 最低，最好 1440p
- **剪辑顺序**：先录 Demo 部分（Scene 4+5）多个 take，挑最流畅的；再录旁白；最后配上 Scene 1–3 静态画面
- **模型预热**：录制之前提前跑一个任务让模型热身，避免 30s 加载时间出现在视频里
- **iPhone 录屏**：iOS 控制中心 → 屏幕录制；提前隐藏通知，开勿扰模式
- **背景音乐**：可选，YouTube 无版权音乐库（用轻度 ambient 风格，不要喧宾夺主）

---

## 上传 YouTube 时的元数据

**标题**：`EasyCompute — Run Gemma 4 Locally on Apple Silicon via LiteRT | Gemma 4 Good Hackathon`

**描述**：
```
EasyCompute lets you run Google's Gemma 4 AI model entirely on your Mac using LiteRT-LM 
with Apple Silicon GPU acceleration. Submit tasks from your iPhone — your data never 
leaves your home network.

Built for the Gemma 4 Good Hackathon (LiteRT Special Technology Track).

GitHub: https://github.com/Yanjin-ai/easycomputewithgemma
Model: https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm

Tech: Gemma 4 · LiteRT-LM · Apple Silicon Metal GPU · Node.js · Python · Kotlin
```

**Tags**：`Gemma 4, LiteRT, local AI, Apple Silicon, privacy, on-device AI, Google AI Edge`

**设为公开**：提交前必须设为 Public（不能是 Unlisted 或 Private）
