#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tiklaw (OpenClaw)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://manual.seafile.com/latest/setup_binary/installation/
#
# Usage for testing on a fork:
#   SEAFILE_TARBALL_URL='https://example.invalid/seafile-pro-server_x86-64.tar.gz' \
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/yann-soliman/ProxmoxVE/feat/seafile-script/ct/seafile.sh)"
#
# The installer requires SEAFILE_TARBALL_URL to be set to a direct archive download URL.

CUSTOM_REPO_OWNER="yann-soliman"
CUSTOM_REPO_NAME="ProxmoxVE"
CUSTOM_REPO_BRANCH="feat/seafile-script"
CUSTOM_REPO="https://raw.githubusercontent.com/${CUSTOM_REPO_OWNER}/${CUSTOM_REPO_NAME}/${CUSTOM_REPO_BRANCH}"

export REPO_SOURCE="external"
source <(curl -fsSL "${CUSTOM_REPO}/misc/build.func")

APP="Seafile"
var_tags="${var_tags:-cloud;files}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_install="seafile-install"

header_info "$APP"
variables
color
catch_errors

if [[ -z "${SEAFILE_TARBALL_URL:-}" ]]; then
  msg_error "SEAFILE_TARBALL_URL is required before launching this script"
  echo "Example:" >/dev/tty
  echo "  SEAFILE_TARBALL_URL='https://example.invalid/seafile-pro-server_x86-64.tar.gz' bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/${CUSTOM_REPO_OWNER}/${CUSTOM_REPO_NAME}/${CUSTOM_REPO_BRANCH}/ct/seafile.sh)\"" >/dev/tty
  exit 1
fi

function update_script() {
  header_info "$APP"
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/seafile-installer/seafile-installer.conf ]]; then
    msg_error "No ${APP} installer state found!"
    exit
  fi

  source /etc/seafile-installer/seafile-installer.conf
  if [[ -z "${SEAFILE_TARBALL_URL}" ]]; then
    msg_error "No Seafile tarball URL configured!"
    exit
  fi

  SEAFILE_ROOT=/opt/seafile
  TARBALL_NAME=$(basename "${SEAFILE_TARBALL_URL%%\?*}")
  TARBALL_PATH=${SEAFILE_ROOT}/${TARBALL_NAME}

  msg_info "Stopping Seafile services"
  systemctl stop seahub.service || true
  systemctl stop seafile.service || true
  msg_ok "Stopped Seafile services"

  msg_info "Refreshing Python dependencies for Seafile 13"
  sudo -u seafile bash -lc "source ${SEAFILE_ROOT}/python-venv/bin/activate && pip3 install --timeout=3600 boto3 oss2 twilio configparser pytz sqlalchemy==2.0.* pymysql==1.1.* jinja2 django-pylibmc pylibmc redis django-redis psd-tools lxml django==5.2.* cffi==1.17.1 future==1.0.* mysqlclient==2.2.* captcha==0.7.* django_simple_captcha==0.6.* pyjwt==2.10.* djangosaml2==1.11.* pysaml2==7.5.* pycryptodome==3.23.* python-ldap==3.4.* pillow==11.3.* pillow-heif==1.0.* cairosvg==2.8.* scikit-learn==1.7.*"
  msg_ok "Refreshed Python dependencies"

  msg_info "Downloading updated Seafile Pro tarball"
  sudo -u seafile wget -O "${TARBALL_PATH}" "${SEAFILE_TARBALL_URL}"
  msg_ok "Downloaded updated tarball"

  msg_info "Extracting updated Seafile Pro tarball"
  sudo -u seafile tar -C ${SEAFILE_ROOT} -xf "${TARBALL_PATH}"
  SEAFILE_EXTRACTED_DIR=$(tar -tf "${TARBALL_PATH}" | head -n1 | cut -d/ -f1)
  if [[ -z "${SEAFILE_EXTRACTED_DIR}" ]]; then
    msg_error "Unable to determine extracted Seafile directory"
    exit
  fi
  ln -sfn ${SEAFILE_ROOT}/${SEAFILE_EXTRACTED_DIR} ${SEAFILE_ROOT}/seafile-server-latest
  msg_ok "Extracted updated tarball"

  if [[ -x ${SEAFILE_ROOT}/seafile-server-latest/upgrade/upgrade_12.0_13.0.sh ]]; then
    msg_info "Running Seafile major upgrade script"
    sudo -u seafile bash -lc "source ${SEAFILE_ROOT}/python-venv/bin/activate && cd ${SEAFILE_ROOT}/seafile-server-latest && yes | bash upgrade/upgrade_12.0_13.0.sh"
    msg_ok "Ran major upgrade script"
  fi

  msg_info "Starting Seafile services"
  systemctl start seafile.service
  systemctl start seahub.service || sudo -u seafile bash -lc "cd ${SEAFILE_ROOT}/seafile-server-latest && yes | bash ./seahub.sh start"
  msg_ok "Started Seafile services"

  msg_ok "Updated successfully!"
  exit
}

function build_container() {
  local custom_install_func_url
  local custom_build_func_url
  local custom_script_path
  local temp_build

  custom_install_func_url="${CUSTOM_REPO}/misc/install.func"
  custom_build_func_url="${CUSTOM_REPO}/misc/build.func"
  custom_script_path="${CUSTOM_REPO}/install/${var_install}.sh"

  msg_info "Seafile debug: wrapping build_container for fork testing"
  log_msg "Seafile debug: custom_build_func_url=${custom_build_func_url}"
  log_msg "Seafile debug: custom_install_func_url=${custom_install_func_url}"
  log_msg "Seafile debug: custom_script_path=${custom_script_path}"

  temp_build=$(mktemp)
  curl -fsSL "${custom_build_func_url}" >"${temp_build}"

  python3 - <<'PY' "${temp_build}" "${custom_install_func_url}" "${custom_script_path}"
from pathlib import Path
import sys
p = Path(sys.argv[1])
install_url = sys.argv[2]
script_url = sys.argv[3]
text = p.read_text()
text = text.replace(
    'export FUNCTIONS_FILE_PATH="$(curl -fsSL "$\\_func_url")"',
    'export FUNCTIONS_FILE_PATH="$(curl -fsSL \"' + install_url + '\")"\n  log_msg "Seafile debug: FUNCTIONS_FILE_PATH loaded from fork: ' + install_url + '"'
)
text = text.replace(
    'lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh)"',
    'log_msg "Seafile debug: running install script from fork: ' + script_url + '"\n    lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL ' + script_url + ')"'
)
p.write_text(text)
PY

  if [[ ! -s "${temp_build}" ]]; then
    msg_error "Seafile debug: failed to prepare patched build.func"
    exit 1
  fi

  log_msg "Seafile debug: patched build.func stored at ${temp_build}"
  source "${temp_build}"
  header_info "$APP"
  build_container
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW} Installer state is stored in:${CL}"
echo -e "${TAB}${BGN}/etc/seafile-installer/seafile-installer.conf${CL}"
echo -e "${INFO}${YW} Credentials are stored in:${CL}"
echo -e "${TAB}${BGN}/root/seafile.creds${CL}"
