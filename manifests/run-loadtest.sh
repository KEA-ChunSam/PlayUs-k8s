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

    # 현재 노드 확인
    log_info "사용 가능한 노드 목록:"
    kubectl get nodes -o wide

    # YAML 파일 존재 확인
    if [[ ! -f "k6-loadtest.yaml" ]]; then
        log_error "k6-loadtest.yaml 파일이 현재 디렉토리에 없습니다."
        exit 1
    fi

    # containerd 상태 확인 (현재 노드에서)
    log_info "현재 노드의 containerd 상태 확인..."
    sudo systemctl is-active containerd >/dev/null 2>&1 && log_success "containerd가 실행 중입니다." || log_warning "containerd 상태를 확인할 수 없습니다."

    log_success "사전 검사 완료"
}

# 부하 테스트 실행
run_loadtest() {
    log_info "부하 테스트 시작..."

    # 기존 테스트 정리
    log_info "기존 부하 테스트 정리 중..."
    kubectl delete namespace loadtest2 --ignore-not-found=true
    sleep 10

    # 새 테스트 배포
    log_info "부하 테스트 배포 중..."
    kubectl apply -f k6-loadtest.yaml

    # 네임스페이스 생성 대기
    log_info "네임스페이스 생성 대기 중..."
    kubectl wait --for=condition=Ready namespace/loadtest2 --timeout=30s 2>/dev/null || true

    # Job 시작 대기
    log_info "Job 생성 대기 중..."
    sleep 15

    # Pod 생성 확인
    log_info "Pod 상태 확인 중..."
    kubectl get pods -n loadtest2

    log_success "부하 테스트가 시작되었습니다!"
}

