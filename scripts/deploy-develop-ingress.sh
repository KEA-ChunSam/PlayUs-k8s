#!/bin/bash

# Kong Ingress 자동 배포 스크립트
CHART_PATH="./kong-ingress-chart"
VALUES_DIR="${CHART_PATH}/values-dev"

# 배포 전 이전 리소스 제거 (선택사항)
echo "기존 Kong Ingress 리소스 정리 중..."
kubectl get ingress --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' | grep -i ingress | while read ns ingress; do
  if kubectl get ingress -n $ns $ingress -o yaml | grep -q "kubernetes.io/ingress.class: kong"; then
    kubectl delete ingress -n $ns $ingress
    echo "삭제됨: $ns/$ingress"
  fi
done

# values 디렉토리의 모든 YAML 파일에 대해 배포 실행
echo "Kong Ingress 배포 시작"
for values_file in ${VALUES_DIR}/*.yaml; do
  # 파일 이름에서 서비스 이름 추출 (확장자 제외)
  service_name=$(basename "$values_file" .yaml)

  echo "배포 중: $service_name Ingress"

  # Helm으로 배포 (존재하면 업그레이드, 없으면 설치)
  if helm list -q | grep -q "${service_name}-ingress"; then
    helm upgrade "${service_name}-ingress" $CHART_PATH -f "$values_file"
  else
    helm install "${service_name}-ingress" $CHART_PATH -f "$values_file"
  fi
done

echo "모든 Kong Ingress 배포 완료!"

# Ingress 목록 확인
echo "배포된 Kong Ingress 목록:"
kubectl get ingress --all-namespaces | grep -i kong
