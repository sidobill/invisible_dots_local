# invisible_dots_local

A fork of [feder-cr/invisible_dots](https://github.com/feder-cr/invisible_dots) that runs Dots on a local model
served by [Ollama](https://ollama.com) instead of OpenRouter. No API key, no per-request cost.

## Quick start (Windows)

First-time install, as in the upstream README:

```powershell
winget install -e --id OpenJS.NodeJS.LTS; winget install -e --id GoLang.Go; winget install -e --id Git.Git
git clone https://github.com/sidobill/invisible_dots_local; cd invisible_dots_local
npm ci; npm run build --workspace @invisible-dots/cli
node apps/cli/dist/invisible-dots.mjs setup --all
```

Then, every time:

```powershell
powershell -ExecutionPolicy Bypass -File .\local-model.ps1                      # qwen3:8b, 40960 tokens
powershell -ExecutionPolicy Bypass -File .\local-model.ps1 llama3.1:8b 65536    # any Ollama model with tool calling, and its window
```

The script installs Ollama if needed, starts it with the given context (flash attention, 8-bit KV cache), pulls the model, rebuilds the CLI and the
runtime image, and starts the server with local-model mode on.

In each Dot's **Settings → Advanced YAML**, set `model.id` to the Ollama model name (for example `qwen3:8b`) and
leave `provider: openrouter` as it is (the schema only accepts that value). Then stop and start the Dot's computer
so it boots the new image.

After the image has been built once, you can start just the server:

```powershell
$env:INVISIBLE_DOTS_LOCAL_MODEL = "1"; node apps/cli/dist/invisible-dots.mjs server
```

## What the fork changes

| File | Change |
|---|---|
| `guest/image-builder/units/invisible-dots-agent.service` | The engine's model endpoint is `http://10.0.2.2:11434/v1`: QEMU's user-mode gateway, which is the host's loopback, where Ollama listens. |
| `apps/scheduler/src/lifecycle.ts` | With `INVISIBLE_DOTS_LOCAL_MODEL=1`, the server no longer refuses to start a Dot without an OpenRouter key. |
| `invisible_engine_dots/nanobot/providers/openai_compat_provider.py` | For a local endpoint: the model's window is read from Ollama's `/api/ps` (loading the model first if needed) instead of OpenRouter's `/models/{id}/endpoints`, with a 4096-token answer, and a response with no reported cost counts as free instead of stopping the task. |
| `local-model.ps1` | The script above. |

Every change is marked `LOCAL MODEL (fork patch)` in the code.

## Notes

- **Every Dot uses the local model.** The endpoint is baked into the runtime image, so OpenRouter models stop
  working on this build. Use the upstream project if you want OpenRouter.
- **Context window.** The Dot's fixed prompt is about 13,500 tokens and one web page it reads can take another
  10,000 to 15,000, so browsing needs at least about 40,000. The window is the script's second argument and
  nothing else: the engine reads it from Ollama, so changing it needs no image rebuild.
- **Hardware.** `qwen3:8b` at 40960 tokens with the 8-bit KV cache takes about 8 GB of VRAM (or RAM, much slower).
- **Model quality.** Small local models handle summarising, watching pages and organising information well, but
  make more mistakes than large hosted models in long multi-step tasks with tools.
- **Spending cap.** `limits.max_cost_per_task_usd` has no effect on local models, which cost nothing; the step
  limit `max_steps_per_task` still applies.
