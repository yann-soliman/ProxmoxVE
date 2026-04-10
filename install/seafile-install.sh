#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tiklaw (OpenClaw)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://manual.seafile.com/latest/setup_binary/installation/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  mariadb-server \
  redis-server \
  python3 \
  python3-dev \
  python3-setuptools \
  python3-pip \
  python3-ldap \
  python3-rados \
  python3.13-venv \
  libmariadb-dev-compat \
  default-libmysqlclient-dev \
  libmemcached-dev \
  libldap2-dev \
  libsasl2-dev \
  ldap-utils \
  build-essential \
  pkg-config \
  libhiredis-dev \
  wget \
  pwgen
msg_ok "Installed Dependencies"

SEAFILE_ROOT=/opt/seafile
SEAFILE_USER=seafile
SEAFILE_CONF_DIR=${SEAFILE_ROOT}/conf
SEAFILE_STATE_DIR=/etc/seafile-installer
SEAFILE_SETUP_ENV=/tmp/seafile-setup.env
mkdir -p "${SEAFILE_ROOT}" "${SEAFILE_STATE_DIR}"

get_lxc_ip

msg_info "Collecting Seafile installation parameters"

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local result=""
  printf "\n%s [%s]\n> " "${prompt}" "${default_value}" >/dev/tty
  read -r result </dev/tty
  if [[ -z "${result}" ]]; then
    result="${default_value}"
  fi
  printf '%s' "${result}"
}

validate_tarball_url_hint() {
  local url="$1"

  if [[ -z "${url}" ]]; then
    msg_error "A Seafile Pro tarball URL is required"
    return 1
  fi

  if [[ "${url}" == *"mode=list"* ]]; then
    msg_error "The provided URL still points to a Seafile listing page (mode=list), not a direct file"
    echo "Open the file entry in Seafile and copy the final direct download URL, not the folder/listing URL." >/dev/tty
    return 1
  fi

  if [[ ! "${url}" =~ \.(tar\.gz|tgz|tar\.xz|zip)(\?.*)?$ ]]; then
    msg_warn "The URL does not look like a direct archive link. I will still test it after download."
  fi

  return 0
}

if [[ -z "${SEAFILE_TARBALL_URL:-}" ]]; then
  msg_error "SEAFILE_TARBALL_URL environment variable is required"
  echo "Run the CT script like this:" >/dev/tty
  echo "  SEAFILE_TARBALL_URL='https://example.invalid/seafile-pro-server_x86-64.tar.gz' bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/yann-soliman/ProxmoxVE/feat/seafile-script/ct/seafile.sh)\"" >/dev/tty
  exit 1
fi

printf "\nUsing Seafile Pro tarball URL from environment.\n" >/dev/tty
if ! validate_tarball_url_hint "${SEAFILE_TARBALL_URL}"; then
  exit 1
fi

SEAFILE_SERVER_NAME=$(prompt_with_default "Seafile server name" "seafile")
SEAFILE_SERVER_HOSTNAME=$(prompt_with_default "Seafile server hostname or IP" "${LOCAL_IP}")
SEAFILE_FILESERVER_PORT=$(prompt_with_default "Fileserver port" "8082")
SEAFILE_ADMIN_EMAIL=$(prompt_with_default "Admin email" "admin@local.invalid")
SEAFILE_ADMIN_PASSWORD=$(pwgen -s 20 1)
SEAFILE_DB_PASS=$(pwgen -s 24 1)
JWT_PRIVATE_KEY=$(pwgen -s 40 1)

msg_info "Persisting installer state"
cat <<STATE_EOF > ${SEAFILE_STATE_DIR}/seafile-installer.conf
SEAFILE_TARBALL_URL='${SEAFILE_TARBALL_URL}'
SEAFILE_SERVER_NAME='${SEAFILE_SERVER_NAME}'
SEAFILE_SERVER_HOSTNAME='${SEAFILE_SERVER_HOSTNAME}'
SEAFILE_FILESERVER_PORT='${SEAFILE_FILESERVER_PORT}'
SEAFILE_ADMIN_EMAIL='${SEAFILE_ADMIN_EMAIL}'
STATE_EOF
chmod 600 ${SEAFILE_STATE_DIR}/seafile-installer.conf
msg_ok "Persisted installer state"

