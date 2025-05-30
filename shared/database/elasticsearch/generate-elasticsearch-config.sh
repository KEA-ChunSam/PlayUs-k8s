#!/bin/bash

# Elasticsearch IP Configuration Generator for SealedSecret
# 사용법: ./generate-elasticsearch-config.sh <elasticsearch-ip>
# 예시: ./generate-elasticsearch-config.sh 0.0.0.0

set -e

if [ -z "$1" ]; then
  echo "❌ 오류: Elasticsearch IP를 인자로 전달해주세요."
  echo "사용법: $0 <elasticsearch-ip>"
  exit 1
fi

# 프로젝트 루트 디렉토리 찾기
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SEALED_SECRETS_CERT="${PROJECT_ROOT}/sealed-secrets-public.pem"

if [ ! -f "$SEALED_SECRETS_CERT" ]; then
  echo "❌ 오류: sealed-secrets-public.pem 파일을 찾을 수 없습니다: $SEALED_SECRETS_CERT"
  exit 1
fi

# dev-db 네임스페이스와 elasticsearch-config라는 이름의 Secret 생성 예정
ELASTICSEARCH_IP="$1"
NAMESPACE="dev-db"
SECRET_NAME="elasticsearch-config"

# IP 주소를 base64로 인코딩
ELASTICSEARCH_IP_B64=$(echo -n "$ELASTICSEARCH_IP" | base64)

echo "🔐 Elasticsearch IP Secret을 위한 SealedSecret 생성 중..."
echo "📍 IP 주소: ${ELASTICSEARCH_IP} (base64: ${ELASTICSEARCH_IP_B64})"

# 임시 Secret 생성
cat << EOF > /tmp/elasticsearch-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  namespace: ${NAMESPACE}
type: Opaque
data:
  elasticsearch-ip: ${ELASTICSEARCH_IP_B64}
EOF

# SealedSecret으로 변환
kubeseal --cert "$SEALED_SECRETS_CERT" -f /tmp/elasticsearch-secret.yaml -w ./sealed-configmap.yaml

# 임시 파일 정리
rm /tmp/elasticsearch-secret.yaml

echo "✅ SealedSecret이 생성되었습니다: sealed-configmap.yaml"
echo "💡 Secret을 사용하여 보안이 강화되었습니다."
echo "🚀 이제 Git에 안전하게 커밋하고 ArgoCD가 자동 배포할 수 있습니다."

# 디버깅용 정보 출력
echo ""
echo "📋 생성된 리소스 정보:"
echo "   - Type: Secret (SealedSecret으로 암호화됨)"
echo "   - Name: ${SECRET_NAME}"
echo "   - Namespace: ${NAMESPACE}"
echo "   - IP Field: data.elasticsearch-ip (base64 인코딩됨)"
