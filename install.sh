#!/usr/bin/env bash
set -euo pipefail

NODE_DIR="/opt/marzban-node"
DATA_DIR="/var/lib/marzban-node"
CERT_FILE="${DATA_DIR}/ssl_client_cert.pem"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root (use sudo)."
    exit 1
  fi
}

install_pkgs() {
  apt-get update
  apt-get install -y ca-certificates curl git nano jq ufw
}

install_docker() {
  # Ubuntu repo вариант (просто и стабильно)
  apt-get install -y docker.io docker-compose-plugin
  systemctl enable --now docker
  docker compose version >/dev/null
}

clone_repo() {
  if [[ -d "${NODE_DIR}" ]]; then
    echo "Repo exists: ${NODE_DIR} (pulling latest)"
    git -C "${NODE_DIR}" pull --ff-only
  else
    git clone https://github.com/Gozargah/Marzban-node "${NODE_DIR}"
  fi
}

prepare_dirs() {
  mkdir -p "${DATA_DIR}"
}

patch_compose() {
  local f="${NODE_DIR}/docker-compose.yml"
  if [[ ! -f "${f}" ]]; then
    echo "docker-compose.yml not found in ${NODE_DIR}"
    exit 1
  fi

  # 1) Убрать SSL_CERT_FILE / SSL_KEY_FILE (их просят удалить в доке)
  #    Мы не удаляем, а комментируем, чтобы апдейты не ломались.
  sed -i -E \
    -e 's/^[[:space:]]*(SSL_CERT_FILE:)/# \1/' \
    -e 's/^[[:space:]]*(SSL_KEY_FILE:)/# \1/' \
    "${f}"

  # 2) Включить SSL_CLIENT_CERT_FILE (раскоментировать)
  sed -i -E \
    -e 's/^[[:space:]]*#[[:space:]]*(SSL_CLIENT_CERT_FILE:)/          \1/' \
    "${f}"

  # 3) Включить REST протокол (стабильнее для новых версий)
  sed -i -E \
    -e 's/^[[:space:]]*#[[:space:]]*(SERVICE_PROTOCOL:)/          \1/' \
    "${f}"

  # 4) Если вдруг строки отсутствуют (после обновлений репы) — добавим в environment
  if ! grep -q 'SSL_CLIENT_CERT_FILE:' "${f}"; then
    echo "SSL_CLIENT_CERT_FILE not found, please update script for new compose format."
    exit 1
  fi
}

read_cert() {
  echo
  echo "Paste SSL CLIENT CERT (from Marzban Panel -> Node Settings -> Show Certificate)."
  echo "When finished, press Ctrl+D on a new line."
  echo

  umask 077
  cat > "${CERT_FILE}"

  if ! grep -q "BEGIN CERTIFICATE" "${CERT_FILE}"; then
    echo "Certificate does not look like PEM. File: ${CERT_FILE}"
    exit 1
  fi

  echo "Saved: ${CERT_FILE}"
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
  clone_repo
  prepare_dirs
  patch_compose
  read_cert
  start_node

  echo
  echo "DONE."
  echo "Logs:  cd ${NODE_DIR} && docker compose logs -f"
  echo "Cert:  ${CERT_FILE}"
}

main "$@"
