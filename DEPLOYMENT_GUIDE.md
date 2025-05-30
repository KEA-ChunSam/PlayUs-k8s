# 🚀 PlayUs 완전 배포 가이드

## 📋 사전 준비 체크리스트

### 1. 마스터 노드 확인
```bash
# 1. 클러스터 상태 확인
kubectl cluster-info
kubectl get nodes

# 2. 필요한 도구들 설치 확인
kubectl version --client
helm version
kubeseal --version
```

### 2. ArgoCD 설치 확인
```bash
# ArgoCD 네임스페이스 확인
kubectl get namespace argocd

# ArgoCD가 없다면 설치 (자동화 스크립트 사용)
./scripts/setup-argocd.sh

# 또는 수동 설치
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### 3. Sealed Secret Controller 설치
```bash
# 자동화 스크립트 사용 (권장)
./scripts/setup-sealed-secret.sh

# 또는 수동 설치
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/controller.yaml
```

## 🚀 **원클릭 배포 (권장)**

### 완전 자동화 배포
```bash
# 기본 IP로 전체 배포
./deploy-all.sh

# 사용자 지정 IP로 배포
./deploy-all.sh 129.154.50.74

# 환경과 IP 모두 지정
./deploy-all.sh 129.154.50.74 develop
```

### 배포 옵션 제어
```bash
# 특정 컴포넌트만 배포
DEPLOY_KONG=false ./deploy-all.sh          # Kong 제외
DEPLOY_DATABASES=false ./deploy-all.sh     # 데이터베이스 제외
DEPLOY_SERVICES=false ./deploy-all.sh      # 서비스 제외
```

## 🗂️ 단계별 수동 배포

### **1단계: 인프라 설치**
```bash
# Sealed Secrets Controller
./scripts/setup-sealed-secret.sh

# ArgoCD 설치
./scripts/setup-argocd.sh

# Kong Ingress Controller 설치
./scripts/deploy-kong.sh develop
```

### **2단계: 네임스페이스 생성**
```bash
kubectl apply -f argocd/dev-namespaces.yaml
```

### **3단계: 데이터베이스 IP 설정**
```bash
# 각 데이터베이스별 IP 설정
cd shared/database/mongo-chat
./generate-mongo-chat-config.sh 129.154.50.74

cd ../mongo-read
./generate-mongo-read-config.sh 129.154.50.74

cd ../mysql
./generate-mysql-config.sh 129.154.50.74

cd ../elasticsearch
./generate-elasticsearch-config.sh 129.154.50.74
```

### **4단계: ArgoCD 애플리케이션 배포**
```bash
# 데이터베이스 ApplicationSet
kubectl apply -f argocd/dev-database.yaml

# 메인 서비스 ApplicationSet
kubectl apply -f argocd/dev-applicationset.yaml

# Ingress 설정
kubectl apply -f argocd/dev-ingress.yaml

# Kong Ingress 규칙 배포
./scripts/deploy-develop-ingress.sh
```

## 🔍 **배포 상태 검증**

### 자동 검증 스크립트 (권장)
```bash
# 전체 배포 상태 검증
./verify-deployment.sh
```

### 수동 검증
```bash
# 전체 Pod 상태 확인
kubectl get pods --all-namespaces

# ArgoCD 애플리케이션 상태
kubectl get applications -n argocd

# 데이터베이스 연결 확인
kubectl get svc,endpoints -n dev-db

