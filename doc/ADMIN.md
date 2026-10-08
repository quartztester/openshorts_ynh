# Administering OpenShorts

## First steps after install

1. Log in through SSO and open **Clip Generator**.
2. Submit a short (1–2 min) test video first — it exercises the whole chain
   (download → transcript → LLM moment pick → reframe → captions) for a few
   CPU-minutes.
3. Confirm the job log shows the transcript step passing; that proves the
   Whisper model and the LLM endpoint are both healthy.

## Ports

| Purpose | Variable | Default | Exposed publicly? |
|---|---|---|---|
| FastAPI backend (uvicorn) | `__port_main__` | 24682 | No — loopback only, reached via nginx |
| Remotion render service | `__port_render__` | 3101 | No — loopback only; nginx proxies `/render/` and `/output/` to it |

Neither port is published in the firewall. Both listen on 127.0.0.1.

## Routine settings

Keys and models live in app settings; the env file
(`/var/www/__APP__/env`, mode 600) is rendered from them:

```
yunohost app setting __APP__ gemini_api_key -v "AIza..."
yunohost app setting __APP__ whisper_model  -v "medium"
```

Re-render env + restart after changing them:

```
yunohost app upgrade __APP__ -u /var/www/__APP__ --no-safety-backup   # or:
sed -i 's/^WHISPER_MODEL=.*/WHISPER_MODEL=medium/' /var/www/__APP__/env && systemctl restart __APP__
```

CPU knobs in the same file: `WHISPER_DEVICE`, `WHISPER_COMPUTE` (`int8`
default), `FFMPEG_ENCODER` (`x264`; set `auto` if you add a GPU).

## Updates

`yunohost app upgrade __APP__` re-downloads the pinned upstream tarball only
if you upgrade from a **custom app URL** pointing at a newer package commit.
The venv and node builds are rebuilt in place (pip/npm network needed);
jobs, uploads, and model caches survive — they live in the data dir.

## Data & identity

- `__DATA_DIR__` holds `output/` (all jobs and clips), `uploads/`, and
  `.cache/huggingface` (Whisper weights). Backed up with the app.
- `install_dir/env` (keys) and the two systemd units are also backed up.
- The venv and node_modules are **not** backed up — restore rebuilds them.
- `output/` and `uploads/` are symlinks from the install dir into the data
  dir; the app writes through them.

## Troubleshooting

| Symptom | Cause & fix |
|---|---|
| Job fails at "moment detection" with a connection error | The LLM endpoint isn't reachable **from the server** (browser access is irrelevant). `curl -s $LLM_BASE_URL/models` as root; fix firewall/DNS or set `llm_base_url` to an address the box can route to. |
| Job fails instantly, log mentions `response_format`/JSON | Older OpenAI-compatible servers reject strict JSON schema mode; the app retries with `json_object` automatically. If it still fails, pick a model that follows JSON instructions (e.g. a Qwen/Llama instruct model ≥ 8B). |
| `/videos/...` clips 404 after a restore | The job dirs were archived but the restore predates this package's symlink fix — check `ls -l /var/www/__APP__/output` points at `__DATA_DIR__/output`, then `systemctl restart __APP__ __APP__-render`. |
| Dashboard loads, API calls 502 | `systemctl status __APP__` — usually the venv was interrupted mid-install. Re-run `yunohost app upgrade __APP__` to finish the pip install. |
| Render (Remotion) fails with browser download error | The renderer downloads a headless Chromium under `HOME=__DATA_DIR__` on first render. Offline box: pre-seed `__DATA_DIR__/.remotion/`, or allow egress once. |
| Whisper OOM (job killed, dmesg shows oom-kill) | Drop `WHISPER_MODEL` to `small`/`base` or keep `WHISPER_COMPUTE=int8`. |
| 413 on upload | nginx `client_max_body_size` is 2048M; larger files → upload via scp into `__DATA_DIR__/uploads/` and pick "local file" — or raise the cap in `/etc/nginx/conf.d/<domain>.d/__APP__.conf`. |
| Memory pressure while a job runs | Torch + Whisper + YOLO overlap for the first ~60 s of a job. Trim the biggest RSS holder (`ps aux --sort=-rss`) rather than killing the job mid-render. |
