#!/bin/bash

# PlayUs 배포 검증 스크립트
set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 로그 함수들
log_header() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================================${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_info() {
    echo -e "${BLUE}💡 $1${NC}"
}

# 검증 함수
check_namespace() {
    local namespace=$1
    if kubectl get namespace "$namespace" > /dev/null 2>&1; then
        log_success "네임스페이스 '$namespace' 존재 확인"
        return 0
    else
        log_error "네임스페이스 '$namespace' 없음"
        return 1
    fi
}

check_deployment() {
    local namespace=$1
    local deployment=$2
    if kubectl get deployment "$deployment" -n "$namespace" > /dev/null 2>&1; then
        local ready=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.spec.replicas}')
        if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
            log_success "$namespace/$deployment: $ready/$desired 레플리카 준비완료"
            return 0
        else
            log_warning "$namespace/$deployment: $ready/$desired 레플리카 (아직 준비 중)"
            return 1
        fi
    else
        log_error "$namespace/$deployment 배포 없음"
        return 1
    fi
}

check_service() {
    local namespace=$1
    local service=$2
    if kubectl get service "$service" -n "$namespace" > /dev/null 2>&1; then
        log_success "서비스 '$namespace/$service' 존재 확인"
        return 0
    else
        log_error "서비스 '$namespace/$service' 없음"
        return 1
    fi
}

check_argocd_app() {
    local app_name=$1
    if kubectl get application "$app_name" -n argocd > /dev/null 2>&1; then
        local sync_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.sync.status}')
        local health_status=$(kubectl get application "$app_name" -n argocd -o jsonpath='{.status.health.status}')
        
        if [ "$sync_status" = "Synced" ] && [ "$health_status" = "Healthy" ]; then
            log_success "ArgoCD 앱 '$app_name': $sync_status, $health_status"
            return 0
        else
            log_warning "ArgoCD 앱 '$app_name': $sync_status, $health_status"
            return 1
        fi
    else
        log_error "ArgoCD 앱 '$app_name' 없음"
        return 1
    fi
}

log_header "🔍 PlayUs 배포 상태 검증 시작"

# 클러스터 연결 확인
log_info "Kubernetes 클러스터 연결 확인..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    log_error "클러스터에 연결할 수 없습니다"
    exit 1
fi
log_success "클러스터 연결 확인 완료"

echo ""
log_header "📁 네임스페이스 확인"

# 필수 네임스페이스들 확인
NAMESPACES=(
    "argocd"
    "kube-system" 
    "dev-db"
    "dev-gateway"
    "dev-user-service"
    "dev-community-service"
    "dev-match-service"
    "dev-search-service"
    "dev-twp-service"
    "dev-monitoring"
    "kong"
)

for ns in "${NAMESPACES[@]}"; do
    check_namespace "$ns"
done

echo ""
log_header "🔐 Sealed Secrets 확인"
check_deployment "kube-system" "sealed-secrets-controller"

echo ""
log_header "🔧 ArgoCD 확인"
check_deployment "argocd" "argocd-server"
check_deployment "argocd" "argocd-application-controller"
check_deployment "argocd" "argocd-dex-server"
check_deployment "argocd" "argocd-redis"
check_deployment "argocd" "argocd-repo-server"

# ArgoCD 애플리케이션들 확인
echo ""
log_header "📱 ArgoCD 애플리케이션 상태 확인"
ARGOCD_APPS=(
    "dev-namespaces"
    "dev-mysql"
    "dev-mongo-chat"
    "dev-mongo-read"
    "dev-elasticsearch"
    "dev-gateway"
    "dev-user-service"
    "dev-community-service"
    "dev-match-service"
    "dev-search-service"
    "dev-twp-service"
    "dev-monitoring"
)

for app in "${ARGOCD_APPS[@]}"; do
    check_argocd_app "$app" || true
done

