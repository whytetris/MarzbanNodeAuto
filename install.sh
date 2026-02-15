#!/usr/bin/env bash
set -euo pipefail

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

ask_yes_no() {
  local prompt="${1}"
  local ans
  read -r -p "${prompt} [y/N]: " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

install_pkgs() {
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release git nano
}

install_docker_official_repo() {
  # Official Docker repo (recommended)
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    > /etc/apt/sources.list.d/docker.list

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
  systemctl enable --now docker
  return 0
}

install_docker_fallback() {
  # Fallback: Ubuntu packages + docker-compose-v2 (available in noble)
  apt-get update
  apt-get install -y docker.io docker-compose-v2 || true
  systemctl enable --now docker
}

install_compose_manual_if_needed() {
  # If `docker compose` still missing, install plugin manually (official docs allow this).
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi

  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="x86_64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) echo "Unsupported arch for manual compose plugin: ${arch}"; return 1 ;;
  esac

  local plugin_dir="/usr/local/lib/docker/cli-plugins"
  mkdir -p "${plugin_dir}"
  curl -fL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}" \
    -o "${plugin_dir}/docker-compose"
  chmod +x "${plugin_dir}/docker-compose"

  docker compose version >/dev/null 2>&1
}

ensure_docker_and_compose() {
  # try official repo first
  if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
    echo "Installing Docker + Compose..."
    if ! install_docker_official_repo; then
      echo "Docker official repo install failed, using Ubuntu fallback..."
      install_docker_fallback
    fi
  fi

  # ensure compose works (manual fallback)
  install_compose_manual_if_needed
}

maybe_reinstall_cleanup() {
  if [[ -d "${NODE_DIR}" || -d "${DATA_DIR}" ]]; then
    echo "Marzban Node seems already installed."
    if ask_yes_no "Reinstall (this will DELETE ${NODE_DIR} and ${DATA_DIR})?"; then
      echo "Stopping/removing previous containers (if any)..."
      if [[ -f "${COMPOSE_FILE}" ]]; then
        (cd "${NODE_DIR}" && docker compose down --remove-orphans) || true
      fi
      rm -rf "${NODE_DIR}" "${DATA_DIR}"
      echo "Removed."
    else
      echo "Cancelled."
      exit 0
    fi
  fi
}

prepare_dirs() {
  mkdir -p "${NODE_DIR}" "${DATA_DIR}"
}

write_compose() {
  # Minimal, robust compose based on official Marzban Node approach:
  # - SSL_CLIENT_CERT_FILE enabled
  # - SERVICE_PROTOCOL=rest (recommended for Marzban >= 0.4.4)
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
  echo "Panel -> Node Settings -> Add New Marzban Node -> Show Certificate"
  echo "Finish input with Ctrl+D on a new line."
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
  ensure_docker_and_compose
  maybe_reinstall_cleanup
  prepare_dirs
  write_compose
  read_cert
  start_node

  echo
  echo "DONE."
  echo "Compose: ${COMPOSE_FILE}"
  echo "Cert:    ${CERT_FILE}"
  echo "Logs:    cd ${NODE_DIR} && docker compose logs -f"
}

main "$@"
