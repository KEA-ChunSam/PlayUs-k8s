#!/bin/bash

set -e  # 에러 발생 시 즉시 종료

# 상대 경로 계산을 위한 스크립트 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_DIR="${SCRIPT_DIR}/../manifests"

echo "🚀 [1] Argo CD 네임스페이스 생성"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "📦 [2] Argo CD 설치 중"
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "⏳ [3] Argo CD 서버 대기 중"
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "🌐 [4] Ingress 설정 적용 (/argocd 경로)"
kubectl apply -f "${MANIFEST_DIR}/dev-argocd-ingress.yaml"

echo "🔧 [5] HTTPS 제거 + 서브경로(/argocd) 접속 설정"
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type merge -p '{"data":{
    "server.insecure":"true",
    "server.enable.ssl":"false",
    "server.basehref":"/argocd"
  }}'

echo "🔁 [6] Argo CD 서버 재시작"
kubectl rollout restart deployment argocd-server -n argocd
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo ""
echo "✅ Argo CD 설치 및 Ingress 설정 완료"
echo "초기 로그인 정보:"
echo "사용자명: admin"
echo "비밀번호: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"

echo ""
echo "🌍 외부 접속 주소:"
echo "➡️  http://<EXTERNAL-IP>/argocd"
echo "ℹ️  EXTERNAL-IP 확인 명령어:"
echo "    kubectl get svc -n dev-gateway ingress-kong-kong-proxy"
