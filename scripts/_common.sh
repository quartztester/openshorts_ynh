#!/bin/bash

# Shared deployment steps for install/upgrade. Functions read the usual
# YunoHost globals (app, install_dir, data_dir) plus whisper_model.

# LLM/ASR options are plain settings so the config panel and upgrades can
# change them without touching the rendered env file.
openshorts_store_llm_settings() {
	ynh_app_setting_set --key=llm_base_url --value="${llm_base_url:-}"
	ynh_app_setting_set --key=llm_model --value="${llm_model:-}"
	ynh_app_setting_set --key=llm_api_key --value="${llm_api_key:-}"
	ynh_app_setting_set --key=gemini_api_key --value="${gemini_api_key:-}"
	ynh_app_setting_set --key=whisper_model --value="${whisper_model:-small}"
}

# The app writes uploads/ and output/ relative to its cwd (= install_dir,
# where uvicorn's main.py lives). Symlink them into the backed-up data_dir.
openshorts_link_data() {
	mkdir -p "$data_dir/output" "$data_dir/uploads" "$data_dir/.cache"
	chmod 750 "$data_dir"
	ln -sfn "$data_dir/output" "$install_dir/output"
	ln -sfn "$data_dir/uploads" "$install_dir/uploads"
	chown -h "$app:$app" "$install_dir/output" "$install_dir/uploads"
	chown -R "$app:$app" "$install_dir" "$data_dir"
}

# CPU-only torch from PyTorch's own index first: the default PyPI wheel drags
# ~2 GB of CUDA libraries this box will never use. Venv is kept across
# upgrades (rebuildable, but slow); recreated only when missing.
openshorts_ensure_venv() {
	[ -x "$install_dir/venv/bin/uvicorn" ] && return 0
	ynh_script_progression "Creating the Python virtualenv (this takes a few minutes)..."
	python3 -m venv "$install_dir/venv"
	"$install_dir/venv/bin/pip" install --no-cache-dir --upgrade pip
	"$install_dir/venv/bin/pip" install --no-cache-dir \
		--index-url https://download.pytorch.org/whl/cpu \
		"torch==$(grep -oP '^torch==\K.*' "$install_dir/requirements.txt")" \
		"torchvision==$(grep -oP '^torchvision==\K.*' "$install_dir/requirements.txt")"
}

# Rest of the pins from regular PyPI; reinstalled unconditionally because
# requirements.txt may have moved between upstream versions.
openshorts_pip_install_deps() {
	grep -vE '^torch(vision)?==' "$install_dir/requirements.txt" > "$install_dir/requirements-cpu.txt"
	"$install_dir/venv/bin/pip" install --no-cache-dir -r "$install_dir/requirements-cpu.txt"
	rm -f "$install_dir/requirements-cpu.txt"
	chown -R "$app:$app" "$install_dir/venv"
}

# Local patches applied to the unpacked source before building:
# - [local box patch] with a local OpenAI-compatible LLM configured, clipping
#   needs no Gemini/Upload-Post key: only block processing when no LLM AND no
#   gemini key. (Upload-Post remains available in Settings for auto-posting.)
# - Upload limit: upstream hardcodes MAX_FILE_SIZE_MB=2048 and a stale "500MB"
#   UI label. Raise the cap to 4 GB and fix the label (conf/nginx.conf's
#   client_max_body_size matches). NB: behind Cloudflare's proxy, their
#   plan-level body cap applies first (Free: 100MB) — grey-cloud the DNS
#   record for big uploads.
openshorts_apply_patches() {
	sed -i "s/const keysMissing = !billingEnabled \&\& (!geminiOk || !uploadPostKey);/const keysMissing = !billingEnabled \&\& !geminiOk;/" "$install_dir/dashboard/src/App.jsx"
	sed -i "s/^MAX_FILE_SIZE_MB = 2048.*/MAX_FILE_SIZE_MB = 4096  # 4GB limit (package patch)/" "$install_dir/app.py"
	sed -i "s/MP4, MOV up to 500MB/MP4, MOV up to 4GB/" "$install_dir/dashboard/src/components/MediaInput.jsx"
	sed -i "s/Keep files under 500\./Keep files under 4GB./" "$install_dir/dashboard/src/components/ClipTutorial.jsx"
}

