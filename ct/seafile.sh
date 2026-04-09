#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tiklaw (OpenClaw)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.seafile.com/ | Github: https://github.com/haiwen/seafile-docker

APP="Seafile"
var_tags="${var_tags:-cloud;files;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info "$APP"
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/seafile/docker-compose.yml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Pulling latest Seafile container images"
  cd /opt/seafile
  $STD docker compose pull
  msg_info "Recreating Seafile stack"
  $STD docker compose up -d
  msg_ok "Updated ${APP} container stack"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW} Credentials are stored in:${CL}"
echo -e "${TAB}${BGN}~/seafile.creds${CL}"
