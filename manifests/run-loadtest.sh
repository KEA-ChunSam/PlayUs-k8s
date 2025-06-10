#!/bin/bash

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로그 함수
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 사전 검사
pre_check() {
    log_info "부하 테스트 사전 검사 시작..."

    # kubectl 확인
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl이 설치되어 있지 않습니다."
        exit 1
    fi

    # 클러스터 연결 확인
    if ! kubectl cluster-info &> /dev/null; then
        log_error "쿠버네티스 클러스터에 연결할 수 없습니다."
        exit 1
    fi

    # 현재 리소스 상태 확인
    log_info "현재 클러스터 리소스 상태:"
    kubectl top nodes 2>/dev/null || log_warning "노드 메트릭을 가져올 수 없습니다."

    log_success "사전 검사 완료"
}

# 부하 테스트 실행
run_loadtest() {
    log_info "부하 테스트 시작..."

    # 기존 테스트 정리
    log_info "기존 부하 테스트 정리 중..."
    kubectl delete namespace loadtest --ignore-not-found=true
    sleep 5

    # 새 테스트 배포
    log_info "부하 테스트 배포 중..."
    kubectl apply -f k6-loadtest.yaml

    # Job 시작 대기
    log_info "Job 시작 대기 중..."
    kubectl wait --for=condition=ready pod -l app=k6-loadtest -n loadtest --timeout=60s

    log_success "부하 테스트가 시작되었습니다!"
}

# 실시간 모니터링
monitor_test() {
    log_info "부하 테스트 모니터링 시작..."
    log_info "실시간 로그를 확인하려면 Ctrl+C를 눌러 중단할 수 있습니다."

    # Job 상태 확인
    while true; do
        JOB_STATUS=$(kubectl get job k6-loadtest-job -n loadtest -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "")

        if [[ "$JOB_STATUS" == "Complete" ]]; then
            log_success "부하 테스트가 완료되었습니다!"
            break
        elif [[ "$JOB_STATUS" == "Failed" ]]; then
            log_error "부하 테스트가 실패했습니다!"
            break
        fi

        # 실시간 로그 출력
        kubectl logs -f job/k6-loadtest-job -n loadtest -c k6 --tail=10 2>/dev/null || true
        sleep 10
    done
}

# 결과 수집
collect_results() {
    log_info "테스트 결과 수집 중..."

    # 최종 로그 출력
    echo "=== 부하 테스트 최종 결과 ==="
    kubectl logs job/k6-loadtest-job -n loadtest -c k6 --tail=50

    # 결과 파일 추출 (가능한 경우)
    RESULT_POD=$(kubectl get pods -n loadtest -l app=k6-loadtest -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$RESULT_POD" ]]; then
        log_info "결과 파일을 로컬로 복사 중..."
        kubectl cp loadtest/$RESULT_POD:/results ./loadtest-results/ -c result-collector 2>/dev/null || log_warning "결과 파일 복사 실패"
    fi

    log_success "결과 수집 완료"
}

# 정리
cleanup() {
    log_info "테스트 환경 정리 중..."
    kubectl delete namespace loadtest --ignore-not-found=true
    log_success "정리 완료"
}

# 메인 함수
main() {
    echo "=== PlayUs 부하 테스트 자동화 스크립트 ==="
    echo "이 스크립트는 다음을 수행합니다:"
    echo "1. 사전 검사"
    echo "2. 부하 테스트 실행"
    echo "3. 실시간 모니터링"
    echo "4. 결과 수집"
    echo "5. 환경 정리"
    echo ""

    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "사용자가 취소했습니다."
        exit 0
    fi

    # 트랩 설정 (Ctrl+C 시 정리)
    trap cleanup EXIT

    pre_check
    run_loadtest
    monitor_test
    collect_results

    log_success "부하 테스트가 모두 완료되었습니다!"

    echo ""
    echo "=== 추가 명령어 ==="
    echo "• 실시간 로그 확인: kubectl logs -f job/k6-loadtest-job -n loadtest -c k6"
    echo "• 결과 확인: kubectl logs job/k6-loadtest-job -n loadtest -c result-collector"
    echo "• 수동 정리: kubectl delete namespace loadtest"
    echo ""
}

# 스크립트 실행
main "$@"
