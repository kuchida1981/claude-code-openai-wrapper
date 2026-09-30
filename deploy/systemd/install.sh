#!/usr/bin/env bash
# Installs claude-wrapper as a user-level systemd service (systemctl --user)
# on this machine. No sudo/root required for the service itself; the script
# uses `loginctl enable-linger` (also no root needed for your own account on
# most distros) so the service starts at boot and survives logout.
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
UNIT_DIR="${HOME}/.config/systemd/user"
UNIT_PATH="${UNIT_DIR}/${UNIT_NAME}"

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not as root (it's a --user service)." >&2
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

echo "Repo dir:  ${REPO_DIR}"
echo "Unit path: ${UNIT_PATH}"
echo "Poetry:    ${POETRY_BIN}"

echo ""
echo "Installing dependencies (poetry install --no-root)..."
( cd "${REPO_DIR}" && "${POETRY_BIN}" install --no-root )

mkdir -p "${UNIT_DIR}"

sed \
  -e "s|__HOME__|${HOME}|g" \
  -e "s|__REPO_DIR__|${REPO_DIR}|g" \
  -e "s|__POETRY_BIN__|${POETRY_BIN}|g" \
  "${TEMPLATE}" > "${UNIT_PATH}"

systemctl --user daemon-reload
systemctl --user enable --now "${UNIT_NAME}"

# Let the user service start at boot / survive logout without an active
# session. Harmless to re-run if already enabled.
loginctl enable-linger "$(whoami)" || {
  echo "WARNING: could not enable linger for $(whoami)." >&2
  echo "The service will stop when you log out until you run:" >&2
  echo "  loginctl enable-linger $(whoami)" >&2
}

echo ""
echo "Installed and started ${UNIT_NAME} (user service)."
echo "  Status:  systemctl --user status ${UNIT_NAME}"
echo "  Logs:    journalctl --user -u ${UNIT_NAME} -f"
echo "  Restart: systemctl --user restart ${UNIT_NAME}   (after git pull / .env changes)"
