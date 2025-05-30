#!/bin/bash

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
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"  # scripts 디렉토리의 부모 디렉토리가 프로젝트 루트
OVERLAYS_DIR="${PROJECT_ROOT}/overlays/develop"
ORIGINAL_DIR="$(pwd)"  # 현재 디렉토리 저장

# sealed-secrets-public.pem 파일 경로 설정
export SEALED_SECRETS_CERT="${PROJECT_ROOT}/sealed-secrets-public.pem"

# sealed-secrets-public.pem 파일 존재 확인
if [ ! -f "$SEALED_SECRETS_CERT" ]; then
    log_error "sealed-secrets-public.pem 파일을 찾을 수 없습니다: $SEALED_SECRETS_CERT"
    log_info "프로젝트 루트 디렉토리에 sealed-secrets-public.pem 파일이 있는지 확인해주세요."
    exit 1
fi

# 서비스 목록
SERVICES=(
    "user-service"
    "community-service"
    "match-service"
    "search-service"
    "twp-service"
)

log_header "🔐 서비스 시크릿 생성 시작"

# kubeseal 설치 확인
if ! command -v kubeseal &> /dev/null; then
    log_error "kubeseal이 설치되어 있지 않습니다."
    log_info "설치 방법: https://github.com/bitnami-labs/sealed-secrets#installation"
    exit 1
fi

# Sealed Secrets Controller 실행 확인
if ! kubectl get deployment sealed-secrets-controller -n kube-system &> /dev/null; then
    log_error "Sealed Secrets Controller가 실행 중이지 않습니다."
    log_info "먼저 Sealed Secrets Controller를 설치해주세요."
    exit 1
fi

# 각 서비스의 시크릿 생성
for service in "${SERVICES[@]}"; do
    log_header "📦 ${service} 시크릿 생성"
    
    SECRET_WORKSPACE="${OVERLAYS_DIR}/${service}/secret-workspace"
    GENERATE_SCRIPT="${SECRET_WORKSPACE}/generate-sealed-secret.sh"
    
    # secret-workspace 디렉토리 확인
    if [ ! -d "$SECRET_WORKSPACE" ]; then
        log_warning "${service}의 secret-workspace 디렉토리가 없습니다. 건너뜁니다."
        continue
    fi
    
    # generate-sealed-secret.sh 스크립트 확인
    if [ ! -f "$GENERATE_SCRIPT" ]; then
        log_warning "${service}의 generate-sealed-secret.sh 스크립트가 없습니다. 건너뜁니다."
        continue
    fi
    
    # .env.secret 파일 확인
    if [ ! -f "${SECRET_WORKSPACE}/.env.secret" ]; then
        log_warning "${service}의 .env.secret 파일이 없습니다. 건너뜁니다."
        continue
    fi
    
    # 스크립트 실행 권한 부여 및 실행
    log_step "${service} 시크릿 생성 중..."
    chmod +x "$GENERATE_SCRIPT"
    if (cd "$SECRET_WORKSPACE" && SEALED_SECRETS_CERT="$SEALED_SECRETS_CERT" ./generate-sealed-secret.sh); then
        log_success "${service} 시크릿 생성 완료"
    else
        log_error "${service} 시크릿 생성 실패"
    fi
    # 서브쉘을 사용했으므로 자동으로 원래 디렉토리로 돌아감
done

# 원래 디렉토리로 이동 (안전을 위해)
cd "$ORIGINAL_DIR"

log_header "✅ PlayUs 서비스 시크릿 생성 완료"

# 다음 단계 안내
echo ""
log_info "📋 다음 단계:"
echo -e "${PURPLE}  1. 생성된 sealed-secret.yaml 파일들을 Git에 커밋${NC}"
echo -e "${PURPLE}     git add overlays/develop/*/sealed-secret.yaml${NC}"
echo -e "${PURPLE}     git commit -m 'feat: 서비스 시크릿 암호화'${NC}"
echo -e "${PURPLE}     git push${NC}"
echo ""
echo -e "${PURPLE}  2. ArgoCD 애플리케이션 배포${NC}"
echo -e "${PURPLE}     kubectl apply -f argocd/dev-applicationset.yaml${NC}" 