# Kong 외부 IP 확인
kubectl get svc -n dev-gateway
```

## 🌐 **외부 접근 설정**

### ArgoCD UI 접근
```bash
# Kong을 통한 접근 (외부 IP 확인 후)
KONG_IP=$(kubectl get svc -n dev-gateway ingress-kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "ArgoCD: http://$KONG_IP/argocd"

# 또는 포트 포워딩
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080
```

### API 엔드포인트 테스트
```bash
# Kong 외부 IP 확인
KONG_IP=$(kubectl get svc -n dev-gateway ingress-kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# API 테스트
curl -i http://$KONG_IP/api/users/health
curl -i http://$KONG_IP/api/community/health
curl -i http://$KONG_IP/api/match/health
curl -i http://$KONG_IP/api/search/health
curl -i http://$KONG_IP/api/twp/health
```

## 🔧 트러블슈팅

### 문제 1: SealedSecret 복호화 실패
```bash
# Sealed Secret Controller 로그 확인
kubectl logs -n kube-system -l name=sealed-secrets-controller

# 해결방법: SealedSecret 재생성
cd shared/database/<database-name>
./generate-<database-name>-config.sh <ip-address>
```

### 문제 2: ArgoCD 동기화 실패
```bash
# ArgoCD 애플리케이션 상태 확인
kubectl get applications -n argocd

# 수동 동기화 강제 실행
kubectl patch application <app-name> -n argocd --type merge --patch '{"spec":{"syncPolicy":{"syncOptions":["CreateNamespace=true"]}}}'

# ArgoCD UI에서 Sync 버튼 클릭
```

### 문제 3: Kong Ingress 연결 실패
```bash
# Kong 설정 확인
kubectl describe ingress <ingress-name> -n <namespace>

# Kong 프록시 로그 확인
kubectl logs -n dev-gateway -l app.kubernetes.io/component=app

# Kong Ingress 재배포
./scripts/deploy-develop-ingress.sh
```

### 문제 4: Pod가 시작되지 않음
```bash
# Pod 상세 정보 확인
kubectl describe pod <pod-name> -n <namespace>

# Pod 로그 확인
kubectl logs <pod-name> -n <namespace>

# 이벤트 확인
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp
```

## 🎯 최종 확인 사항

### 1. 모든 서비스 정상 동작 확인
```bash
# 검증 스크립트 실행
./verify-deployment.sh

# 또는 수동 확인
kubectl get pods --all-namespaces | grep -v Running
kubectl get applications -n argocd
```

### 2. 네트워크 연결 테스트
```bash
# Kong 프록시 테스트
KONG_IP=$(kubectl get svc -n dev-gateway ingress-kong-kong-proxy -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Health Check
curl -f http://$KONG_IP/api/users/health || echo "User Service 연결 실패"
curl -f http://$KONG_IP/api/community/health || echo "Community Service 연결 실패"
```

## 📝 주요 명령어 요약

### 빠른 배포
```bash
# 전체 자동 배포
./deploy-all.sh 129.154.50.74

# 배포 검증
./verify-deployment.sh

# Git 커밋 (SealedSecret 파일들)
git add . && git commit -m "feat: 데이터베이스 IP SealedSecret 설정" && git push
```

### 상태 모니터링
```bash
# 실시간 Pod 상태 모니터링
watch kubectl get pods --all-namespaces

# ArgoCD 애플리케이션 상태
watch kubectl get applications -n argocd

# Kong 외부 IP 확인
kubectl get svc -n dev-gateway ingress-kong-kong-proxy
```

### 로그 확인
```bash
# 전체 이벤트 확인
kubectl get events --all-namespaces --sort-by=.metadata.creationTimestamp

# 특정 Pod 로그
kubectl logs -f <pod-name> -n <namespace>

# ArgoCD 애플리케이션 상세 정보
kubectl describe application <app-name> -n argocd
```

## 🚀 성공적인 배포 확인

배포가 성공하면 다음과 같은 상태가 됩니다:

1. ✅ 모든 Pod가 `Running` 상태
2. ✅ ArgoCD 애플리케이션들이 `Synced` 및 `Healthy` 상태
3. ✅ Kong을 통해 외부에서 API 접근 가능
4. ✅ 데이터베이스 엔드포인트가 올바른 IP로 설정됨
5. ✅ SealedSecret이 정상적으로 복호화됨

## 📞 지원

문제가 발생하면:
1. `./verify-deployment.sh` 스크립트로 상태 확인
2. 관련 Pod의 로그 확인
3. ArgoCD UI에서 동기화 상태 확인
4. Kong 설정 및 Ingress 규칙 확인 