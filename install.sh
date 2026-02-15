#!/usr/bin/env bash
set -euo pipefail

# ---- settings ----
NODE_DIR="/opt/marzban-node"
DATA_DIR="/var/lib/marzban-node"
CERT_FILE="${DATA_DIR}/ssl_client_cert.pem"
COMPOSE_FILE="${NODE_DIR}/docker-compose.yml"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (use sudo)."
    exit 1
  fi
}

install_pkgs() {
  apt-get update
  apt-get install -y ca-certificates curl git nano
}

install_docker() {
  # официальный способ из доки (актуальный docker + docker compose)
  if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
  fi
  systemctl enable --now docker

  # убедимся что есть docker compose (v2)
  if ! docker compose version >/dev/null 2>&1; then
    apt-get update
    apt-get install -y docker-compose-plugin
  fi

  docker compose version >/dev/null
}

prepare_dirs() {
  mkdir -p "${NODE_DIR}" "${DATA_DIR}"
}

write_compose() {
  # Эталон из официальной документации:
  # - SSL_CLIENT_CERT_FILE включён
  # - SERVICE_PROTOCOL=rest (для Marzban v0.4.4+ стабильнее)
  # - SSL_CERT_FILE / SSL_KEY_FILE не используем для связи с панелью
  cat > "${COMPOSE_FILE}" <<'YML'
services:
  marzban-node:
    image: gozargah/marzban-node:latest
    restart: always
    network_mode: host

    environment:
      SSL_CLIENT_CERT_FILE: "/var/lib/marzban-node/ssl_client_cert.pem"
      SERVICE_PROTOCOL: "rest"

    volumes:
      - /var/lib/marzban-node:/var/lib/marzban-node
YML
}

read_cert() {
  echo
  echo "Paste SSL CLIENT CERT from Marzban Panel:"
  echo "Node Settings -> Add New Marzban Node -> Show Certificate"
  echo "Finish with Ctrl+D on a new line."
  echo

  umask 077
  cat > "${CERT_FILE}"

  if ! grep -q "BEGIN CERTIFICATE" "${CERT_FILE}"; then
    echo "Certificate does not look like PEM. File: ${CERT_FILE}"
    exit 1
  fi
}

start_node() {
  cd "${NODE_DIR}"
  docker compose up -d
  docker compose ps
}

main() {
  need_root
  install_pkgs
  install_docker
  prepare_dirs
  write_compose
  read_cert
  start_node

  echo
  echo "DONE."
  echo "Compose: ${COMPOSE_FILE}"
  echo "Cert:   ${CERT_FILE}"
  echo "Logs:   cd ${NODE_DIR} && docker compose logs -f"
}

main "$@"
