#!/bin/zsh
# Brain Vault — webhook server runner.
# Loads the secrets file and execs the Node server. Used by launchd (KeepAlive).

set -euo pipefail

VAULT="/Users/carlos/Brain/OBSIDIAN"
NODE="/Users/carlos/.nvm/versions/node/v20.9.0/bin/node"
LOG_DIR="$VAULT/automations/scripts/logs"
mkdir -p "$LOG_DIR"

if [[ -f "$HOME/.brain-secrets" ]]; then
  set -a
  source "$HOME/.brain-secrets"
  set +a
fi

exec "$NODE" "$VAULT/automations/scripts/webhook-server.cjs"
