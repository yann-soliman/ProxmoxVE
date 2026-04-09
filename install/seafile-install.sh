#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tiklaw (OpenClaw)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.seafile.com/ | Github: https://github.com/haiwen/seafile-docker

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  openssl
msg_ok "Installed Dependencies"

setup_docker
get_lxc_ip

SEAFILE_DIR=/opt/seafile
SEAFILE_DATA_DIR=${SEAFILE_DIR}/data
SEAFILE_DB_DIR=${SEAFILE_DIR}/mysql
mkdir -p "${SEAFILE_DATA_DIR}" "${SEAFILE_DB_DIR}"

SEAFILE_DB_USER="seafile"
SEAFILE_DB_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)"
MYSQL_ROOT_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)"
SEAFILE_ADMIN_EMAIL="admin@local.invalid"
SEAFILE_ADMIN_PASS="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)"
SEAFILE_SERVER_HOSTNAME="${LOCAL_IP}"
SEAFILE_SERVER_PROTOCOL="http"

msg_info "Creating Seafile credentials file"
cat <<CREDS_EOF > ~/seafile.creds
Seafile URL: ${SEAFILE_SERVER_PROTOCOL}://${SEAFILE_SERVER_HOSTNAME}
Seafile Admin Email: ${SEAFILE_ADMIN_EMAIL}
Seafile Admin Password: ${SEAFILE_ADMIN_PASS}
MariaDB Root Password: ${MYSQL_ROOT_PASS}
Seafile Database User: ${SEAFILE_DB_USER}
Seafile Database Password: ${SEAFILE_DB_PASS}
Data Directory: ${SEAFILE_DATA_DIR}
Database Directory: ${SEAFILE_DB_DIR}
CREDS_EOF
chmod 600 ~/seafile.creds
msg_ok "Created credentials file"

msg_info "Creating Docker Compose stack"
cat <<COMPOSE_EOF > ${SEAFILE_DIR}/docker-compose.yml
services:
  db:
    image: mariadb:11.4
    container_name: seafile-db
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      MYSQL_LOG_CONSOLE: "true"
      MARIADB_AUTO_UPGRADE: "1"
    volumes:
      - ${SEAFILE_DB_DIR}:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mariadb-admin", "ping", "-h", "localhost", "-p${MYSQL_ROOT_PASS}"]
      interval: 20s
      timeout: 5s
      retries: 10

  seafile:
    image: seafileltd/seafile-mc:latest
    container_name: seafile
    restart: unless-stopped
    ports:
      - "80:80"
    depends_on:
      db:
        condition: service_healthy
    environment:
      DB_HOST: db
      DB_ROOT_PASSWD: ${MYSQL_ROOT_PASS}
      TIME_ZONE: Europe/Paris
      SEAFILE_ADMIN_EMAIL: ${SEAFILE_ADMIN_EMAIL}
      SEAFILE_ADMIN_PASSWORD: ${SEAFILE_ADMIN_PASS}
      SEAFILE_SERVER_LETSENCRYPT: "false"
      SEAFILE_SERVER_HOSTNAME: ${SEAFILE_SERVER_HOSTNAME}
      SEAFILE_SERVER_PROTOCOL: ${SEAFILE_SERVER_PROTOCOL}
      INIT_SEAFILE_MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASS}
      SEAFILE_MYSQL_DB_CCNET_DB_NAME: ccnet_db
      SEAFILE_MYSQL_DB_SEAFILE_DB_NAME: seafile_db
      SEAFILE_MYSQL_DB_SEAHUB_DB_NAME: seahub_db
      SEAFILE_MYSQL_DB_USER: ${SEAFILE_DB_USER}
      SEAFILE_MYSQL_DB_PASSWORD: ${SEAFILE_DB_PASS}
    volumes:
      - ${SEAFILE_DATA_DIR}:/shared
COMPOSE_EOF
msg_ok "Created Docker Compose stack"

msg_info "Starting Seafile stack"
cd ${SEAFILE_DIR}
$STD docker compose up -d
msg_ok "Started Seafile stack"

motd_ssh
customize
cleanup_lxc
