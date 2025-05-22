#!/bin/bash

set -e  # 에러 발생 시 즉시 종료

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 상대 경로 계산을 위한 스크립트 디렉토리 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SCRIPT_DIR}/.."

# 로그 함수들
log_header() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================================================${NC}"
}

log_step() {
    echo -e "${BLUE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

log_info() {
    echo -e "${PURPLE}$1${NC}"
}

# 배포 옵션 설정
DEPLOY_KONG=${DEPLOY_KONG:-true}
DEPLOY_SEALED_SECRETS=${DEPLOY_SEALED_SECRETS:-true}
DEPLOY_ARGOCD=${DEPLOY_ARGOCD:-true}
DEPLOY_SERVICES=${DEPLOY_SERVICES:-true}
DEPLOY_DATABASES=${DEPLOY_DATABASES:-true}
DEPLOY_MONITORING=${DEPLOY_MONITORING:-true}

ENVIRONMENT=${ENVIRONMENT:-develop}

# 타임아웃 설정
WAIT_TIMEOUT=${WAIT_TIMEOUT:-300}

# 환경 검증 함수
validate_environment() {
    case $ENVIRONMENT in
        "develop"|"staging"|"production")
            log_success "✅ 유효한 환경: $ENVIRONMENT"
            ;;
        *)
            log_error "❌ 지원하지 않는 환경: $ENVIRONMENT"
            log_info "지원 환경: develop, staging, production"
            exit 1
            ;;
    esac
}

