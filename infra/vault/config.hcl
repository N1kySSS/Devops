# Vault в не-dev режиме: файловое хранилище, Shamir при operator init (3 ключа, порог 2)
storage "file" {
  path = "/vault/file"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://0.0.0.0:8200"
ui       = true

disable_mlock = true
