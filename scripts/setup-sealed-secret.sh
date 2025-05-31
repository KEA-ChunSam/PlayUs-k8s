#!/bin/bash

set -e

# === 설정 ===
NAMESPACE="kube-system"
RELEASE_NAME="sealed-secrets"
CONTROLLER_NAME="sealed-secrets-controller"
KEY_FILE="sealed-secrets-public.pem"

# OS 확인
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  ARCH="amd64"
elif [ "$ARCH" = "aarch64" ]; then
  ARCH="arm64"
fi

# kubeseal 최신 버전 확인
echo "🔍 kubeseal 최신 버전 확인 중"
KUBESEAL_VERSION=$(curl -s https://api.github.com/repos/bitnami-labs/sealed-secrets/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
echo "📌 kubeseal 버전: ${KUBESEAL_VERSION}"

echo "📦 [1] Bitnami Sealed Secrets Helm repo 추가 및 업데이트"
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update

echo "🚀 [2] Sealed Secrets Controller 설치"
helm upgrade --install ${RELEASE_NAME} sealed-secrets/sealed-secrets \
  --namespace ${NAMESPACE} \
  --create-namespace \
  --set-string fullnameOverride=${CONTROLLER_NAME}

echo "⏳ [3] 컨트롤러 준비 대기 중"
kubectl wait --namespace ${NAMESPACE} \
  --for=condition=available deployment/${CONTROLLER_NAME} \
  --timeout=180s

echo "🔑 [4] 퍼블릭 키 추출 → ${KEY_FILE}"
kubectl get secret -n ${NAMESPACE} -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o jsonpath="{.items[0].data.tls\.crt}" | base64 -d > "${KEY_FILE}"

echo "🧰 [5] kubeseal CLI 설치"
if [ "$OS" = "linux" ]; then
  TMP_DIR=$(mktemp -d)
  ORIGIN_DIR=$(pwd)
  cd "$TMP_DIR"

  # Linux용 설치
  curl -LO "https://github.com/bitnami-labs/sealed-secrets/releases/download/v${KUBESEAL_VERSION}/kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz"
  tar -xvzf "kubeseal-${KUBESEAL_VERSION}-linux-${ARCH}.tar.gz" kubeseal

  chmod +x kubeseal
  sudo mv kubeseal /usr/local/bin/

  cd "$ORIGIN_DIR"
  rm -rf "$TMP_DIR"
else
  echo "⚠️ 지원하지 않는 운영체제입니다: $OS"
  echo "수동으로 kubeseal을 설치해주세요: https://github.com/bitnami-labs/sealed-secrets/releases"
fi

echo ""
echo "✅ 설치 완료!"
echo "🔐 퍼블릭 키 저장 위치: $(pwd)/${KEY_FILE}"
echo ""
echo "💡 사용 방법:"
echo ".env 파일을 SealedSecret으로 변환하려면 함께 작성된 generate-sealed-secret.sh 스크립트를 사용하세요"
echo "   ./generate-sealed-secret.sh"
