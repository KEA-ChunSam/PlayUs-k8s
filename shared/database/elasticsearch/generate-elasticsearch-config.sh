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

# dev-db 네임스페이스와 elasticsearch-config라는 이름의 ConfigMap 생성 예정
ELASTICSEARCH_IP="$1"
NAMESPACE="dev-db"
CONFIGMAP_NAME="elasticsearch-config"

echo "🔐 Elasticsearch IP ConfigMap을 위한 SealedSecret 생성 중..."
echo "📍 IP 주소: ${ELASTICSEARCH_IP}"

# 임시 ConfigMap 생성
cat << EOF > /tmp/elasticsearch-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CONFIGMAP_NAME}
  namespace: ${NAMESPACE}
data:
  elasticsearch-ip: "${ELASTICSEARCH_IP}"
EOF

# SealedSecret으로 변환
kubeseal --cert "$SEALED_SECRETS_CERT" -f /tmp/elasticsearch-configmap.yaml -w ./sealed-configmap.yaml

# 임시 파일 정리
rm /tmp/elasticsearch-configmap.yaml

echo "✅ SealedSecret이 생성되었습니다: sealed-configmap.yaml"
echo "💡 ConfigMap 방식으로 Base64 인코딩 이슈가 해결되었습니다."
echo "🚀 이제 Git에 안전하게 커밋하고 ArgoCD가 자동 배포할 수 있습니다."

# 디버깅용 정보 출력
echo ""
echo "📋 생성된 리소스 정보:"
echo "   - Type: ConfigMap (SealedSecret으로 암호화됨)"
echo "   - Name: ${CONFIGMAP_NAME}"
echo "   - Namespace: ${NAMESPACE}"
echo "   - IP Field: data.elasticsearch-ip"
