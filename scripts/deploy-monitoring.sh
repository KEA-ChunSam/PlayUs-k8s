#!/bin/bash

# =================================================
# PlayUs 모니터링 스택 Helm 배포
# Target: dev-monitoring namespace
# =================================================

set -e

# 색상
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# 설정
NAMESPACE="dev-monitoring"
RELEASE_NAME="playus-monitoring"
CHART_PATH="./monitoring"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}🚀 PlayUs 모니터링 스택 Helm 배포${NC}"
echo -e "${YELLOW}Namespace: ${NAMESPACE}${NC}"
echo -e "${YELLOW}Release: ${RELEASE_NAME}${NC}"
echo ""

# =================================================
# 1. 사전 확인
# =================================================

echo -e "${YELLOW}📋 1. 사전 확인${NC}"

# Helm 확인
if ! command -v helm &> /dev/null; then
    echo -e "${RED}❌ Helm이 설치되지 않았습니다${NC}"
    exit 1
fi

# kubectl 확인
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl이 설치되지 않았습니다${NC}"
    exit 1
fi

# Chart 디렉토리 확인
if [ ! -f "${PROJECT_ROOT}/monitoring/Chart.yaml" ]; then
    echo -e "${RED}❌ Chart.yaml을 찾을 수 없습니다: ${PROJECT_ROOT}/monitoring/Chart.yaml${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 사전 확인 완료${NC}"

# =================================================
# 2. Helm Repository 추가
# =================================================

echo -e "${YELLOW}📦 2. Helm Repository 추가${NC}"

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

echo -e "${GREEN}✅ Repository 추가 완료${NC}"

# =================================================
# 3. 네임스페이스 생성
# =================================================

echo -e "${YELLOW}📁 3. 네임스페이스 생성${NC}"

# dev-monitoring namespace 생성
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✅ Namespace '${NAMESPACE}' 준비 완료${NC}"

# =================================================
# 4. Chart 의존성 업데이트
# =================================================

echo -e "${YELLOW}🔄 4. Chart 의존성 업데이트${NC}"

cd "${PROJECT_ROOT}/monitoring"
helm dependency update

echo -e "${GREEN}✅ 의존성 업데이트 완료${NC}"

# =================================================
# 5. 기존 릴리즈 확인 및 정리
# =================================================

echo -e "${YELLOW}🧹 5. 기존 릴리즈 확인${NC}"

if helm list -n ${NAMESPACE} | grep -q ${RELEASE_NAME}; then
    echo -e "${YELLOW}기존 릴리즈 발견: ${RELEASE_NAME}${NC}"
    read -p "기존 릴리즈를 업그레이드하시겠습니까? (Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${RED}배포 중단${NC}"
        exit 0
    fi
    HELM_COMMAND="upgrade"
else
    HELM_COMMAND="install"
fi

# =================================================
# 6. Helm 배포
# =================================================

echo -e "${YELLOW}🚀 6. Helm 차트 배포${NC}"

if [ "$HELM_COMMAND" = "upgrade" ]; then
    echo -e "${CYAN}업그레이드 중...${NC}"
    helm upgrade ${RELEASE_NAME} . \
        --namespace ${NAMESPACE} \
        --values values.yaml \
        --wait \
        --timeout 600s
else
    echo -e "${CYAN}새로 설치 중...${NC}"
    helm install ${RELEASE_NAME} . \
        --namespace ${NAMESPACE} \
        --values values.yaml \
        --wait \
        --timeout 600s
fi

echo -e "${GREEN}✅ Helm 배포 완료${NC}"

# =================================================
# 7. 배포 상태 확인
# =================================================

echo -e "${YELLOW}📊 7. 배포 상태 확인${NC}"

echo -e "${CYAN}📋 Helm Release 상태:${NC}"
helm list -n ${NAMESPACE}

echo ""
echo -e "${CYAN}📋 Pod 상태:${NC}"
kubectl get pods -n ${NAMESPACE} -o wide

echo ""
echo -e "${CYAN}📋 Service 상태:${NC}"
kubectl get svc -n ${NAMESPACE}

echo ""
echo -e "${CYAN}📋 PVC 상태:${NC}"
kubectl get pvc -n ${NAMESPACE}

# =================================================
# 8. 헬스 체크
# =================================================

echo -e "${YELLOW}🩺 8. 헬스 체크${NC}"

# Pod 준비 대기
echo -e "${CYAN}Pod 준비 대기...${NC}"
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=${RELEASE_NAME} -n ${NAMESPACE} --timeout=300s

# 개별 서비스 헬스 체크
echo -e "${CYAN}Loki 헬스 체크...${NC}"
if kubectl exec -n ${NAMESPACE} deployment/${RELEASE_NAME}-loki -- wget -q --spider http://localhost:3100/ready 2>/dev/null; then
    echo -e "${GREEN}✅ Loki 정상${NC}"
else
    echo -e "${YELLOW}⚠️ Loki 헬스 체크 건너뜀${NC}"
fi

echo -e "${CYAN}Alloy 헬스 체크...${NC}"
if kubectl exec -n ${NAMESPACE} deployment/${RELEASE_NAME}-alloy -- wget -q --spider http://localhost:12345/-/healthy 2>/dev/null; then
    echo -e "${GREEN}✅ Alloy 정상${NC}"
else
    echo -e "${YELLOW}⚠️ Alloy 헬스 체크 건너뜀${NC}"
fi

echo -e "${CYAN}Grafana 헬스 체크...${NC}"
if kubectl exec -n ${NAMESPACE} deployment/${RELEASE_NAME}-grafana -- wget -q --spider http://localhost:3000/api/health 2>/dev/null; then
    echo -e "${GREEN}✅ Grafana 정상${NC}"
else
    echo -e "${YELLOW}⚠️ Grafana 헬스 체크 건너뜀${NC}"
fi

# =================================================
# 9. 접속 정보
# =================================================

echo ""
echo -e "${GREEN}🎉 PlayUs 모니터링 스택 배포 완료!${NC}"
echo ""
echo -e "${BLUE}📊 접속 정보:${NC}"
echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}│                   PlayUs Monitoring                        │${NC}"
echo -e "${YELLOW}├─────────────────────────────────────────────────────────────┤${NC}"
echo -e "${YELLOW}│ Grafana:                                                   │${NC}"
echo -e "${YELLOW}│   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-grafana 3000:3000    │${NC}"
echo -e "${YELLOW}│   http://localhost:3000                                    │${NC}"
echo -e "${YELLOW}│   admin / playus-dev-2024!                                │${NC}"
echo -e "${YELLOW}│                                                           │${NC}"
echo -e "${YELLOW}│ Alloy:                                                    │${NC}"
echo -e "${YELLOW}│   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-alloy 12345:12345    │${NC}"
echo -e "${YELLOW}│   http://localhost:12345                                  │${NC}"
echo -e "${YELLOW}│                                                           │${NC}"
echo -e "${YELLOW}│ Loki:                                                     │${NC}"
echo -e "${YELLOW}│   kubectl port-forward -n ${NAMESPACE} svc/${RELEASE_NAME}-loki 3100:3100      │${NC}"
echo -e "${YELLOW}│   http://localhost:3100                                   │${NC}"
echo -e "${YELLOW}└─────────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${BLUE}📝 다음 단계:${NC}"
echo -e "${YELLOW}1. Grafana에서 대시보드 확인${NC}"
echo -e "${YELLOW}2. Alloy에서 타겟 수집 상태 확인${NC}"
echo -e "${YELLOW}3. 온프레미스 DB 연결 추가${NC}"

cd - > /dev/null
