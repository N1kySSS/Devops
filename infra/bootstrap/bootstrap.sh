#!/usr/bin/env bash
# Полная первичная настройка Vault: Shamir 3/2, PKI (корневой CA), KV с bcrypt,
# AppRole для Jenkins и registry-sync, выпуск TLS для registry/dockerd и клиента Jenkins,
# отзыв root-токена. Повторный запуск: только unseal (если есть .done и ключи).
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
STATE_DIR="${STATE_DIR:-/bootstrap-state}"
KEYS_FILE="${STATE_DIR}/unseal-keys.json"
DONE_FILE="${STATE_DIR}/.bootstrap_done"
CERT_DIR="${CERT_DIR:-/certs}"
REG_AUTH_DIR="${REG_AUTH_DIR:-/registry-auth}"

mkdir -p "$STATE_DIR" "$CERT_DIR/dockerd" "$CERT_DIR/registry" "$CERT_DIR/jenkins" "$REG_AUTH_DIR"

wait_for_vault() {
  local i
  for i in $(seq 1 90); do
    if curl -s "${VAULT_ADDR}/v1/sys/health" 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 2
  done
  echo "Vault API недоступен по $VAULT_ADDR" >&2
  return 1
}

unseal_if_needed() {
  local st sealed
  st=$(vault status -format=json 2>&1) || true
  if [[ -z "$st" ]] || ! echo "$st" | jq -e . >/dev/null 2>&1; then
    echo "Не удалось получить статус Vault (проверьте бинарник vault и VAULT_ADDR)." >&2
    vault version 2>&1 || true
    exit 1
  fi
  sealed=$(echo "$st" | jq -r '.sealed')
  if [[ "$sealed" != "true" ]]; then
    return 0
  fi
  if [[ ! -f "$KEYS_FILE" ]]; then
    echo "Vault запечатан, нет файла ключей $KEYS_FILE — выполните operator init вручную." >&2
    exit 1
  fi
  vault operator unseal "$(jq -r '.unseal_keys_b64[0]' "$KEYS_FILE")"
  vault operator unseal "$(jq -r '.unseal_keys_b64[1]' "$KEYS_FILE")"
}

if [[ "${1:-}" == "unseal-only" ]]; then
  wait_for_vault
  unseal_if_needed
  exit 0
fi

wait_for_vault

st_json=$(vault status -format=json 2>&1) || true
if [[ -z "$st_json" ]] || ! echo "$st_json" | jq -e . >/dev/null 2>&1; then
  echo "Не удалось получить JSON-статус Vault (часто: образ bootstrap собран с vault linux_amd64 на Mac ARM — пересоберите: docker compose build --no-cache bootstrap)." >&2
  echo "VAULT_ADDR=$VAULT_ADDR" >&2
  vault version 2>&1 || true
  vault status 2>&1 || true
  exit 1
fi
initialized=$(echo "$st_json" | jq -r '.initialized // false')
if [[ "$initialized" == "false" ]]; then
  vault operator init -key-shares=3 -key-threshold=2 -format=json >"$KEYS_FILE"
  chmod 600 "$KEYS_FILE" || true
  echo "Сохранены ключи распечатывания в volume bootstrap-state (unseal-keys.json)."
fi

unseal_if_needed

if [[ -f "$DONE_FILE" ]]; then
  echo "Bootstrap уже выполнен (есть $DONE_FILE). Выполнен только unseal."
  exit 0
fi

ROOT_TOKEN=$(jq -r '.root_token' "$KEYS_FILE")
export VAULT_TOKEN="$ROOT_TOKEN"

# --- KV и секреты registry (bcrypt для nginx + пароли для docker login в KV) ---
vault secrets enable -path=secret kv-v2 2>/dev/null || true

READER_PASS=$(openssl rand -hex 18)
WRITER_PASS=$(openssl rand -hex 18)
READER_LINE=$(htpasswd -nbB reader "$READER_PASS" | tr -d '\n')
WRITER_LINE=$(htpasswd -nbB writer "$WRITER_PASS" | tr -d '\n')

vault kv put secret/registry/auth \
  reader_line="$READER_LINE" \
  writer_line="$WRITER_LINE" \
  reader_password="$READER_PASS" \
  writer_password="$WRITER_PASS"

printf '%s\n' "$READER_LINE" >"$REG_AUTH_DIR/htpasswd_reader"
printf '%s\n' "$WRITER_LINE" >"$REG_AUTH_DIR/htpasswd_writer"
chmod 644 "$REG_AUTH_DIR/htpasswd_reader" "$REG_AUTH_DIR/htpasswd_writer"

# --- PKI: корневой CA ---
vault secrets enable pki 2>/dev/null || true
vault secrets tune -max-lease-ttl=87600h pki
if ! vault read pki/cert/ca >/dev/null 2>&1; then
  vault write pki/root/generate/internal common_name="assignment5-root-ca" ttl=87600h
