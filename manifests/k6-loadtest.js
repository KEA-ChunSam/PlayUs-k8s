/**
 * K6 부하테스트 스크립트 - 2만명 동시 사용자
 *
 * 테스트 목적:
 * - MSA 아키텍처의 확장성 및 성능 한계 측정
 * - Circuit Breaker 패턴 동작 검증
 * - 메모리 최적화를 통한 대규모 부하테스트 안정성 확보
 * - 웹 서비스와 API 서비스의 개별 성능 분석
 *
 * 테스트 대상:
 * - 웹 서비스: https://web.playus.o-r.kr
 * - API 서비스: https://api.playus.o-r.kr/user/user/profile
 *
 * 부하 패턴:
 * - 1,000명 → 3,000명 → 6,000명 → 10,000명 → 15,000명 → 20,000명
 * - 총 테스트 시간: 15분
 * - 점진적 증가 후 단계적 감소로 시스템 복구 능력 검증
 *
 * 사용 방법:
 *
 * 1) 로컬 환경에서 실행:
 *    k6 run k6-loadtest.js
 *
 * 2) 결과 파일과 함께 실행:
 *    k6 run --out json=results.json k6-loadtest.js
 *
 * 3) Kubernetes 환경에서 실행:
 *    # 파일을 Pod에 복사
 *    kubectl cp k6-loadtest.js k6-loadtest-pod:/tmp/ -n loadtest2
 *
 *    # Pod에서 실행
 *    kubectl exec -it k6-loadtest-pod -n loadtest2 -- k6 run /tmp/k6-loadtest.js
 *
 * 4) 실시간 모니터링 (별도 터미널):
 *    watch -n 3 'kubectl top pod k6-loadtest-pod -n loadtest2'
 *
 * 주의사항:
 * - 메모리 최소 7GB 이상 권장
 * - 네트워크 대역폭 확보
 * - 대상 서버 사전 알림 필요 (대규모 부하)
 */

import http from "k6/http";
import { sleep, check, group } from "k6";

export let options = {
  // 부하 증가 단계 (총 15분)
  stages: [
    { duration: "2m", target: 1000 },      // 1단계: 1천명
    { duration: "2m", target: 3000 },      // 2단계: 3천명
    { duration: "2m", target: 6000 },      // 3단계: 6천명
    { duration: "2m", target: 10000 },     // 4단계: 1만명
    { duration: "2m", target: 15000 },     // 5단계: 1.5만명
    { duration: "2m", target: 20000 },     // 6단계: 2만명
    { duration: "1m", target: 10000 },     // 7단계: 급격한 감소
    { duration: "1m", target: 2000 },      // 8단계: 정상화
    { duration: "1m", target: 0 },         // 9단계: 종료
  ],

  // 성능 임계값 설정
  thresholds: {
    "http_req_duration": ["p(95)<15000"],    // 95% 요청이 15초 이내
    "http_req_failed": ["rate<0.70"],        // 실패율 70% 이하
    "checks": ["rate>0.50"],                 // 체크 성공률 50% 이상
  },

  // 메모리 최적화 설정 (OOM 방지)
  discardResponseBodies: true,   // 응답 본문 메모리에서 즉시 제거
  noConnectionReuse: false,      // 연결 재사용
  batchPerHost: 20,              // 호스트당 배치 크기
  maxRedirects: 0,               // 리다이렉트 비활성화
  insecureSkipTLSVerify: true,   // TLS 검증 스킵 (성능 향상)
};

// Circuit Breaker 구현
let circuitOpen = false;    // Circuit Breaker 상태
let failures = 0;           // 연속 실패 카운터

export default function() {
  const userId = Math.floor(Math.random() * 1000000);  // 고유 사용자 ID

  group("MSA Test - 20K Users", function() {

    // 웹 서비스 테스트 (프론트엔드)
    if (!circuitOpen) {
      let webResp = http.get("https://web.playus.o-r.kr", {
        headers: {
          "User-Agent": "k6-optimized-20k/1.0",
          "X-User-ID": userId.toString(),
        },
        timeout: "10s",  // 웹 서비스 타임아웃
      });

      // Circuit Breaker 로직
      if (webResp.status >= 500) {
        failures++;
        if (failures > 15) {  // 15회 연속 실패 시 Circuit Open
          circuitOpen = true;
          console.log("🚨 Circuit Breaker OPEN - System Protection Activated");
        }
      } else if (webResp.status === 200) {
        failures = Math.max(0, failures - 2);  // 성공 시 실패 카운터 감소
        if (circuitOpen) {
          circuitOpen = false;
          console.log("✅ Circuit Breaker CLOSED - System Recovered");
        }
      }

      // 웹 서비스 성능 체크
      check(webResp, {
        "web: status ok": (r) => r.status === 200,
        "web: fast": (r) => r.timings.duration < 8000,
        "web: not 5xx": (r) => r.status < 500,
      });
    } else {
      // Circuit Breaker가 열린 상태 - 추가 요청 차단
      console.log("⚠️  Circuit Breaker OPEN - Request Blocked");
    }

    // API 서비스 테스트
    // 70%만 API 호출하여 부하 분산
    if (!circuitOpen && Math.random() > 0.3) {
      let apiResp = http.get("https://api.playus.o-r.kr/user/user/profile", {
        headers: {
          "X-User-ID": userId.toString(),
          "Accept": "application/json"
        },
        timeout: "6s",  // API 서비스 타임아웃
      });

      // API 서비스 성능 체크
      check(apiResp, {
        "api: valid": (r) => r.status === 200 || r.status === 401,  // 401도 정상 (인증 필요)
        "api: not timeout": (r) => r.status !== 0,
      });
    }
  });

  // 사용자 행동 시뮬레이션 (0.2-1.7초 랜덤 대기)
  sleep(Math.random() * 1.5 + 0.2);
}

// 테스트 시작 시 실행
export function setup() {
  console.log("=== K6 부하테스트 시작 ===");
  console.log("Memory Optimized MSA Test - 20,000 Users");
  console.log("Memory: 7GB (OOM Prevention)");
  console.log("Target: Web + API Services");
  console.log("Duration: ~15 minutes");
  console.log("Circuit Breaker: Enabled");
  console.log("=====================================");
  return { start: Date.now() };
}

// 결과 요약
export function teardown(data) {
  const mins = (Date.now() - data.start) / 60000;
  console.log("");
  console.log("=== 테스트 완료 ===");
  console.log(`실행 시간: ${mins.toFixed(1)}분`);
  console.log(`Circuit Breaker 최종 상태: ${circuitOpen ? "OPEN (보호 중)" : "CLOSED (정상)"}`);
  console.log("========================");
}
