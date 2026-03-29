FROM jenkins/jenkins:lts-jdk17

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
     ca-certificates curl jq unzip \
  && install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
     https://download.docker.com/linux/debian \
     $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
     > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin \
  && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH=amd64
ARG VAULT_VERSION=1.17.0
RUN curl -fsSL "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_${TARGETARCH}.zip" -o /tmp/vault.zip \
  && unzip /tmp/vault.zip -d /usr/local/bin \
  && rm /tmp/vault.zip \
  && chmod +x /usr/local/bin/vault

COPY entrypoint.sh /usr/local/bin/jenkins-infra-entrypoint.sh
RUN chmod +x /usr/local/bin/jenkins-infra-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/jenkins-infra-entrypoint.sh"]