msg_info "Preparing MariaDB and Redis"
systemctl enable -q --now mariadb redis-server
mariadb <<SQL
CREATE DATABASE IF NOT EXISTS ccnet_db CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS seafile_db CHARACTER SET utf8;
CREATE DATABASE IF NOT EXISTS seahub_db CHARACTER SET utf8;
CREATE USER IF NOT EXISTS 'seafile'@'localhost' IDENTIFIED BY '${SEAFILE_DB_PASS}';
ALTER USER 'seafile'@'localhost' IDENTIFIED BY '${SEAFILE_DB_PASS}';
GRANT ALL PRIVILEGES ON ccnet_db.* TO 'seafile'@'localhost';
GRANT ALL PRIVILEGES ON seafile_db.* TO 'seafile'@'localhost';
GRANT ALL PRIVILEGES ON seahub_db.* TO 'seafile'@'localhost';
FLUSH PRIVILEGES;
SQL
msg_ok "Prepared MariaDB and Redis"

if ! id -u ${SEAFILE_USER} >/dev/null 2>&1; then
  msg_info "Creating seafile user"
  /usr/sbin/adduser --disabled-password --gecos "" ${SEAFILE_USER}
  msg_ok "Created seafile user"
fi
chown -R ${SEAFILE_USER}:${SEAFILE_USER} ${SEAFILE_ROOT}

msg_info "Setting up Python virtual environment"
sudo -u ${SEAFILE_USER} python3 -m venv ${SEAFILE_ROOT}/python-venv
sudo -u ${SEAFILE_USER} bash -lc "source ${SEAFILE_ROOT}/python-venv/bin/activate && pip3 install --timeout=3600 boto3 oss2 twilio configparser pytz sqlalchemy==2.0.* pymysql==1.1.* jinja2 django-pylibmc pylibmc redis django-redis psd-tools lxml django==5.2.* cffi==1.17.1 future==1.0.* mysqlclient==2.2.* captcha==0.7.* django_simple_captcha==0.6.* pyjwt==2.10.* djangosaml2==1.11.* pysaml2==7.5.* pycryptodome==3.23.* python-ldap==3.4.* pillow==11.3.* pillow-heif==1.0.* cairosvg==2.8.* scikit-learn==1.7.*"
msg_ok "Set up Python virtual environment"

msg_info "Downloading Seafile Pro tarball"
TARBALL_NAME=$(basename "${SEAFILE_TARBALL_URL%%\?*}")
[[ -z "${TARBALL_NAME}" || "${TARBALL_NAME}" == "download" ]] && TARBALL_NAME="seafile-pro-download"
TARBALL_PATH=${SEAFILE_ROOT}/${TARBALL_NAME}
sudo -u ${SEAFILE_USER} wget --content-disposition -O "${TARBALL_PATH}" "${SEAFILE_TARBALL_URL}"
msg_ok "Downloaded Seafile Pro tarball"

msg_info "Validating downloaded Seafile archive"
FILE_TYPE=$(file -b "${TARBALL_PATH}" || true)
log_msg "Seafile debug: downloaded file type: ${FILE_TYPE}"
if grep -qiE 'HTML document|XML document|ASCII text|Unicode text|JSON text' <<<"${FILE_TYPE}"; then
  msg_error "Downloaded file is not a tarball archive, it looks like: ${FILE_TYPE}"
  echo "The provided URL did not return a Seafile archive. It likely points to a web page, not a direct file download." >/dev/tty
  exit 1
fi

if ! tar -tf "${TARBALL_PATH}" >/tmp/seafile-tar-list.txt 2>/dev/null; then
  msg_error "Downloaded file is not a valid tar archive"
  echo "The provided URL did not return a valid Seafile tarball. Please use a direct archive download URL." >/dev/tty
  exit 1
fi
SEAFILE_EXTRACTED_DIR=$(head -n1 /tmp/seafile-tar-list.txt | cut -d/ -f1)
if [[ -z "${SEAFILE_EXTRACTED_DIR}" ]]; then
  msg_error "Unable to determine extracted Seafile directory from archive"
  exit 1
fi
msg_ok "Validated downloaded Seafile archive"

msg_info "Extracting Seafile Pro tarball"
sudo -u ${SEAFILE_USER} tar -C ${SEAFILE_ROOT} -xf "${TARBALL_PATH}"
SEAFILE_INSTALL_DIR=${SEAFILE_ROOT}/${SEAFILE_EXTRACTED_DIR}
ln -sfn ${SEAFILE_INSTALL_DIR} ${SEAFILE_ROOT}/seafile-server-latest
msg_ok "Extracted Seafile Pro tarball"

msg_info "Running Seafile setup"
cat <<EOF_SETUP > ${SEAFILE_SETUP_ENV}
export LC_ALL=C
export PYTHONUNBUFFERED=1
EOF_SETUP
chown ${SEAFILE_USER}:${SEAFILE_USER} ${SEAFILE_SETUP_ENV}
chmod 600 ${SEAFILE_SETUP_ENV}
cat <<SETUP_INPUT | sudo -u ${SEAFILE_USER} bash -lc "source ${SEAFILE_SETUP_ENV}; source ${SEAFILE_ROOT}/python-venv/bin/activate; cd ${SEAFILE_INSTALL_DIR}; ./setup-seafile-mysql.sh"

