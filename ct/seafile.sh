#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tiklaw (OpenClaw)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://manual.seafile.com/latest/setup_binary/installation/

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

header_info "$APP"
variables
var_install="seafile-install"
color
catch_errors

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
  local custom_install_script_url

  custom_install_func_url="${CUSTOM_REPO}/misc/install.func"
  custom_install_script_url="${CUSTOM_REPO}/install/${var_install}.sh"

  export FUNCTIONS_FILE_PATH="$(curl -fsSL "${custom_install_func_url}")"
  if [[ -z "$FUNCTIONS_FILE_PATH" || ${#FUNCTIONS_FILE_PATH} -lt 100 ]]; then
    msg_error "Unable to load install.func from custom repo: ${custom_install_func_url}"
    exit 1
  fi

  export CUSTOM_INSTALL_SCRIPT_URL="${custom_install_script_url}"

  header_info "$APP"
  create_lxc_container
  CT_CREATED=1

  msg_info "Running custom Seafile install script from fork"
  echo -e "${TAB}${BGN}${CUSTOM_INSTALL_SCRIPT_URL}${CL}"
  lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL "${CUSTOM_INSTALL_SCRIPT_URL}")"
  local lxc_exit=$?
  if [[ $lxc_exit -ne 0 ]]; then
    msg_error "Custom Seafile install script failed with exit code ${lxc_exit}"
    exit $lxc_exit
  fi
  msg_ok "Custom Seafile install script completed"
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