# 필수 스크립트 검증 함수
check_required_scripts() {
    log_step "📋 필수 배포 스크립트 검증 중"

    local missing_scripts=()

    # Kong 배포가 활성화된 경우 스크립트 확인
    if [ "$DEPLOY_KONG" == "true" ]; then
        if [ ! -f "$SCRIPT_DIR/deploy-kong.sh" ]; then
            missing_scripts+=("deploy-kong.sh")
        fi
        # Kong 인그레스 설정 스크립트 확인
        if [ ! -f "$SCRIPT_DIR/deploy-$ENVIRONMENT-ingress.sh" ]; then
            missing_scripts+=("deploy-$ENVIRONMENT-ingress.sh")
        fi
    fi

    # Sealed Secrets 배포가 활성화된 경우 스크립트 확인
    if [ "$DEPLOY_SEALED_SECRETS" == "true" ]; then
        if [ ! -f "$SCRIPT_DIR/setup-sealed-secret.sh" ]; then
            missing_scripts+=("setup-sealed-secret.sh")
        fi
    fi

    # ArgoCD 배포가 활성화된 경우 스크립트 확인
    if [ "$DEPLOY_ARGOCD" == "true" ]; then
        if [ ! -f "$SCRIPT_DIR/setup-argocd.sh" ]; then
            missing_scripts+=("setup-argocd.sh")
        fi
    fi

    # 누락된 스크립트가 있으면 배포 중단
    if [ ${#missing_scripts[@]} -gt 0 ]; then
        log_error "❌ 필수 배포 스크립트가 누락되었습니다:"
        for script in "${missing_scripts[@]}"; do
            log_error "   - $script"
        done
        echo ""
        log_error "배포를 계속하려면 다음 중 하나를 선택하세요:"
        log_info "1. 누락된 스크립트들을 생성하고 다시 실행"
        log_info "2. 해당 컴포넌트 배포를 비활성화 (환경변수 설정)"
        log_info "   예: DEPLOY_KONG=false DEPLOY_SEALED_SECRETS=false ./deploy.sh"
        echo ""
        exit 1
    fi

    log_success "✅ 필수 스크립트 검증 완료"
}

# 사전 검증 함수
check_prerequisites() {
    log_header "🔍 사전 환경 검증"

    # 환경 검증
    validate_environment

    # kubectl 설치 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "❌ kubectl이 설치되지 않았습니다."
        exit 1
    fi
    log_success "✅ kubectl 확인 완료"

    # helm 설치 확인 (Kong 배포용)
    if [ "$DEPLOY_KONG" == "true" ] && ! command -v helm &> /dev/null; then
        log_error "❌ Kong 배포를 위해 helm이 필요하지만 설치되지 않았습니다."
        log_info "helm을 설치하거나 DEPLOY_KONG=false 로 설정하세요."
        exit 1
    fi

    if command -v helm &> /dev/null; then
        log_success "✅ helm 확인 완료"
    fi

    # 클러스터 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "❌ Kubernetes 클러스터에 연결할 수 없습니다."
        exit 1
    fi
    log_success "✅ 클러스터 연결 확인 완료"

    # 필수 디렉토리 확인
    local required_dirs=("shared" "base" "overlays/$ENVIRONMENT")
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            log_error "❌ 필수 디렉토리를 찾을 수 없습니다: $dir"
            exit 1
        fi
    done
    log_success "✅ 필수 디렉토리 확인 완료"

    # 필수 스크립트 검증
    check_required_scripts

    log_success "✅ 사전 검증 완료"
    echo ""
}

# 네임스페이스 생성
deploy_namespaces() {
    log_header "🏗️  네임스페이스 배포"

    log_step "📦 네임스페이스 생성 중"
    cd "$PROJECT_ROOT/shared/namespaces"
    kubectl apply -k .

    # 네임스페이스가 생성될 때까지 대기
    log_step "⏳ 네임스페이스 생성 대기 중"
    sleep 10

    log_success "✅ 네임스페이스 배포 완료"
    echo ""
}

# Sealed Secret 설정
setup_sealed_secrets() {
    if [ "$DEPLOY_SEALED_SECRETS" != "true" ]; then
        log_warning "⏭️  Sealed Secrets 설정 건너뜀"
        return
    fi

    log_header "🔐 Sealed Secret Controller 설정"

    # 필수 스크립트 확인 후 실행
    log_step "🔑 Sealed Secret 설치 스크립트 실행 중..."
    bash "$SCRIPT_DIR/setup-sealed-secret.sh"

    log_success "✅ Sealed Secret 설정 완료"
    echo ""
}

# Kong Ingress Controller 배포
deploy_kong() {
    if [ "$DEPLOY_KONG" != "true" ]; then
        log_warning "⏭️  Kong 배포 건너뜀"
        return
    fi

    log_header "🌐 Kong Ingress Controller 배포"

    # 필수 스크립트 확인 후 실행
    log_step "🚀 Kong 배포 스크립트 실행 중"
    bash "$SCRIPT_DIR/deploy-kong.sh" "$ENVIRONMENT"

    # Kong 배포 대기
    log_step "⏳ Kong 배포 대기 중 (sleep 10초)"
    sleep 10

    log_success "✅ Kong Ingress Controller 배포 완료"
    echo ""
}

# Kong Ingress 설정
deploy_kong_ingress() {
    if [ "$DEPLOY_KONG" != "true" ]; then
        log_warning "⏭️  Kong Ingress 설정 건너뜀"
        return
    fi

    log_header "🔗 Kong Ingress 리소스 설정"

    # 환경별 인그레스 배포 스크립트 실행
    log_step "🚀 Kong Ingress 설정 스크립트 실행 중"
    bash "$SCRIPT_DIR/deploy-$ENVIRONMENT-ingress.sh"

    # Ingress 리소스 생성 확인
    log_step "🔍 Ingress 리소스 확인 중"
    sleep 10
    kubectl get ingress --all-namespaces | grep -v "No resources found" || log_warning "Ingress 리소스가 생성되지 않았을 수 있습니다."

    log_success "✅ Kong Ingress 설정 완료"
    echo ""
}

# 의존성 체크 함수
check_dependencies() {
    log_step "🔗 서비스 의존성 확인 중"

    # Kong이 Ready 상태인지 확인
    if [ "$DEPLOY_KONG" == "true" ]; then
        log_step "🌐 Kong 상태 확인 중"
        if ! kubectl get pods -n kong | grep kong; then
            log_error "❌ Kong pods를 찾을 수 없습니다. 배포를 중단합니다."
            exit 1
        fi
    fi

    log_success "✅ 의존성 확인 완료"
}

# 데이터베이스 배포
deploy_databases() {
    if [ "$DEPLOY_DATABASES" != "true" ]; then
        log_warning "⏭️  데이터베이스 배포 건너뜀"
        return
    fi

    log_header "🗄️  데이터베이스 배포"

    # postgres는 prod 환경에서만 배포
    local databases=("mysql" "redis-token" "mongo-chat" "mongo-read" "elasticsearch" "s3")

    if [ "$ENVIRONMENT" = "production" ]; then
            databases+=("postgres-kong")
    fi

    for db in "${databases[@]}"; do
        if [ -d "$PROJECT_ROOT/shared/database/$db" ]; then
            log_step "📊 $db 배포 중..."
            cd "$PROJECT_ROOT/shared/database/$db"
            kubectl apply -k .
            log_success "✅ $db 배포 완료"
        else
            log_error "❌ $db 디렉토리를 찾을 수 없습니다: $PROJECT_ROOT/shared/database/$db"
            log_error "필수 데이터베이스 구성 요소가 누락되었습니다. 배포를 중단합니다."
            exit 1
        fi
    done

    # 데이터베이스 Pod들이 준비될 때까지 대기
    log_step "⏳ 데이터베이스 Pod 준비 대기 중"
    sleep 30

    # 주요 데이터베이스 상태 확인
    log_step "🔍 데이터베이스 상태 확인 중"
    for db in "${databases[@]}"; do
        if ! kubectl get pods -l app=$db --all-namespaces 2>/dev/null | grep Running; then
            log_warning "⚠️ $db pods 상태 확인 필요"
        fi
    done

    log_success "✅ 데이터베이스 배포 완료"
    echo ""
}

# 마이크로서비스 배포
deploy_services() {
    if [ "$DEPLOY_SERVICES" != "true" ]; then
        log_warning "⏭️  서비스 배포 건너뜀"
        return
    fi

    log_header "🚀 마이크로서비스 배포"

    local services=("user-service" "community-service" "match-service" "search-service" "twp-service")

    for service in "${services[@]}"; do
        log_step "🔄 $service 배포 중"

        # Base 리소스 배포
        if [ -d "$PROJECT_ROOT/base/$service" ]; then
            cd "$PROJECT_ROOT/base/$service"
            kubectl apply -k .
            log_success "✅ $service base 리소스 배포 완료"
        else
            log_error "❌ $service base 디렉토리를 찾을 수 없습니다: $PROJECT_ROOT/base/$service"
            exit 1
        fi

        # 환경별 오버레이 적용
        if [ -d "$PROJECT_ROOT/overlays/$ENVIRONMENT/$service" ]; then
            cd "$PROJECT_ROOT/overlays/$ENVIRONMENT/$service"
            kubectl apply -k .
            log_success "✅ $service 환경별 설정 적용 완료"
        else
            log_error "❌ $service 환경별 오버레이를 찾을 수 없습니다: $PROJECT_ROOT/overlays/$ENVIRONMENT/$service"
            exit 1
        fi
    done

    # 서비스 Pod들이 준비될 때까지 대기
    log_step "⏳ 서비스 Pod 준비 대기 중"
    sleep 30

    # 서비스 상태 확인
    log_step "🔍 서비스 상태 확인 중"
    for service in "${services[@]}"; do
        kubectl get pods -l app=$service --all-namespaces 2>/dev/null | head -3
    done

    log_success "✅ 마이크로서비스 배포 완료"
    echo ""
}

# 모니터링 스택 배포
deploy_monitoring() {
    if [ "$DEPLOY_MONITORING" != "true" ]; then
        log_warning "⏭️  모니터링 배포 건너뜀"
        return
    fi

    log_header "📊 모니터링 스택 배포"

    # Base 모니터링 배포
    if [ -d "$PROJECT_ROOT/base/monitoring" ]; then
        log_step "🔍 Base 모니터링 리소스 배포 중"
        cd "$PROJECT_ROOT/base/monitoring"
        kubectl apply -k .
        log_success "✅ Base 모니터링 배포 완료"
    else
        log_error "❌ 모니터링 base 디렉토리를 찾을 수 없습니다: $PROJECT_ROOT/base/monitoring"
        exit 1
    fi

    # Overlay 모니터링 패치 적용
    if [ -d "$PROJECT_ROOT/overlays/$ENVIRONMENT/monitoring" ]; then
        log_step "🔧 환경별 모니터링 설정 적용 중"
        cd "$PROJECT_ROOT/overlays/$ENVIRONMENT/monitoring"
        kubectl apply -k .
        log_success "✅ 환경별 모니터링 설정 적용 완료"
    else
        log_warning "⚠️ 환경별 모니터링 오버레이를 찾을 수 없습니다: $PROJECT_ROOT/overlays/$ENVIRONMENT/monitoring"
        log_info "기본 모니터링 설정만 적용됩니다."
    fi

    # 모니터링 스택 준비 대기
    log_step "⏳ 모니터링 스택 준비 대기 중"
    sleep 20

    log_success "✅ 모니터링 스택 배포 완료"
    echo ""
}

# ArgoCD 설치 및 설정
deploy_argocd() {
    if [ "$DEPLOY_ARGOCD" != "true" ]; then
        log_warning "⏭️  ArgoCD 배포 건너뜀"
        return
    fi

    log_header "🔄 ArgoCD GitOps 배포"

    # 필수 스크립트 확인 후 실행
    log_step "🚀 ArgoCD 설치 스크립트 실행 중"
    bash "$SCRIPT_DIR/setup-argocd.sh"

    log_success "✅ ArgoCD 기본 설치 완료"
    echo ""
}

# ArgoCD Application 배포
deploy_argocd_applications() {
    if [ "$DEPLOY_ARGOCD" != "true" ]; then
        return
    fi

    log_header "📱 ArgoCD Applications 배포"

    # ArgoCD Application 리소스 배포 (Kustomization 활용)
    if [ -d "$PROJECT_ROOT/argocd" ]; then
        log_step "📦 ArgoCD Applications 배포 중 (Kustomization 사용)"
        cd "$PROJECT_ROOT/argocd"

        # kustomization.yaml이 있는지 확인
        if [ -f "kustomization.yaml" ]; then
            kubectl apply -k . -n argocd
            log_success "✅ Kustomization을 통한 ArgoCD Applications 배포 완료"
        else
            # 개별 파일 배포
            log_step "📄 개별 YAML 파일 배포 중"
            for yaml_file in *.yaml; do
                if [ -f "$yaml_file" ]; then
                    kubectl apply -f "$yaml_file" -n argocd
                    log_success "✅ $yaml_file 배포 완료"
                fi
            done
        fi
    else
        log_error "❌ ArgoCD Application 디렉토리를 찾을 수 없습니다: $PROJECT_ROOT/argocd"
        exit 1
    fi

    # ArgoCD Applications 동기화 상태 확인
    log_step "🔄 ArgoCD Applications 동기화 확인 중"
    sleep 10
    kubectl get applications -n argocd 2>/dev/null || log_info "ArgoCD Applications가 아직 생성되지 않았습니다."

    log_success "✅ ArgoCD Applications 배포 완료"
    echo ""
}

# 배포 상태 확인
check_deployment_status() {
    log_header "📊 전체 배포 상태 확인"

    echo ""
    log_info "=== 네임스페이스 목록 ==="
    kubectl get namespaces

    echo ""
    log_info "=== 전체 Pod 상태 ==="
    kubectl get pods --all-namespaces | grep -E "(dev-|prod-|kong|argocd|monitoring|database)" || echo "관련 Pod를 찾을 수 없습니다."

    echo ""
    log_info "=== 서비스 상태 ==="
    kubectl get svc --all-namespaces | grep -E "(dev-|prod-|kong|argocd)" || echo "관련 서비스를 찾을 수 없습니다."

    echo ""
    log_info "=== Ingress 상태 ==="
    kubectl get ingress --all-namespaces || echo "Ingress 리소스를 찾을 수 없습니다."

    echo ""
    log_info "=== HPA 상태 ==="
    kubectl get hpa --all-namespaces || echo "HPA 리소스를 찾을 수 없습니다."

    echo ""
    log_info "=== PVC 상태 ==="
    kubectl get pvc --all-namespaces || echo "PVC 리소스를 찾을 수 없습니다."

    if [ "$DEPLOY_ARGOCD" == "true" ]; then
        echo ""
        log_info "=== ArgoCD Applications 상태 ==="
        kubectl get applications -n argocd 2>/dev/null || echo "ArgoCD Applications를 찾을 수 없습니다."
    fi
}

# 롤백 함수
rollback_deployment() {
    log_warning "🔄 배포 실패 시 롤백 수행 중..."
    log_info "수동으로 다음 명령어를 실행하여 문제를 해결하세요:"
    echo "  kubectl get pods --all-namespaces | grep -E '(Error|CrashLoopBackOff|Pending)'"
    echo "  kubectl describe pod <pod-name> -n <namespace>"
    echo "  kubectl logs <pod-name> -n <namespace>"
}

# 메인 실행 함수
main() {
    log_header "🎯 PlayUs Kubernetes 전체 인프라 배포 시작"
    log_info "배포 환경: $ENVIRONMENT"
    echo ""

    # 배포 옵션 표시
    echo "📋 배포 옵션:"
    echo "   - Sealed Secrets: $([ "$DEPLOY_SEALED_SECRETS" == "true" ] && echo "✅" || echo "❌")"
    echo "   - Kong Ingress: $([ "$DEPLOY_KONG" == "true" ] && echo "✅" || echo "❌")"
    echo "   - 데이터베이스: $([ "$DEPLOY_DATABASES" == "true" ] && echo "✅" || echo "❌")"
    echo "   - 마이크로서비스: $([ "$DEPLOY_SERVICES" == "true" ] && echo "✅" || echo "❌")"
    echo "   - 모니터링: $([ "$DEPLOY_MONITORING" == "true" ] && echo "✅" || echo "❌")"
    echo "   - ArgoCD: $([ "$DEPLOY_ARGOCD" == "true" ] && echo "✅" || echo "❌")"
    echo ""

    # 사용자 확인
    read -p "계속 진행하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "배포가 취소되었습니다."
        exit 0
    fi

    # 에러 발생 시 롤백 함수 호출
    trap rollback_deployment ERR

    # 배포 실행 (개선된 순서)
    check_prerequisites          # 필수 스크립트 검증 포함
    deploy_namespaces
    setup_sealed_secrets
    deploy_kong
    deploy_kong_ingress          # Kong Ingress 설정 추가
    check_dependencies           # 의존성 확인
    deploy_databases
    deploy_services              # 마이크로서비스
    deploy_monitoring            # 모니터링 스택
    deploy_argocd                # ArgoCD 설치
    deploy_argocd_applications   # ArgoCD Applications 배포
    check_deployment_status      # 최종 상태 확인

    # 완료 메시지
    log_header "🎉 PlayUs Kubernetes 인프라 배포 완료!"
    echo ""
    log_success "모든 컴포넌트가 성공적으로 배포되었습니다."
    echo ""
    log_info "📝 다음 단계:"
    echo "   1. ArgoCD UI 접속하여 애플리케이션 상태 확인"
    echo "   2. Kong Gateway를 통한 서비스 접근 테스트"
    echo "   3. 모니터링 대시보드 확인 (Prometheus/Grafana)"
    echo "   4. 각 마이크로서비스 헬스체크 수행"
    echo ""
    log_info "🔧 유용한 명령어:"
    echo "   - 전체 상태 확인: kubectl get pods --all-namespaces"
    echo "   - 특정 서비스 로그: kubectl logs -n <namespace> deployment/<service-name>"
    echo "   - ArgoCD 접속: kubectl port-forward svc/argocd-server -n argocd 8080:80"
    echo "   - Kong 상태 확인: kubectl get svc -n kong"
    echo "   - ArgoCD 초기 패스워드: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

# 스크립트 실행
main "$@"
