#!/usr/bin/env bash
# Installs claude-wrapper as a systemd service on this machine.
#
# Usage: deploy/systemd/install.sh
#
# Safe to re-run: it regenerates the unit file from the template and
# reloads systemd. Run it again after `git pull` if the template changed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE="${SCRIPT_DIR}/claude-wrapper.service.template"
UNIT_NAME="claude-wrapper.service"
UNIT_PATH="/etc/systemd/system/${UNIT_NAME}"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user (it uses sudo where needed), not as root." >&2
  exit 1
fi

ENV_FILE="${REPO_DIR}/.env"
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy .env.example to .env and configure it first." >&2
  exit 1
fi

if ! grep -qE '^API_KEY=.+' "${ENV_FILE}"; then
  echo "ERROR: API_KEY is not set in ${ENV_FILE}." >&2
  echo "Running under systemd has no TTY, so the interactive API-key prompt" >&2
  echo "silently falls back to NO AUTHENTICATION. Set API_KEY explicitly" >&2
  echo "in .env before installing this service." >&2
  exit 1
fi

POETRY_BIN="$(command -v poetry || true)"
if [[ -z "${POETRY_BIN}" && -x "${HOME}/.local/bin/poetry" ]]; then
  POETRY_BIN="${HOME}/.local/bin/poetry"
fi
if [[ -z "${POETRY_BIN}" ]]; then
  echo "ERROR: could not find the poetry binary (checked PATH and ~/.local/bin)." >&2
  exit 1
fi

RUN_USER="$(id -un)"
RUN_GROUP="$(id -gn)"

echo "Repo dir:  ${REPO_DIR}"
echo "Run as:    ${RUN_USER}:${RUN_GROUP}"
echo "Poetry:    ${POETRY_BIN}"

sed \
  -e "s|__USER__|${RUN_USER}|g" \
  -e "s|__GROUP__|${RUN_GROUP}|g" \
  -e "s|__HOME__|${HOME}|g" \
  -e "s|__REPO_DIR__|${REPO_DIR}|g" \
  -e "s|__POETRY_BIN__|${POETRY_BIN}|g" \
  "${TEMPLATE}" | sudo tee "${UNIT_PATH}" > /dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now "${UNIT_NAME}"

echo ""
echo "Installed and started ${UNIT_NAME}."
echo "  Status:  sudo systemctl status ${UNIT_NAME}"
echo "  Logs:    sudo journalctl -u ${UNIT_NAME} -f"
echo "  Restart: sudo systemctl restart ${UNIT_NAME}   (after git pull / .env changes)"
