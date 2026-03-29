#!/usr/bin/env bash
set -euo pipefail

if [[ -f /certs/ca.pem ]]; then
  cp /certs/ca.pem /usr/local/share/ca-certificates/assignment5-registry-ca.crt
  update-ca-certificates

  mkdir -p /etc/docker/certs.d/registry-nginx:5443
  mkdir -p /etc/docker/certs.d/registry-nginx:5444
  cp /certs/ca.pem /etc/docker/certs.d/registry-nginx:5443/ca.crt
  cp /certs/ca.pem /etc/docker/certs.d/registry-nginx:5444/ca.crt
fi

if [[ -x /usr/bin/tini ]]; then
  exec /usr/bin/tini -- /usr/local/bin/jenkins.sh "$@"
fi
exec /usr/local/bin/jenkins.sh "$@"
