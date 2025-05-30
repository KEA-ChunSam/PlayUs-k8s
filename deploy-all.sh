#!/bin/bash

# PlayUs 완전 자동화 배포 스크립트
# 사용법: ./deploy-all.sh [database-ip] [environment]
# 예시: ./deploy-all.sh 129.154.50.74 develop

set -e  # 에러 발생 시 즉시 종료

# === 색상 정의 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# === 로그 함수들 ===
log_header() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================================${NC}"
}

log_step() {
    echo -e "${BLUE}🔹 $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_info() {
    echo -e "${PURPLE}💡 $1${NC}"
}

# === 설정 ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}"

# 기본값 설정
DB_IP="${1:-129.154.50.74}"
ENVIRONMENT="${2:-develop}"

# 배포 옵션 (환경변수로 제어 가능)
DEPLOY_SEALED_SECRETS="${DEPLOY_SEALED_SECRETS:-true}"
DEPLOY_ARGOCD="${DEPLOY_ARGOCD:-true}"
DEPLOY_KONG="${DEPLOY_KONG:-true}"
DEPLOY_DATABASES="${DEPLOY_DATABASES:-true}"
DEPLOY_SERVICES="${DEPLOY_SERVICES:-true}"
DEPLOY_INGRESS="${DEPLOY_INGRESS:-true}"

log_header "🚀 PlayUs 완전 자동화 배포 시작"
log_info "데이터베이스 IP: ${DB_IP}"
log_info "환경: ${ENVIRONMENT}"
log_info "프로젝트 루트: ${PROJECT_ROOT}"

# === 사전 확인 ===
log_header "📋 사전 준비 확인"

# 현재 디렉토리가 프로젝트 루트인지 확인
if [ ! -f "argocd/dev-namespaces.yaml" ]; then
    log_error "PlayUs-k8s 프로젝트 루트에서 실행해주세요."
    exit 1
fi

# 필수 도구들 확인
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1이 설치되어 있지 않습니다."
        case "$1" in
            kubectl)
                log_info "설치 방법: https://kubernetes.io/docs/tasks/tools/"
                ;;
            helm)
                log_info "설치 방법: https://helm.sh/docs/intro/install/"
                ;;
            kubeseal)
                log_info "설치 방법: https://github.com/bitnami-labs/sealed-secrets#installation"
                ;;
        esac
        exit 1
    fi
    log_success "$1 ✓"
}

check_tool "kubectl"
check_tool "helm"

# 클러스터 연결 확인
log_step "Kubernetes 클러스터 연결 확인"
if ! kubectl cluster-info > /dev/null 2>&1; then
    log_error "Kubernetes 클러스터에 연결할 수 없습니다."
    exit 1
fi
log_success "클러스터 연결 확인 완료"

# === 1. Sealed Secrets 설정 ===
if [ "$DEPLOY_SEALED_SECRETS" = "true" ]; then
    log_header "🔐 Sealed Secrets Controller 설정"
    
    # Sealed Secrets Controller가 이미 설치되어 있는지 확인
    if kubectl get deployment sealed-secrets-controller -n kube-system > /dev/null 2>&1; then
        log_success "Sealed Secrets Controller가 이미 설치되어 있습니다."
    else
        log_step "Sealed Secrets Controller 설치 중..."
        if [ -f "scripts/setup-sealed-secret.sh" ]; then
            chmod +x scripts/setup-sealed-secret.sh
            ./scripts/setup-sealed-secret.sh
        else
            # 기본 설치 방법
            kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
            kubectl wait --namespace kube-system --for=condition=available deployment/sealed-secrets-controller --timeout=300s
        fi
        log_success "Sealed Secrets Controller 설치 완료"
    fi
    
    # kubeseal 도구 확인
    if ! command -v kubeseal &> /dev/null; then
        log_warning "kubeseal CLI가 설치되어 있지 않습니다. 수동 설치가 필요할 수 있습니다."
    else
        log_success "kubeseal CLI 확인 완료"
    fi
fi

# === 2. ArgoCD 설정 ===
if [ "$DEPLOY_ARGOCD" = "true" ]; then
    log_header "🔧 ArgoCD 설정"
    
    # ArgoCD가 이미 설치되어 있는지 확인
    if kubectl get namespace argocd > /dev/null 2>&1 && kubectl get deployment argocd-server -n argocd > /dev/null 2>&1; then
        log_success "ArgoCD가 이미 설치되어 있습니다."
    else
        log_step "ArgoCD 설치 중..."
        if [ -f "scripts/setup-argocd.sh" ]; then
            chmod +x scripts/setup-argocd.sh
            ./scripts/setup-argocd.sh
        else
            # 기본 설치 방법
            kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
            kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
            kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
        fi
        log_success "ArgoCD 설치 완료"
    fi
    
    # ArgoCD 초기 비밀번호 출력
    if kubectl get secret argocd-initial-admin-secret -n argocd > /dev/null 2>&1; then
        ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
        log_info "ArgoCD 로그인 정보 - 사용자: admin, 비밀번호: ${ARGOCD_PASSWORD}"
    fi
