#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 community-scripts ORG
# Author: <your-name>
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/openai/whisper

APP="Whisper-ROCm"

# Tags & resources (ajuste si besoin)
var_tags="${var_tags:-ai;stt}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"

# Aligné sur ton Dockerfile
var_os="${var_os:-ubuntu}"
var_version="${var_version:-22.04}"

# GPU passthrough via le flag communautaire
# Le mécanisme récent de la repo active le passthrough quand var_gpu="yes"
# et autodétecte Intel/AMD/NVIDIA. :contentReference[oaicite:2]{index=2}
var_gpu="${var_gpu:-yes}"

# En général on reste en unprivileged par défaut dans la repo.
# Si ton host/driver ROCm est capricieux, tu peux tester un conteneur privilégié.
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/whisper-rocm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP} LXC"
  $STD apt-get update
  $STD apt-get -y upgrade

  if [[ -x /opt/whisper-rocm/venv/bin/pip ]]; then
    msg_info "Updating Python packages"
    $STD /opt/whisper-rocm/venv/bin/pip install -U pip
    $STD /opt/whisper-rocm/venv/bin/pip install -U \
      fastapi uvicorn python-multipart openai-whisper pydub numpy
    msg_ok "Updated Python packages"
  fi

  systemctl restart whisper-rocm 2>/dev/null || true
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8001${CL}"

# Petit check indicatif côté host
# (ne fait pas échouer le script si absent)
pct exec "$CTID" -- bash -c "command -v rocminfo >/dev/null && rocminfo | head -n 5" || true
