#!/bin/bash

# Mongo Chat IP Configuration Generator for SealedSecret
# 사용법: ./generate-mongo-chat-config.sh <mongo-chat-ip>
# 예시: ./generate-mongo-chat-config.sh 129.154.50.74

set -e

if [ -z "$1" ]; then
  echo "❌ 오류: Mongo Chat IP를 인자로 전달해주세요."
  echo "사용법: $0 <mongo-chat-ip>"
  exit 1
fi

# dev-db 네임스페이스와 mongo-chat-config라는 이름의 ConfigMap 생성 예정
MONGO_CHAT_IP="$1"
NAMESPACE="dev-db"
CONFIGMAP_NAME="mongo-chat-config"

echo "🔐 Mongo Chat IP ConfigMap을 위한 SealedSecret 생성 중..."
echo "📍 IP 주소: ${MONGO_CHAT_IP}"

# 임시 ConfigMap 생성
cat << EOF > /tmp/mongo-chat-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${CONFIGMAP_NAME}
  namespace: ${NAMESPACE}
data:
  mongo-chat-ip: "${MONGO_CHAT_IP}"
EOF

# SealedSecret으로 변환
kubeseal -f /tmp/mongo-chat-configmap.yaml -w ./sealed-configmap.yaml

# 임시 파일 정리
rm /tmp/mongo-chat-configmap.yaml

echo "✅ SealedSecret이 생성되었습니다: sealed-configmap.yaml"
echo "💡 ConfigMap 방식으로 Base64 인코딩 이슈가 해결되었습니다."
echo "🚀 이제 Git에 안전하게 커밋하고 ArgoCD가 자동 배포할 수 있습니다."

# 디버깅용 정보 출력
echo ""
echo "📋 생성된 리소스 정보:"
echo "   - Type: ConfigMap (SealedSecret으로 암호화됨)"
echo "   - Name: ${CONFIGMAP_NAME}"
echo "   - Namespace: ${NAMESPACE}"
echo "   - IP Field: data.mongo-chat-ip" 