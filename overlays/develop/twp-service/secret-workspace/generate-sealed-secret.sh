# How to run:
# chmod +x generate-sealed-secret.sh
#./generate-sealed-secret.sh

#!/bin/bash

# === Configuration ===
SECRET_NAME="twp-db-secret"
NAMESPACE="dev-twp-service"
ENV_FILE=".env.secret"
SECRET_FILE="secret.yaml"
SEALED_SECRET_FILE="../sealed-secret/sealed-secret.yaml"
CONTROLLER_NAMESPACE="kube-system"
CONTROLLER_NAME="sealed-secrets-controller"

echo "======================================="
echo "Sealed Secret Generation Script (Mac/Linux)"
echo "Location: overlays/develop/twp-service/sealed-secret/"
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
  --controller-namespace $CONTROLLER_NAMESPACE \
  --controller-name $CONTROLLER_NAME \
  --format yaml < $SECRET_FILE > $SEALED_SECRET_FILE

# Done
echo "[3/3] Done! Output file: $SEALED_SECRET_FILE"
echo "Sealed Secret has been successfully created!"