# 실시간 모니터링
monitor_test() {
    log_info "부하 테스트 모니터링 시작..."
    log_info "실시간 로그를 확인하려면 Ctrl+C를 눌러 중단할 수 있습니다."

    local monitor_count=0
    local max_monitor_time=60  # 최대 60회 체크 (약 10분)

    # Job과 Pod 상태 모니터링
    while [[ $monitor_count -lt $max_monitor_time ]]; do
        # Job 상태 확인
        JOB_STATUS=$(kubectl get job k6-loadtest-job -n loadtest -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Running")
        ACTIVE_JOBS=$(kubectl get job k6-loadtest-job -n loadtest -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
        SUCCEEDED_JOBS=$(kubectl get job k6-loadtest-job -n loadtest -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        FAILED_JOBS=$(kubectl get job k6-loadtest-job -n loadtest -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")

        log_info "Job 상태: $JOB_STATUS | Active: $ACTIVE_JOBS | Succeeded: $SUCCEEDED_JOBS | Failed: $FAILED_JOBS"

        if [[ "$JOB_STATUS" == "Complete" ]] || [[ "$SUCCEEDED_JOBS" -gt "0" ]]; then
            log_success "부하 테스트가 완료되었습니다!"
            break
        elif [[ "$JOB_STATUS" == "Failed" ]] || [[ "$FAILED_JOBS" -gt "0" ]]; then
            log_error "부하 테스트가 실패했습니다!"
            break
        fi

        # Pod 상태 확인
        POD_NAME=$(kubectl get pods -n loadtest -l app=k6-loadtest -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [[ -n "$POD_NAME" ]]; then
            POD_STATUS=$(kubectl get pod $POD_NAME -n loadtest -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            log_info "Pod 상태: $POD_STATUS"

            # 실시간 로그 출력 (최근 5줄만)
            log_info "=== 최근 로그 (k6 컨테이너) ==="
            kubectl logs $POD_NAME -n loadtest -c k6 --tail=5 2>/dev/null || log_warning "로그를 가져올 수 없습니다."
        fi

        ((monitor_count++))
        sleep 10
    done

    if [[ $monitor_count -ge $max_monitor_time ]]; then
        log_warning "모니터링 시간이 초과되었습니다. 수동으로 확인해주세요."
    fi
}

# 결과 수집
collect_results() {
    log_info "테스트 결과 수집 중..."

    # Pod 이름 가져오기
    POD_NAME=$(kubectl get pods -n loadtest -l app=k6-loadtest -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$POD_NAME" ]]; then
        log_error "테스트 Pod를 찾을 수 없습니다."
        return 1
    fi

    # k6 컨테이너 로그
    echo ""
    echo "=== k6 부하 테스트 최종 결과 ==="
    kubectl logs $POD_NAME -n loadtest -c k6 --tail=100 2>/dev/null || log_error "k6 로그를 가져올 수 없습니다."

    # 결과 수집기 로그
    echo ""
    echo "=== 결과 수집기 로그 ==="
    kubectl logs $POD_NAME -n loadtest -c result-collector --tail=50 2>/dev/null || log_warning "결과 수집기 로그를 가져올 수 없습니다."

    # 결과 파일 추출 시도
    log_info "결과 파일을 로컬로 복사 시도 중..."
    mkdir -p ./loadtest-results

    # 여러 파일 복사 시도
    kubectl cp loadtest/$POD_NAME:/results/test-results.json ./loadtest-results/ -c result-collector 2>/dev/null && log_success "test-results.json 복사 완료" || log_warning "test-results.json 복사 실패"
    kubectl cp loadtest/$POD_NAME:/results/summary.json ./loadtest-results/ -c result-collector 2>/dev/null && log_success "summary.json 복사 완료" || log_warning "summary.json 복사 실패"
    kubectl cp loadtest/$POD_NAME:/results/console.log ./loadtest-results/ -c result-collector 2>/dev/null && log_success "console.log 복사 완료" || log_warning "console.log 복사 실패"

    # 클러스터 상태 확인
    echo ""
    echo "=== 테스트 후 클러스터 상태 ==="
    kubectl top nodes 2>/dev/null || log_warning "노드 메트릭을 가져올 수 없습니다."

    log_success "결과 수집 완료"
}

# 정리
cleanup() {
    log_info "테스트 환경 정리 중..."

    # 사용자 확인
    read -p "테스트 환경을 정리하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace loadtest2 --ignore-not-found=true
        log_success "정리 완료"
    else
        log_info "정리를 건너뛰었습니다. 수동으로 정리하려면: kubectl delete namespace loadtest2"
    fi
}

# 도움말
show_help() {
    echo "PlayUs 부하 테스트 자동화 스크립트"
    echo ""
    echo "사용법: $0 [옵션]"
    echo ""
    echo "옵션:"
    echo "  -h, --help     이 도움말 표시"
    echo "  -c, --cleanup  테스트 환경만 정리"
    echo "  -m, --monitor  기존 테스트 모니터링만"
    echo "  -r, --results  결과만 수집"
    echo ""
    echo "기본 실행: 전체 테스트 프로세스 실행"
}

# 메인 함수
main() {
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cleanup)
            cleanup
            exit 0
            ;;
        -m|--monitor)
            monitor_test
            exit 0
            ;;
        -r|--results)
            collect_results
            exit 0
            ;;
        "")
            # 기본 실행
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            show_help
            exit 1
            ;;
    esac

    echo "=== PlayUs 부하 테스트 자동화 스크립트 ==="
    echo "이 스크립트는 다음을 수행합니다:"
    echo "1. 사전 검사 (클러스터, 파일, 리소스 상태)"
    echo "2. 부하 테스트 실행 (축소된 시나리오)"
    echo "3. 실시간 모니터링 (약 10분)"
    echo "4. 결과 수집 및 로컬 저장"
    echo "5. 선택적 환경 정리"
    echo ""
    echo "테스트 대상:"
    echo "- Web: https://web.playus.o-r.kr"
    echo "- API: https://api.playus.o-r.kr/user/user/profile"
    echo ""

    read -p "계속하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "사용자가 취소했습니다."
        exit 0
    fi

    pre_check
    run_loadtest
    monitor_test
    collect_results
    cleanup

    log_success "부하 테스트가 모두 완료되었습니다!"

    echo ""
    echo "=== 추가 명령어 ==="
    echo "• 실시간 로그 확인: kubectl logs -f job/k6-loadtest-job -n loadtest -c k6"
    echo "• 결과 확인: kubectl logs job/k6-loadtest-job -n loadtest -c result-collector"
    echo "• Pod 상태 확인: kubectl get pods -n loadtest"
    echo "• 수동 정리: kubectl delete namespace loadtest"
    echo "• 로컬 결과 확인: ls -la ./loadtest-results/"
    echo ""
}

# 스크립트 실행
main "$@"
