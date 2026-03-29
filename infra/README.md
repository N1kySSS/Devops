# Практическое задание №5: Vault, приватный Registry, Docker mTLS, Jenkins

Комплекс разворачивается через Docker Compose (Linux / WSL2 / Docker Desktop с Linux-контейнерами).

## Состав

| Компонент | Описание |
|-----------|----------|
| **Vault** | Не dev-режим, файловое хранилище; инициализация Shamir **3 ключа / порог 2**; PKI как корневой CA; KV с bcrypt-строками для nginx и паролями для `docker login`; AppRole для Jenkins и для синхронизации registry; после настройки **root-токен отзывается**. |
| **Registry** | `registry:2` за nginx с **HTTPS**; **5443** — reader (только GET/HEAD/OPTIONS, pull); **5444** — writer (push/pull). Учётные данные берутся из Vault (bcrypt в KV, обновление sidecar `auth-sync`). |
| **dockerd (dind)** | TCP **2376**, **mTLS**, серверный сертификат из Vault PKI. |
| **Jenkins** | Образ с `vault`, `docker` CLI; в пайплайне секреты только из Vault (см. корневой `Jenkinsfile`); учётные данные AppRole — в **Credentials** Jenkins, не в репозитории. |

## Быстрый старт

На **Apple Silicon (arm64)** образы должны подтягивать Vault **linux_arm64** (в `Dockerfile` используется `TARGETARCH` от BuildKit). Если раньше собирали только под amd64, пересоберите: `docker compose -f compose.yml build --no-cache bootstrap jenkins`.

Из каталога `infra`:

```bash
docker compose -f compose.yml build
docker compose -f compose.yml up -d vault
docker compose -f compose.yml run --rm bootstrap
docker compose -f compose.yml up -d
```

После успешного `bootstrap` из named volume `bootstrap-state` нужно извлечь учётные данные для Jenkins и при необходимости сохранить `generated.env` на хост (файл в `.gitignore`):

```bash
docker run --rm -v infra_bootstrap-state:/data alpine cat /data/generated.env
```

(имя volume может отличаться — смотрите `docker volume ls`, префикс обычно имя проекта.)

## Jenkins

1. Откройте Jenkins: `http://localhost:8081` (порт в `compose.yml`). Первый пароль администратора: `docker compose -f compose.yml logs jenkins 2>&1 | findstr /i "password"` (Windows) или `docker compose ... logs jenkins | grep -i password` (Linux/macOS).
2. Создайте учётные записи типа **Secret text**: `vault-jenkins-role-id`, `vault-jenkins-secret-id` (значения из `jenkins-role-id.txt` / `jenkins-secret-id.txt` в volume `bootstrap-state`).
3. Создайте pipeline из SCM с `Jenkinsfile` из корня репозитория.

Сборка запрашивает из Vault клиентский сертификат для Docker (mTLS) и пароль writer для registry; вывод с `set +x` до операций с секретами, пароль в лог не попадает.

## После перезапуска Vault

Если Vault снова **sealed**, распечатайте двумя ключами из `unseal-keys.json` в volume `bootstrap-state`:

```bash
docker compose -f compose.yml run --rm bootstrap unseal-only
```

Либо вручную:

```bash
docker compose -f compose.yml exec vault vault operator unseal <ключ1>
docker compose -f compose.yml exec vault vault operator unseal <ключ2>
```

## Проверка reader / writer

- **Reader** (только pull), порт 5443, пользователь `reader`, пароль из KV `reader_password` (посмотреть: `vault kv get secret/registry/auth` с токеном с правами — после bootstrap root отозван, используйте AppRole с политикой на чтение или заранее сохранённый пароль из вывода bootstrap).

- **Writer** (push/pull), порт 5444, пользователь `writer`.

Пример (с хоста, если открыты порты):

```bash
docker login localhost:5443 -u reader
docker pull localhost:5443/assignment5/quarkus-api:latest   # должно работать
docker push ... # на 5443 должно быть запрещено nginx (limit_except)
```

## TLS

Внутри сети compose Vault слушает HTTP (`:8200`) для упрощения демонстрации; **TLS** включён для **registry** (nginx), **dockerd** (2376) и выпускается **PKI Vault**. При необходимости включите TLS listener для Vault отдельно и переведите клиентов на `https://vault:8200`.

## Файлы

- `compose.yml` — стек.
- `vault/config.hcl` — конфиг сервера Vault.
- `bootstrap/` — образ первичной настройки и `auth-sync`.
- `nginx/registry.conf` — два виртуальных HTTPS-фронта для registry.
- `jenkins/` — образ Jenkins с доверенным CA registry.
