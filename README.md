# OpenShorts for YunoHost

![Version](https://img.shields.io/badge/helper-v2.1-green)

Turn long-form videos (podcasts, webinars, interviews) into vertical 9:16
shorts with captions — the AI moment picker runs on any OpenAI-compatible LLM
(Ollama, vLLM, OpenRouter, a hosted endpoint...) or Google Gemini.

- 📦 **App:** [OpenShorts](https://github.com/mutonby/openshorts) — MIT, self-hosted mode has no limits or watermarks
- 🗃️ **Category:** Multimedia

## Description

OpenShorts ingests a video file or YouTube URL and produces viral-ready
vertical clips: transcript (faster-whisper, fully local), viral-moment
detection (your LLM), smart 9:16 reframe with face tracking, styled burned-in
subtitles, and a Remotion render pass. The dashboard is gated by YunoHost SSO;
the backend has no accounts of its own.

## Install-time questions

| Question | Notes |
|---|---|
| LLM base URL | OpenAI-compatible endpoint, e.g. `http://ollama:11434/v1`. Leave empty to use Gemini only. |
| LLM model | Model name on that server (e.g. `qwen2.5:14b`). |
| LLM API key | Only if the server checks one. |
| Gemini API key | Optional; needed for layout picking / silent videos. |
| Whisper model | `small` default (~1 GB RAM at int8); `medium`/`large-v3` need more. |

## Prerequisites & hardware reality

- **amd64 only** (mediapipe has no aarch64 wheel at the pinned version).
- **~4 GB free disk** for the venv + node builds, plus the Whisper model
  (~0.5–3 GB by size). `ram.build` peaks around 3 GB during install.
- CPU-only: expect **5–8 minutes of processing per 8 minutes of source
  video** (upstream's own estimate).
- The LLM endpoint must be reachable **from the server**, not from your
  browser. A local Ollama on another box works; a laptop-only Ollama does not.

## Install

```
yunohost app install https://github.com/quartztester/openshorts_ynh
```

or in the webadmin: **Applications → Install a custom app**.

Must be installed at the **root of a domain** (path `/`). Uploads go through
YunoHost SSO, so install with a permission group you belong to.

## After install

1. Open the app tile and paste a YouTube URL or upload a file in
   **Clip Generator**.
2. Watch progress in the job panel; clips land in the results tab.
3. Jobs are processed one at a time on CPU — don't queue a marathon.

Troubleshooting, ports table, and update/backup behavior: shown in the
YunoHost admin under the app's **Documentation** tab.
