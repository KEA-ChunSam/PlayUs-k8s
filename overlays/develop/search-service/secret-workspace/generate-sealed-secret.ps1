# Windows (PowerShell)
# Run using:
# .\generate-sealed-secret.ps1

# === Configuration ===
$SecretName = "search-db-secret"
$Namespace = "dev-search-service"
$EnvFile = ".env.secret"
$SecretFile = "secret.yaml"
$SealedSecretFile = "../sealed-secret/sealed-secret.yaml"
$ControllerNamespace = "kube-system"
$ControllerName = "sealed-secrets-controller"

Write-Output "======================================="
Write-Output "Sealed Secret Generation Script (Windows PowerShell)"
Write-Output "Location: overlays/develop/search-service/sealed-secret/"
Write-Output "======================================="

# Check if the .env.secret file exists
if (!(Test-Path $EnvFile)) {
    Write-Error "$EnvFile file is missing. Please create it before running this script."
    exit 1
}

# Generate Kubernetes Secret YAML
Write-Output "[1/3] Creating Kubernetes Secret YAML..."
kubectl create secret generic $SecretName `
    --from-env-file=$EnvFile `
    --namespace $Namespace `
    --dry-run=client -o yaml > $SecretFile

# Encrypt the Secret using kubeseal
Write-Output "[2/3] Encrypting the Secret with kubeseal..."
Get-Content $SecretFile | kubeseal `
    --controller-namespace $ControllerNamespace `
    --controller-name $ControllerName `
    --format yaml | Out-File -Encoding utf8 $SealedSecretFile

# 3️⃣ Done
Write-Output "[3/3] Done! Output file: $SealedSecretFile"
Write-Output "Sealed Secret has been successfully created!"