${SEAFILE_SERVER_NAME}
${SEAFILE_SERVER_HOSTNAME}
${SEAFILE_FILESERVER_PORT}
2
localhost
3306
seafile
${SEAFILE_DB_PASS}
ccnet_db
seafile_db
seahub_db
SETUP_INPUT
msg_ok "Ran Seafile setup"

msg_info "Creating Seafile environment file"
mkdir -p ${SEAFILE_CONF_DIR}
cat <<ENV_EOF > ${SEAFILE_CONF_DIR}/.env
JWT_PRIVATE_KEY=${JWT_PRIVATE_KEY}
SEAFILE_SERVER_PROTOCOL=http
SEAFILE_SERVER_HOSTNAME=${SEAFILE_SERVER_HOSTNAME}
SEAFILE_MYSQL_DB_HOST=localhost
SEAFILE_MYSQL_DB_PORT=3306
SEAFILE_MYSQL_DB_USER=seafile
SEAFILE_MYSQL_DB_PASSWORD=${SEAFILE_DB_PASS}
SEAFILE_MYSQL_DB_CCNET_DB_NAME=ccnet_db
SEAFILE_MYSQL_DB_SEAFILE_DB_NAME=seafile_db
SEAFILE_MYSQL_DB_SEAHUB_DB_NAME=seahub_db
CACHE_PROVIDER=redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
ENV_EOF
chown ${SEAFILE_USER}:${SEAFILE_USER} ${SEAFILE_CONF_DIR}/.env
chmod 600 ${SEAFILE_CONF_DIR}/.env
msg_ok "Created Seafile environment file"

msg_info "Creating run_with_venv helper"
cat <<'EOF_VENV' > ${SEAFILE_ROOT}/run_with_venv.sh
#!/bin/bash
dir_name="$(cd "$(dirname "$0")" && pwd)"
source "${dir_name}/python-venv/bin/activate"
script="$1"
shift 1
exec "${dir_name}/seafile-server-latest/${script}" "$@"
EOF_VENV
chown ${SEAFILE_USER}:${SEAFILE_USER} ${SEAFILE_ROOT}/run_with_venv.sh
chmod 755 ${SEAFILE_ROOT}/run_with_venv.sh
msg_ok "Created run_with_venv helper"

msg_info "Creating systemd services"
cat <<EOF_SEAFILE >/etc/systemd/system/seafile.service
[Unit]
Description=Seafile
After=network.target mariadb.service redis-server.service

[Service]
Type=forking
ExecStart=bash ${SEAFILE_ROOT}/run_with_venv.sh seafile.sh start
ExecStop=bash ${SEAFILE_ROOT}/seafile-server-latest/seafile.sh stop
LimitNOFILE=infinity
User=${SEAFILE_USER}
Group=${SEAFILE_USER}

[Install]
WantedBy=multi-user.target
EOF_SEAFILE

cat <<EOF_SEAHUB >/etc/systemd/system/seahub.service
[Unit]
Description=Seafile hub
After=network.target seafile.service

[Service]
Type=forking
ExecStart=bash ${SEAFILE_ROOT}/run_with_venv.sh seahub.sh start
ExecStop=bash ${SEAFILE_ROOT}/seafile-server-latest/seahub.sh stop
User=${SEAFILE_USER}
Group=${SEAFILE_USER}

[Install]
WantedBy=multi-user.target
EOF_SEAHUB
systemctl daemon-reload
msg_ok "Created systemd services"

msg_info "Starting Seafile services"
systemctl enable -q --now seafile.service
sudo -u ${SEAFILE_USER} bash -lc "cd ${SEAFILE_ROOT}/seafile-server-latest && yes | bash ./seahub.sh start"
systemctl enable -q seahub.service
msg_ok "Started Seafile services"

msg_info "Creating credentials file"
cat <<CREDS_EOF > /root/seafile.creds
Seafile URL: http://${SEAFILE_SERVER_HOSTNAME}
Seafile Admin Email: ${SEAFILE_ADMIN_EMAIL}
Seafile Admin Password: ${SEAFILE_ADMIN_PASSWORD}
Seafile DB Password: ${SEAFILE_DB_PASS}
Tarball URL: ${SEAFILE_TARBALL_URL}
CREDS_EOF
chmod 600 /root/seafile.creds
msg_ok "Created credentials file"

motd_ssh
customize
cleanup_lxc
