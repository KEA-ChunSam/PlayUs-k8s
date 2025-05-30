# How to run:
# chmod +x generate-sealed-secret.sh
#./generate-sealed-secret.sh

#!/bin/bash

# === Configuration ===
SECRET_NAME="twp-db-secret"
NAMESPACE="dev-twp-service"
ENV_FILE=".env.secret"
SECRET_FILE="secret.yaml"
SEALED_SECRET_FILE="../sealed-secret.yaml"

# 프로젝트 루트 디렉토리 찾기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
SEALED_SECRETS_CERT="${PROJECT_ROOT}/sealed-secrets-public.pem"

if [ ! -f "$SEALED_SECRETS_CERT" ]; then
  echo "❌ 오류: sealed-secrets-public.pem 파일을 찾을 수 없습니다: $SEALED_SECRETS_CERT"
  exit 1
fi

echo "======================================="
echo "Sealed Secret Generation Script (Mac/Linux)"
echo "Location: overlays/develop/twp-service/"
echo "======================================="

# Check if the .env.secret file exists
if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE file is missing. Please create it before running this script."
  exit 1
fi

# Generate Kubernetes Secret YAML
echo "[1/3] Creating Kubernetes Secret YAML..."
kubectl create secret generic $SECRET_NAME \
  --from-env-file=$ENV_FILE \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml > $SECRET_FILE

# Encrypt the Secret using kubeseal
echo "[2/3] Encrypting the Secret with kubeseal..."
kubeseal \
  --cert "$SEALED_SECRETS_CERT" \
  --format yaml < $SECRET_FILE > $SEALED_SECRET_FILE

# Done
echo "[3/3] Done! Output file: $SEALED_SECRET_FILE"
echo "Sealed Secret has been successfully created!"
