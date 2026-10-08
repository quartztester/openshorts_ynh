## First steps

1. Open OpenShorts from your SSO portal (any logged-in user of the allowed
   group).
2. **Clip Generator** tab → paste a YouTube URL or upload a video file.
3. Keep the tab open: progress streams live. On CPU, a short test video takes
   a few minutes; the Whisper model is already downloaded, so the first job
   is not slower than later ones.
4. Download clips from the results panel (also on disk under the app's data
   dir, `output/<job-id>/`).

## Changing the LLM later

```
yunohost app setting openshorts llm_base_url -v "http://your-llm-host:11434/v1"
yunohost app setting openshorts llm_model -v "qwen2.5:14b"
yunohost app setting openshorts llm_api_key -v "sk-..."
systemctl restart openshorts
```

(The env file is re-rendered on the next `yunohost app upgrade`; a quick
`sed -i` on `/var/www/openshorts/env` + service restart also works.)
