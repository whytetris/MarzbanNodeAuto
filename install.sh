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

ensure_docker_and_compose() {
  # Docker (Ubuntu packages)
  if ! command -v docker >/dev/null 2>&1; then
    apt-get update
    apt-get install -y docker.io
    systemctl enable --now docker
  else
    systemctl enable --now docker || true
  fi

  # Compose v2 (Ubuntu package)
  if ! docker compose version >/dev/null 2>&1; then
    apt-get update
    apt-get install -y docker-compose-v2
  fi

  # Final check
  docker --version >/dev/null
  docker compose version >/dev/null
}

maybe_reinstall_cleanup() {
  if [[ -d "${NODE_DIR}" || -d "${DATA_DIR}" ]]; then
    echo "Marzban Node already exists:"
    [[ -d "${NODE_DIR}" ]] && echo " - ${NODE_DIR}"
    [[ -d "${DATA_DIR}" ]] && echo " - ${DATA_DIR}"

    if ask_yes_no "Reinstall? (will DELETE everything above)"; then
      echo "Stopping old containers (if any)..."
      if [[ -f "${COMPOSE_FILE}" ]]; then
        (cd "${NODE_DIR}" && docker compose down --remove-orphans) || true
      fi
      rm -rf "${NODE_DIR}" "${DATA_DIR}"
      echo "Removed old installation."
    else
      echo "Ok, leaving as is."
      exit 0
    fi
  fi
}

prepare_dirs() {
  mkdir -p "${NODE_DIR}" "${DATA_DIR}"
}

write_compose() {
  # Minimal + stable: host network + cert + REST
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
  echo "Finish with Ctrl+D on a new line."
  echo

  umask 077
  cat > "${CERT_FILE}"

  if ! grep -q "BEGIN CERTIFICATE" "${CERT_FILE}"; then
    echo "ERROR: certificate does not look like PEM. File: ${CERT_FILE}"
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