fi

# === 3. Kong Ingress Controller 설정 ===
if [ "$DEPLOY_KONG" = "true" ]; then
    log_header "🌐 Kong Ingress Controller 설정"
    
    # Kong이 이미 설치되어 있는지 확인
    if kubectl get namespace "${ENVIRONMENT}-gateway" > /dev/null 2>&1 && helm list -n "${ENVIRONMENT}-gateway" | grep -q ingress-kong; then
        log_success "Kong이 이미 설치되어 있습니다."
    else
        log_step "Kong Ingress Controller 설치 중..."
        
        # Helm 레포지토리 추가
        helm repo add kong https://charts.konghq.com > /dev/null 2>&1 || true
        helm repo update > /dev/null 2>&1
        
        if [ -f "scripts/deploy-kong.sh" ]; then
            chmod +x scripts/deploy-kong.sh
            ./scripts/deploy-kong.sh "$ENVIRONMENT"
        else
            # 기본 설치 방법
            kubectl create namespace "${ENVIRONMENT}-gateway" --dry-run=client -o yaml | kubectl apply -f -
            helm upgrade --install ingress-kong kong/kong \
                --namespace "${ENVIRONMENT}-gateway" \
                --set ingressController.enabled=true \
                --set ingressController.watchNamespace="" \
                --set env.database=postgres \
                --set postgresql.enabled=true \
                --set postgresql.auth.username=kong \
                --set postgresql.auth.password=kong \
                --set postgresql.auth.database=kong \
                --set env.pg_user=kong \
                --set env.pg_password=kong \
                --set env.pg_database=kong \
                --set proxy.type=LoadBalancer
        fi
        log_success "Kong Ingress Controller 설치 완료"
    fi
fi

# === 4. 네임스페이스 생성 ===
log_header "📁 네임스페이스 생성"
log_step "필요한 네임스페이스들 생성 중..."
kubectl apply -f argocd/dev-namespaces.yaml
log_success "네임스페이스 생성 완료"

# === 5. 데이터베이스 IP 설정 (SealedSecret 생성) ===
if [ "$DEPLOY_DATABASES" = "true" ]; then
    log_header "🗄️ 데이터베이스 IP SealedSecret 생성"
    
    # kubeseal이 없으면 경고하고 건너뛰기
    if ! command -v kubeseal &> /dev/null; then
        log_warning "kubeseal이 설치되어 있지 않습니다. 데이터베이스 IP 설정을 건너뜁니다."
        log_info "수동으로 각 데이터베이스 폴더에서 generate 스크립트를 실행해주세요."
    else
        # Mongo Chat IP 설정
        if [ -f "shared/database/mongo-chat/generate-mongo-chat-config.sh" ]; then
            log_step "Mongo Chat IP 설정..."
            cd shared/database/mongo-chat
            chmod +x generate-mongo-chat-config.sh
            ./generate-mongo-chat-config.sh "$DB_IP"
            cd ../../..
            log_success "Mongo Chat IP 설정 완료"
        fi
        
        # Mongo Read IP 설정  
        if [ -f "shared/database/mongo-read/generate-mongo-read-config.sh" ]; then
            log_step "Mongo Read IP 설정..."
            cd shared/database/mongo-read
            chmod +x generate-mongo-read-config.sh
            ./generate-mongo-read-config.sh "$DB_IP"
            cd ../../..
            log_success "Mongo Read IP 설정 완료"
        fi
        
        # MySQL IP 설정
        if [ -f "shared/database/mysql/generate-mysql-config.sh" ]; then
            log_step "MySQL IP 설정..."
            cd shared/database/mysql
            chmod +x generate-mysql-config.sh
            ./generate-mysql-config.sh "$DB_IP"
            cd ../../..
            log_success "MySQL IP 설정 완료"
        fi
        
        # Elasticsearch IP 설정 (스크립트가 있는 경우에만)
        if [ -f "shared/database/elasticsearch/generate-elasticsearch-config.sh" ]; then
            log_step "Elasticsearch IP 설정..."
            cd shared/database/elasticsearch
            chmod +x generate-elasticsearch-config.sh
            ./generate-elasticsearch-config.sh "$DB_IP"
            cd ../../..
            log_success "Elasticsearch IP 설정 완료"
        fi
        
        # 생성된 SealedSecret 파일 목록 출력
        log_info "생성된 SealedSecret 파일들:"
        find shared/database -name "sealed-configmap.yaml" -type f | while read file; do
            log_info "  📝 $file"
        done
    fi
fi