echo ""
log_header "🌐 Kong 확인"
if check_namespace "dev-gateway" || check_namespace "kong"; then
    # Kong 네임스페이스 결정
    if kubectl get namespace "dev-gateway" > /dev/null 2>&1; then
        KONG_NS="dev-gateway"
    else
        KONG_NS="kong"
    fi
    
    # Kong 서비스 확인
    if kubectl get deployment -n "$KONG_NS" | grep -q kong; then
        kubectl get deployment -n "$KONG_NS" | grep kong | while read deployment rest; do
            check_deployment "$KONG_NS" "$deployment"
        done
    fi
    
    # Kong 외부 IP 확인
    if kubectl get svc -n "$KONG_NS" ingress-kong-kong-proxy > /dev/null 2>&1; then
        EXTERNAL_IP=$(kubectl get svc -n "$KONG_NS" ingress-kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [ -n "$EXTERNAL_IP" ] && [ "$EXTERNAL_IP" != "null" ]; then
            log_success "Kong 외부 IP: $EXTERNAL_IP"
        else
            log_warning "Kong 외부 IP 할당 대기 중"
        fi
    fi
fi

echo ""
log_header "🗄️ 데이터베이스 연결 확인"

# 데이터베이스 서비스들 확인
DB_SERVICES=(
    "dev-mysql"
    "dev-mongo-chat"
    "dev-mongo-read"
    "dev-elasticsearch"
)

for service in "${DB_SERVICES[@]}"; do
    if check_service "dev-db" "$service"; then
        # Endpoints 확인
        if kubectl get endpoints "$service" -n dev-db > /dev/null 2>&1; then
            endpoint_ip=$(kubectl get endpoints "$service" -n dev-db -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null)
            if [ -n "$endpoint_ip" ] && [ "$endpoint_ip" != "null" ]; then
                log_success "$service 엔드포인트: $endpoint_ip"
            else
                log_warning "$service 엔드포인트 IP 없음"
            fi
        fi
    fi
done

# ConfigMap 확인
echo ""
log_info "📝 ConfigMap 확인:"
kubectl get configmap -n dev-db 2>/dev/null | grep -E "(mongo|mysql|elasticsearch)" | while read name rest; do
    log_success "ConfigMap: $name"
done

echo ""
log_header "📊 전체 Pod 상태 요약"

# 모든 Pod 상태 확인
echo ""
log_info "🔍 전체 클러스터 Pod 상태:"
kubectl get pods --all-namespaces | grep -E "(Running|Pending|Error|CrashLoopBackOff)" | \
awk '{
    if ($4 == "Running") 
        printf "\033[0;32m✅ %-20s %-30s %s\033[0m\n", $1, $2, $4
    else if ($4 == "Pending") 
        printf "\033[1;33m⏳ %-20s %-30s %s\033[0m\n", $1, $2, $4
    else 
        printf "\033[0;31m❌ %-20s %-30s %s\033[0m\n", $1, $2, $4
}'

echo ""
log_header "✅ 검증 완료"

# 요약 통계
TOTAL_PODS=$(kubectl get pods --all-namespaces --no-headers | wc -l)
RUNNING_PODS=$(kubectl get pods --all-namespaces --no-headers | grep Running | wc -l)
PENDING_PODS=$(kubectl get pods --all-namespaces --no-headers | grep Pending | wc -l)
ERROR_PODS=$(kubectl get pods --all-namespaces --no-headers | grep -E "(Error|CrashLoopBackOff|Failed)" | wc -l)

log_info "📈 Pod 통계:"
log_success "  실행 중: $RUNNING_PODS/$TOTAL_PODS"
if [ "$PENDING_PODS" -gt 0 ]; then
    log_warning "  대기 중: $PENDING_PODS"
fi
if [ "$ERROR_PODS" -gt 0 ]; then
    log_error "  오류: $ERROR_PODS"
fi

echo ""
if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$ERROR_PODS" -eq 0 ]; then
    log_success "🎉 모든 서비스가 정상적으로 실행 중입니다!"
elif [ "$ERROR_PODS" -eq 0 ] && [ "$PENDING_PODS" -gt 0 ]; then
    log_warning "⏳ 일부 서비스가 아직 시작 중입니다. 잠시 후 다시 확인해주세요."
else
    log_error "🔧 일부 서비스에 문제가 있습니다. 로그를 확인해주세요."
    echo ""
    log_info "💡 문제 해결 명령어:"
    echo -e "${PURPLE}  kubectl get pods --all-namespaces | grep -v Running${NC}"
    echo -e "${PURPLE}  kubectl describe pod <pod-name> -n <namespace>${NC}"
    echo -e "${PURPLE}  kubectl logs <pod-name> -n <namespace>${NC}"
fi 