pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    VAULT_ADDR = 'http://vault:8200'
    DOCKER_HOST = 'tcp://dockerd:2376'
    DOCKER_TLS_VERIFY = '1'
    DOCKER_BUILDKIT = '1'
    IMAGE_NAME = 'assignment5/quarkus-api'
    REGISTRY_HOST = 'registry-nginx:5444'
  }

  stages {
    stage('Сборка и публикация (Vault + mTLS Docker + кеш)') {
      steps {
        withCredentials([
          string(credentialsId: 'vault-jenkins-role-id', variable: 'VAULT_ROLE_ID'),
          string(credentialsId: 'vault-jenkins-secret-id', variable: 'VAULT_SECRET_ID')
        ]) {
          sh '''
            set +x
            export VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$VAULT_ROLE_ID" secret_id="$VAULT_SECRET_ID")
            mkdir -p "${WORKSPACE}/.docker-tls"
            vault write -format=json pki/issue/docker-client common_name="jenkins-build-${BUILD_NUMBER}" ttl=1h > "${WORKSPACE}/.docker-tls/issue.json"
            jq -r '.data.certificate' "${WORKSPACE}/.docker-tls/issue.json" > "${WORKSPACE}/.docker-tls/cert.pem"
            jq -r '.data.private_key' "${WORKSPACE}/.docker-tls/issue.json" > "${WORKSPACE}/.docker-tls/key.pem"
            jq -r '.data.issuing_ca' "${WORKSPACE}/.docker-tls/issue.json" > "${WORKSPACE}/.docker-tls/ca.pem"
            chmod 600 "${WORKSPACE}/.docker-tls/key.pem"
            export DOCKER_CERT_PATH="${WORKSPACE}/.docker-tls"
            export FULL_IMAGE="${REGISTRY_HOST}/${IMAGE_NAME}"
            WRITER_PASS=$(vault kv get -field=writer_password secret/registry/auth)
            printf '%s' "$WRITER_PASS" | docker login "${REGISTRY_HOST}" -u writer --password-stdin
            rm -f "${WORKSPACE}/.docker-tls/issue.json"
            set -x
            docker pull "${FULL_IMAGE}:buildcache" || true
            docker buildx build \
              --cache-from "${FULL_IMAGE}:buildcache" \
              -t "${FULL_IMAGE}:${BUILD_NUMBER}" \
              -t "${FULL_IMAGE}:latest" \
              -t "${FULL_IMAGE}:buildcache" \
              --load \
              .
            docker push "${FULL_IMAGE}:${BUILD_NUMBER}"
            docker push "${FULL_IMAGE}:latest"
            docker push "${FULL_IMAGE}:buildcache"
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'rm -rf "${WORKSPACE}/.docker-tls" || true'
    }
  }
}
