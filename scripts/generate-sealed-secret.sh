#!/bin/bash

set -e

# === 설정 ===
SECRET_NAME=""
NAMESPACE="default"
ENV_FILE=""
SECRET_FILE="temp-secret.yaml"
PUBLIC_KEY_FILE="sealed-secrets-public.pem"

# 사용법 표시 함수
show_usage() {
  echo "사용법: $0 [-n 시크릿이름] [-s 네임스페이스] [-f 환경파일]"
  echo ""
  echo "옵션:"
  echo "  -n  생성할 시크릿 이름 (필수)"
  echo "  -s  쿠버네티스 네임스페이스 (기본값: default)"
  echo "  -f  환경변수 파일 경로 (필수)"
  echo ""
  echo "예시:"
  echo "  $0 -n database-credentials -s app-namespace -f .env.database"
  exit 1
}

# 명령줄 인자 파싱
while getopts "n:s:f:" opt; do
  case ${opt} in
    n )
      SECRET_NAME=$OPTARG
      ;;
    s )
      NAMESPACE=$OPTARG
      ;;
    f )
      ENV_FILE=$OPTARG
      ;;
    \? )
      show_usage
      ;;
  esac
done

# 필수 입력값 확인
if [ -z "$SECRET_NAME" ] || [ -z "$ENV_FILE" ]; then
  echo "❌ 오류: 시크릿 이름(-n)과 환경변수 파일(-f)은 필수입니다."
  show_usage
fi

SEALED_SECRET_FILE="sealed-${SECRET_NAME}.yaml"

echo "🔐 Sealed Secret 자동 생성 스크립트 실행"
echo "• 시크릿 이름: $SECRET_NAME"
echo "• 네임스페이스: $NAMESPACE"
echo "• 환경변수 파일: $ENV_FILE"

# 1. 퍼블릭 키 확인
if [ ! -f "$PUBLIC_KEY_FILE" ]; then
  echo "❌ 퍼블릭 키가 존재하지 않습니다: $PUBLIC_KEY_FILE"
  echo ""
  echo "다음 방법 중 하나로 퍼블릭 키를 가져오세요:"
  echo "1. 클러스터에서 직접 가져오기:"
  echo "   kubeseal --fetch-cert > $PUBLIC_KEY_FILE"
  echo ""
  echo "2. install-sealed-secrets.sh 스크립트를 먼저 실행하세요."
  exit 1
fi

# 2. .env 파일 확인
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ 환경 파일이 존재하지 않습니다: $ENV_FILE"
  echo "파일 경로를 확인하고 다시 시도하세요: $ENV_FILE"
  exit 1
fi

# 3. 파일 내용 확인
if [ ! -s "$ENV_FILE" ]; then
  echo "⚠️ 경고: 환경 파일이 비어있습니다: $ENV_FILE"
  read -p "계속 진행하시겠습니까? (y/n): " confirm
  if [ "$confirm" != "y" ]; then
    echo "작업이 취소되었습니다."
    exit 0
  fi
fi

# 4. Kubernetes Secret YAML 생성
echo "📝 Kubernetes Secret 생성 중"
kubectl create secret generic "$SECRET_NAME" \
  --from-env-file="$ENV_FILE" \
  --namespace "$NAMESPACE" \
  --dry-run=client -o yaml > "$SECRET_FILE"

# 5. SealedSecret으로 암호화
echo "🔐 SealedSecret으로 암호화 중"
kubeseal \
  --cert "$PUBLIC_KEY_FILE" \
  --namespace "$NAMESPACE" \
  --format yaml < "$SECRET_FILE" > "$SEALED_SECRET_FILE"

rm "$SECRET_FILE"

echo "✅ 완료!"
echo "📄 생성된 Sealed Secret: $SEALED_SECRET_FILE"
echo ""
echo "Kustomize를 사용:"
echo "   - 생성된 파일을 Kustomize 디렉토리 구조에 배치"
echo "   - Kustomization 파일에 리소스로 등록"
echo "   - 'kubectl apply -k ./경로' 명령으로 전체 애플리케이션 배포"
