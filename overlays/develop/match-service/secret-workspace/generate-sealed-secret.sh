# How to run:
# chmod +x generate-sealed-secret.sh
#./generate-sealed-secret.sh

#!/bin/bash

# === Configuration ===
SECRET_NAME="match-db-secret"
NAMESPACE="dev-match-service"
ENV_FILE=".env.secret"
SECRET_FILE="secret.yaml"
SEALED_SECRET_FILE="../sealed-secret.yaml"

# sealed-secrets-public.pem 파일 경로 확인
if [ -z "$SEALED_SECRETS_CERT" ]; then
    echo "❌ 오류: SEALED_SECRETS_CERT 환경 변수가 설정되지 않았습니다."
    exit 1
fi

if [ ! -f "$SEALED_SECRETS_CERT" ]; then
    echo "❌ 오류: sealed-secrets-public.pem 파일을 찾을 수 없습니다: $SEALED_SECRETS_CERT"
    exit 1
fi

echo "======================================="
echo "Sealed Secret Generation Script (Mac/Linux)"
echo "Location: overlays/develop/match-service/"
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
