#!/usr/bin/env bash
# Периодическое обновление htpasswd из Vault (bcrypt), без хранения паролей в образе.
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
STATE_DIR="${STATE_DIR:-/bootstrap-state}"
REG_AUTH_DIR="${REG_AUTH_DIR:-/registry-auth}"

ROLE_ID_FILE="$STATE_DIR/registry-sync-role-id.txt"
SECRET_ID_FILE="$STATE_DIR/registry-sync-secret-id.txt"

if [[ ! -f "$ROLE_ID_FILE" || ! -f "$SECRET_ID_FILE" ]]; then
  echo "Нет RoleID/SecretID для registry-sync (ожидается bootstrap)." >&2
  sleep 60
  exit 1
fi

login_vault() {
  export VAULT_TOKEN
  VAULT_TOKEN=$(vault write -field=token auth/approle/login \
    role_id="$(cat "$ROLE_ID_FILE")" \
    secret_id="$(cat "$SECRET_ID_FILE")")
}

sync_once() {
  login_vault
  local json
  json=$(vault kv get -format=json secret/registry/auth)
  echo "$json" | jq -r '.data.data.reader_line // empty' >"$REG_AUTH_DIR/htpasswd_reader"
  echo "$json" | jq -r '.data.data.writer_line // empty' >"$REG_AUTH_DIR/htpasswd_writer"
  chmod 644 "$REG_AUTH_DIR/htpasswd_reader" "$REG_AUTH_DIR/htpasswd_writer" 2>/dev/null || true
}

while true; do
  sealed=$(vault status -format=json 2>/dev/null | jq -r '.sealed // true')
  if [[ "$sealed" == "false" ]]; then
    sync_once || true
  fi
  sleep 60
done