fi
curl -s "${VAULT_ADDR}/v1/pki/ca/pem" >"$CERT_DIR/ca.pem"

vault write pki/roles/docker-server \
  allowed_domains="dockerd,registry,registry-nginx,localhost" \
  allow_bare_domains=true \
  max_ttl=720h \
  key_type=rsa \
  key_bits=2048

vault write pki/roles/docker-client \
  allow_any_name=true \
  max_ttl=720h \
  key_type=rsa \
  key_bits=2048

issue_server() {
  local cn="$1"
  local out_dir="$2"
  vault write -format=json pki/issue/docker-server \
    "common_name=$cn" ttl=720h \
    alt_names="DNS:dockerd,DNS:localhost" ip_sans="127.0.0.1" >"/tmp/issue-$cn.json"
  jq -r '.data.certificate' "/tmp/issue-$cn.json" >"$out_dir/server.pem"
  jq -r '.data.private_key' "/tmp/issue-$cn.json" >"$out_dir/server-key.pem"
  chmod 644 "$out_dir/server.pem"
  chmod 600 "$out_dir/server-key.pem"
}

issue_server dockerd "$CERT_DIR/dockerd"

vault write -format=json pki/issue/docker-server \
  common_name=registry-nginx ttl=720h \
  alt_names="DNS:registry,DNS:registry-nginx,DNS:localhost" >"/tmp/issue-reg.json"
jq -r '.data.certificate' "/tmp/issue-reg.json" >"$CERT_DIR/registry/server.pem"
jq -r '.data.private_key' "/tmp/issue-reg.json" >"$CERT_DIR/registry/server-key.pem"
chmod 644 "$CERT_DIR/registry/server.pem"
chmod 600 "$CERT_DIR/registry/server-key.pem"

vault write -format=json pki/issue/docker-client common_name=jenkins ttl=72h >"/tmp/issue-client.json"
jq -r '.data.certificate' "/tmp/issue-client.json" >"$CERT_DIR/jenkins/cert.pem"
jq -r '.data.private_key' "/tmp/issue-client.json" >"$CERT_DIR/jenkins/key.pem"
cp -f "$CERT_DIR/ca.pem" "$CERT_DIR/jenkins/ca.pem"
chmod 644 "$CERT_DIR/jenkins/cert.pem" "$CERT_DIR/jenkins/ca.pem"
chmod 600 "$CERT_DIR/jenkins/key.pem"

# --- AppRole: Jenkins и синхронизация htpasswd ---
vault auth enable approle 2>/dev/null || true

vault policy write jenkins-pol - <<'EOF'
path "secret/data/registry/auth" {
  capabilities = ["read"]
}
path "pki/issue/docker-client" {
  capabilities = ["create", "update"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

vault policy write registry-sync-pol - <<'EOF'
path "secret/data/registry/auth" {
  capabilities = ["read"]
}
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF

vault write auth/approle/role/jenkins token_policies="jenkins-pol" token_ttl=1h token_max_ttl=4h
vault write auth/approle/role/registry-sync token_policies="registry-sync-pol" token_ttl=1h token_max_ttl=4h

J_ROLE_ID=$(vault read -field=role_id auth/approle/role/jenkins/role-id)
RS_ROLE_ID=$(vault read -field=role_id auth/approle/role/registry-sync/role-id)
J_SECRET=$(vault write -f -field=secret_id auth/approle/role/jenkins/secret-id)
RS_SECRET=$(vault write -f -field=secret_id auth/approle/role/registry-sync/secret-id)

printf '%s\n' "$J_ROLE_ID" >"$STATE_DIR/jenkins-role-id.txt"
printf '%s\n' "$J_SECRET" >"$STATE_DIR/jenkins-secret-id.txt"
printf '%s\n' "$RS_ROLE_ID" >"$STATE_DIR/registry-sync-role-id.txt"
printf '%s\n' "$RS_SECRET" >"$STATE_DIR/registry-sync-secret-id.txt"
chmod 600 "$STATE_DIR"/*.txt 2>/dev/null || true

# Файл для docker compose / Jenkins (секреты не коммитить)
cat >"$STATE_DIR/generated.env" <<EOF
# Скопируйте в infra/generated.env для локального compose при необходимости (файл в .gitignore)
VAULT_JENKINS_ROLE_ID=$J_ROLE_ID
VAULT_JENKINS_SECRET_ID=$J_SECRET
VAULT_REGISTRY_SYNC_ROLE_ID=$RS_ROLE_ID
VAULT_REGISTRY_SYNC_SECRET_ID=$RS_SECRET
EOF
chmod 600 "$STATE_DIR/generated.env"

# --- Отзыв root-токена ---
vault token revoke -self

touch "$DONE_FILE"
echo "Bootstrap завершён. Root-токен отозван. Данные AppRole и ключи — в volume bootstrap-state."