# === 6. ArgoCD 애플리케이션 배포 ===
if [ "$DEPLOY_SERVICES" = "true" ]; then
    log_header "🚀 ArgoCD 애플리케이션 배포"
    
    # 데이터베이스 ApplicationSet 배포
    if [ "$DEPLOY_DATABASES" = "true" ] && [ -f "argocd/dev-database.yaml" ]; then
        log_step "데이터베이스 ApplicationSet 배포..."
        kubectl apply -f argocd/dev-database.yaml
        log_success "데이터베이스 ApplicationSet 배포 완료"
        
        # 잠시 대기 (데이터베이스가 먼저 배포되도록)
        log_step "데이터베이스 배포 대기 중 (10초)..."
        sleep 10
    fi
    
    # 메인 서비스 ApplicationSet 배포
    if [ -f "argocd/dev-applicationset.yaml" ]; then
        log_step "메인 서비스 ApplicationSet 배포..."
        kubectl apply -f argocd/dev-applicationset.yaml
        log_success "메인 서비스 ApplicationSet 배포 완료"
    fi
fi

# === 7. Ingress 설정 배포 ===
if [ "$DEPLOY_INGRESS" = "true" ]; then
    log_header "🌐 Ingress 설정 배포"
    
    # ArgoCD Ingress 배포
    if [ -f "argocd/dev-ingress.yaml" ]; then
        log_step "ArgoCD Ingress 설정 배포..."
        kubectl apply -f argocd/dev-ingress.yaml
        log_success "ArgoCD Ingress 설정 배포 완료"
    fi
    
    # Kong Ingress 배포 (스크립트가 있는 경우)
    if [ -f "scripts/deploy-develop-ingress.sh" ]; then
        log_step "Kong Ingress 규칙 배포..."
        chmod +x scripts/deploy-develop-ingress.sh
        ./scripts/deploy-develop-ingress.sh
        log_success "Kong Ingress 규칙 배포 완료"
    fi
fi

# === 8. 배포 상태 확인 ===
log_header "📊 배포 상태 확인"

# 잠시 대기 후 상태 확인
log_step "배포 상태 확인 중 (5초 대기)..."
sleep 5

# ArgoCD 애플리케이션 상태 확인
if kubectl get applications -n argocd > /dev/null 2>&1; then
    log_step "ArgoCD 애플리케이션 상태:"
    kubectl get applications -n argocd --no-headers | awk '{printf "    🔹 %-30s: %s\n", $1, $3}' || true
fi

# Kong 외부 IP 확인
KONG_NAMESPACE="${ENVIRONMENT}-gateway"
if kubectl get svc -n "$KONG_NAMESPACE" > /dev/null 2>&1; then
    KONG_EXTERNAL_IP=$(kubectl get svc -n "$KONG_NAMESPACE" ingress-kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "대기중")
    log_info "Kong 프록시 외부 IP: ${KONG_EXTERNAL_IP}"
fi

# === 9. 완료 및 다음 단계 안내 ===
log_header "✅ 배포 완료!"

log_success "PlayUs 배포가 성공적으로 시작되었습니다!"
echo ""
log_info "📋 다음 단계:"

if [ "$DEPLOY_DATABASES" = "true" ] && command -v kubeseal &> /dev/null; then
    echo -e "${PURPLE}  1. Git에 변경사항 커밋:${NC}"
    echo -e "${PURPLE}     git add .${NC}"
    echo -e "${PURPLE}     git commit -m 'feat: 데이터베이스 IP SealedSecret 설정'${NC}"
    echo -e "${PURPLE}     git push${NC}"
    echo ""
fi

if [ "$DEPLOY_ARGOCD" = "true" ]; then
    echo -e "${PURPLE}  2. ArgoCD UI 접근:${NC}"
    if [ -n "$KONG_EXTERNAL_IP" ] && [ "$KONG_EXTERNAL_IP" != "대기중" ]; then
        echo -e "${PURPLE}     http://${KONG_EXTERNAL_IP}/argocd${NC}"
    else
        echo -e "${PURPLE}     kubectl port-forward svc/argocd-server -n argocd 8080:443${NC}"
        echo -e "${PURPLE}     https://localhost:8080${NC}"
    fi
    echo ""
fi

echo -e "${PURPLE}  3. 서비스 상태 모니터링:${NC}"
echo -e "${PURPLE}     watch kubectl get pods --all-namespaces${NC}"
echo ""

echo -e "${PURPLE}  4. 전체 상태 확인:${NC}"
echo -e "${PURPLE}     kubectl get all --all-namespaces${NC}"
echo ""

if [ -n "$KONG_EXTERNAL_IP" ] && [ "$KONG_EXTERNAL_IP" != "대기중" ]; then
    log_info "🌍 API 엔드포인트 테스트:"
    echo -e "${PURPLE}     curl -i http://${KONG_EXTERNAL_IP}/api/users/health${NC}"
    echo -e "${PURPLE}     curl -i http://${KONG_EXTERNAL_IP}/api/community/health${NC}"
fi

log_header "🎉 PlayUs 클러스터가 준비되었습니다!" 