# dashboard = vite SPA: npm ci as app user with HOME in data_dir (npm cache
# must be writable); --ignore-scripts skips postinstall downloads the static
# build doesn't need; VITE_API_URL='' bakes same-origin relative API calls.
# Upstream's render-service lockfile pins an older Remotion than the un-locked
# remotion/ project resolves to; the skew breaks the startup bundle on new
# exports (Error: export 'Interactive' ... was not found in 'remotion').
# Install remotion/ FIRST, then pin render-service to the exact version it got.
openshorts_build_frontends() {
	ynh_script_progression "Building the dashboard (npm ci + vite build)..."
	ynh_exec_as_app env HOME="$data_dir" VITE_API_URL="" \
		npm --prefix "$install_dir/dashboard" ci --ignore-scripts --no-audit --no-fund
	ynh_exec_as_app env HOME="$data_dir" \
		npm --prefix "$install_dir/dashboard" run build

	ynh_script_progression "Building the Remotion render service..."
	ynh_exec_as_app env HOME="$data_dir" \
		npm --prefix "$install_dir/remotion" install --no-audit --no-fund
	local remotion_version
	remotion_version=$(node -p "require('$install_dir/remotion/node_modules/remotion/package.json').version")
	ynh_exec_as_app env HOME="$data_dir" \
		npm --prefix "$install_dir/render-service" install --no-audit --no-fund \
		"remotion@$remotion_version" "@remotion/bundler@$remotion_version" "@remotion/renderer@$remotion_version"
	ynh_exec_as_app env HOME="$data_dir" \
		npm --prefix "$install_dir/render-service" run build

	chown -R "$app:$app" "$install_dir"
}

# Model weights are fetched at job time otherwise, where a slow mirror looks
# like a hung job. HF_HOME keeps them in data_dir so upgrades and restores
# don't refetch. Skips when the chosen model is already cached (a changed
# whisper_model setting re-triggers the download). YOLO weights only matter
# on fresh installs.
openshorts_preload_models() {
	local preload_yolo="${1:-yes}"
	if ls "$data_dir"/.cache/huggingface/hub/models--Systran--faster-whisper-"$whisper_model"* > /dev/null 2>&1; then
		return 0
	fi
	ynh_script_progression "Pre-downloading the $whisper_model Whisper model..."
	cd "$install_dir"
	ynh_exec_as_app env HF_HOME="$data_dir/.cache/huggingface" \
		"$install_dir/venv/bin/python" -c "from faster_whisper import WhisperModel; WhisperModel('$whisper_model', device='cpu', compute_type='int8')"
	if [ "$preload_yolo" = yes ]; then
		ynh_exec_as_app env HF_HOME="$data_dir/.cache/huggingface" \
			"$install_dir/venv/bin/python" -c "from ultralytics import YOLO; YOLO('yolov8n.pt')"
	fi
	cd /
}

openshorts_add_config() {
	ynh_config_add --template=env --destination="$install_dir/env"
	chmod 600 "$install_dir/env"
	chown "$app:$app" "$install_dir/env"

	ynh_config_add_systemd
	ynh_config_add_systemd --service="$app-render" --template=systemd-render.service

	# nginx (www-data) serves dashboard/dist directly: install_dir is 0750
	# (app-only) by YunoHost convention, so grant *traverse* (o+x, not o+r) on
	# the path to dist and make dist world-readable. Without this, try_files
	# silently falls through to the backend and the portal tile shows
	# {"detail":"Not Found"}.
	chmod o+x "$install_dir" "$install_dir/dashboard" 2>/dev/null || true
	chmod -R a+rX "$install_dir/dashboard/dist" 2>/dev/null || true

	ynh_config_add_nginx
}

openshorts_start_services() {
	ynh_systemctl --service="$app-render" --action=start --log_path=systemd --wait_until="Listening on port"
	ynh_systemctl --service="$app" --action=start --log_path=systemd --wait_until="Uvicorn running"
}

# Tile logo for the SSO portal + admin UI (supported override for
# non-catalog apps: <app>.png in the applogos dir).
openshorts_set_logo() {
	if [ -f "$YNH_APP_BASEDIR/doc/logo.png" ]; then
		cp "$YNH_APP_BASEDIR/doc/logo.png" "/usr/share/yunohost/applogos/$app.png"
		yunohost user permission update "$app.main" --logo "/usr/share/yunohost/applogos/$app.png" || true
	fi
}
