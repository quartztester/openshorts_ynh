## Before installing

- **CPU budget:** every job runs ffmpeg + Whisper + face tracking on CPU.
  Roughly 5–8 minutes of work per 8 minutes of source video, and one job at a
  time. This is not a busy-service app.
- **RAM:** the `small` Whisper model at int8 needs ~1 GB free while a job
  runs; `medium` needs ~3 GB. Close other heavy workloads or trim their
  limits if the box is tight.
- **An LLM for moment picking:** either a Google Gemini API key, or the base
  URL of any OpenAI-compatible chat server reachable *from this server*.
  Without either, jobs fail at the clip-selection step.
- **Disk:** ~4 GB for the install, plus the Whisper model you choose and all
  generated clips live in the app's data dir (backed up with the app).
