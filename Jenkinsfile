pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  environment {
    VAULT_ADDR = 'http://vault:8200'
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
            rm -f "${WORKSPACE}/.docker-tls/issue.json"

            export FULL_IMAGE="${REGISTRY_HOST}/${IMAGE_NAME}"
            WRITER_PASS=$(vault kv get -field=writer_password secret/registry/auth)

            # Создаём docker context с mTLS
            docker context rm jenkinsctx 2>/dev/null || true
            docker context create jenkinsctx \
              --docker "host=tcp://dockerd:2376,ca=${WORKSPACE}/.docker-tls/ca.pem,cert=${WORKSPACE}/.docker-tls/cert.pem,key=${WORKSPACE}/.docker-tls/key.pem"

            # Логин через context
            printf '%s' "$WRITER_PASS" | docker --context jenkinsctx login "${REGISTRY_HOST}" -u writer --password-stdin

            set -x

            # Создаём buildx builder на основе context
            docker buildx rm mybuilder 2>/dev/null || true
            docker buildx create \
              --name mybuilder \
              --driver docker-container \
              --use \
              jenkinsctx

            docker buildx build \
              --cache-from "type=registry,ref=${FULL_IMAGE}:buildcache" \
              --cache-to "type=registry,ref=${FULL_IMAGE}:buildcache,mode=max" \
              --push \
              -t "${FULL_IMAGE}:${BUILD_NUMBER}" \
              -t "${FULL_IMAGE}:latest" \
              .
          '''
        }
      }
    }
  }

  post {
    always {
      sh '''
        docker buildx rm mybuilder 2>/dev/null || true
        docker context rm jenkinsctx 2>/dev/null || true
        rm -rf "${WORKSPACE}/.docker-tls" || true
      '''
    }
  }
}