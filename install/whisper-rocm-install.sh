#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: <your-name>
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/openai/whisper

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

ROCM_VERSION="6.2"
HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-11.0.0}"

msg_info "Installing System Dependencies"
$STD apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  wget \
  gnupg2 \
  ffmpeg \
  python3 \
  python3-pip \
  python3-venv \
  python3-dev \
  build-essential
msg_ok "Installed System Dependencies"

msg_info "Setting up ROCm APT Repository"
wget -qO - https://repo.radeon.com/rocm/rocm.gpg.key \
  | gpg --dearmor -o /etc/apt/trusted.gpg.d/rocm.gpg

echo "deb [arch=amd64] https://repo.radeon.com/rocm/apt/${ROCM_VERSION} jammy main" \
  >/etc/apt/sources.list.d/rocm.list

$STD apt-get update
msg_ok "ROCm repository added"

msg_info "Installing ROCm Runtime (minimal)"
# On reste proche de ton Dockerfile.
# Si la version exacte de rocminfo n'est plus dispo, apt choisira la meilleure candidate.
$STD apt-get install -y --no-install-recommends \
  rocminfo \
  rocm-hip-runtime \
  rocm-device-libs
msg_ok "Installed ROCm Runtime"

msg_info "Preparing Application Directory"
mkdir -p /opt/whisper-rocm/app
msg_ok "Directory ready"

msg_info "Creating Python Virtual Environment"
python3 -m venv /opt/whisper-rocm/venv
msg_ok "Virtual environment created"

msg_info "Installing PyTorch ROCm + Whisper stack"
source /opt/whisper-rocm/venv/bin/activate

$STD pip install -U pip wheel setuptools

# PyTorch ROCm 6.2 (comme ton Dockerfile)
$STD pip install \
  torch torchvision torchaudio \
  --index-url https://download.pytorch.org/whl/rocm6.2

# Dépendances applicatives
$STD pip install \
  fastapi==0.109.2 \
  uvicorn[standard]==0.27.1 \
  python-multipart==0.0.9 \
  openai-whisper==20231117 \
  pydub==0.25.1 \
  numpy==1.26.3

deactivate
msg_ok "Installed Python packages"

msg_info "Creating Minimal Whisper API"
cat >/opt/whisper-rocm/app/main.py <<'PY'
import os
import tempfile
from fastapi import FastAPI, File, UploadFile, HTTPException
import whisper

APP_NAME = "whisper-rocm"
DEFAULT_MODEL = os.getenv("WHISPER_MODEL", "base")

app = FastAPI(title=APP_NAME)

_model = None

def get_model():
    global _model
    if _model is None:
        _model = whisper.load_model(DEFAULT_MODEL)
    return _model

@app.get("/health")
def health():
    return {"status": "ok", "model": DEFAULT_MODEL}

@app.post("/transcribe")
async def transcribe(file: UploadFile = File(...)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")

    suffix = os.path.splitext(file.filename)[1] or ".wav"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        content = await file.read()
        tmp.write(content)
        tmp_path = tmp.name

    try:
        model = get_model()
        result = model.transcribe(tmp_path)
        return {
            "text": result.get("text", "").strip(),
            "language": result.get("language"),
            "segments": result.get("segments", []),
        }
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
PY
msg_ok "API created"

msg_info "Creating Environment File"
cat >/opt/whisper-rocm/.env <<EOF
HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}
ROCM_VERSION=${ROCM_VERSION}
WHISPER_MODEL=base
PYTHONUNBUFFERED=1
PYTHONDONTWRITEBYTECODE=1
EOF
msg_ok "Environment file created"

msg_info "Creating Service"
cat >/etc/systemd/system/whisper-rocm.service <<'EOF'
[Unit]
Description=Whisper ROCm FastAPI Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/whisper-rocm/app
EnvironmentFile=/opt/whisper-rocm/.env
ExecStart=/opt/whisper-rocm/venv/bin/python -m uvicorn main:app --host 0.0.0.0 --port 8001
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now whisper-rocm
msg_ok "Service created"

motd_ssh
customize
cleanup_lxc
