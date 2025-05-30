# PlayUs Kubernetes 배포 환경

PlayUs 마이크로서비스의 Kubernetes 배포를 위한 GitOps 기반 인프라스트럭처 리포지토리입니다. ArgoCD를 사용하여 자동화된 배포와 모니터링을 제공합니다.

## 📋 목차

- [아키텍처 개요](#아키텍처-개요)
- [프로젝트 구조](#프로젝트-구조)
- [주요 컴포넌트](#주요-컴포넌트)
- [환경 설정](#환경-설정)
- [배포 가이드](#배포-가이드)
- [모니터링](#모니터링)
- [트러블슈팅](#트러블슈팅)

## 🏗️ 아키텍처 개요

PlayUs는 다음 마이크로서비스로 구성됩니다.

- **user-service**: 사용자 관리 서비스
- **community-service**: 커뮤니티 및 게시판 서비스
- **search-service**: 검색 기능 서비스
- **twp-service**: 직관팟 관련 서비스

### 기술 스택
- **Orchestration**: Kubernetes
- **GitOps**: ArgoCD
- **API Gateway**: Kong Ingress Controller
- **Monitoring**: Prometheus + Grafana
- **Secret Management**: Sealed Secrets
- **Configuration**: Kustomize

## 📁 프로젝트 구조

```
PlayUs-k8s/
├── argocd/                     # ArgoCD 애플리케이션 정의
│   ├── dev-applicationset.yaml # 개발환경 ApplicationSet
│   ├── dev-namespaces.yaml     # 네임스페이스 정의
│   ├── dev-database.yaml       # 데이터베이스 설정
│   └── dev-ingress.yaml        # 인그레스 설정
├── base/                       # 기본 Kubernetes 매니페스트
│   ├── user-service/           # 각 서비스별 기본 설정
│   ├── community-service/
│   ├── match-service/
│   ├── search-service/
│   ├── twp-service/
│   └── monitoring/             # 모니터링 스택
├── overlays/                   # 환경별 커스터마이징
│   └── develop/                # 개발환경 오버레이
│       ├── user-service/
│       ├── community-service/
│       ├── match-service/
│       ├── search-service/
│       ├── twp-service/
│       └── monitoring/
├── shared/                     # 공유 리소스
│   ├── database/               # 데이터베이스 공통 설정
│   └── namespaces/             # 네임스페이스 템플릿
├── kong-ingress-chart/         # Kong 설정
├── manifests/                  # 공통 매니페스트
└── .github/                    # GitHub Actions 워크플로우
```

## 🛠️ 주요 컴포넌트

### ArgoCD
- **목적**: GitOps 기반 지속적 배포
- **네임스페이스**: `argocd`
- **접근**: ArgoCD UI를 통한 배포 모니터링

### Kong Ingress Controller
- **목적**: API 게이트웨이 및 라우팅
- **기능**: 라우팅, 로드 밸런싱

### Sealed Secrets
- **목적**: 안전한 시크릿 관리
- **방식**: 암호화된 시크릿을 Git에 안전하게 저장

### Kustomize
- **목적**: 환경별 설정 커스터마이징
- **패턴**: base + overlays 구조

## ⚙️ 환경 설정

### 사전 요구사항

```bash
# 필수 도구 설치
kubectl   # Kubernetes CLI
kustomize # Kustomize CLI (kubectl에 내장)
helm      # Helm 패키지 매니저
argocd    # ArgoCD CLI
```

### 1단계: 클러스터 준비

```bash
# 네임스페이스 생성
kubectl apply -f argocd/dev-namespaces.yaml

# ArgoCD 설치
./scripts/setup-argocd.sh
```

### 2단계: Sealed Secrets 설정

```bash
# Sealed Secrets Controller 설치 및 설정
./scripts/setup-sealed-secret.sh
```

### 3단계: Kong Ingress Controller 배포

```bash
# Kong 설치 및 설정
./scripts/deploy-kong.sh
```

### 4단계: ArgoCD Applications 배포

```bash
# ApplicationSet 배포 (모든 서비스 자동 배포)
kubectl apply -f argocd/dev-applicationset.yaml
```

## 🚀 배포 가이드

### 자동 배포

ArgoCD가 Git 저장소의 변경사항을 자동으로 감지하여 배포합니다.

1. 코드 변경 후 `develop` 브랜치에 푸시
2. ArgoCD가 변경사항 감지 (기본 3분 간격)
3. 자동으로 클러스터에 배포
4. ArgoCD UI에서 배포 상태 확인

### 수동 배포

긴급 상황이나 테스트 시 수동 배포합니다.

```bash
# 특정 서비스만 배포
kustomize build overlays/develop/user-service | kubectl apply -f -

# 전체 서비스 배포
./scripts/deploy.sh
```

### 새로운 환경 추가

1. `overlays/` 하위에 새 환경 디렉토리 생성
2. 각 서비스별 kustomization.yaml 작성
3. ArgoCD ApplicationSet에 새 환경 추가

## 📊 모니터링

### Prometheus + Grafana

- **Prometheus**: 메트릭 수집 및 저장
- **Grafana**: 시각화 대시보드

### 접근 방법

```bash
# Grafana 접속
kubectl port-forward -n dev-monitoring svc/grafana 3000:80

# Prometheus 접속
kubectl port-forward -n dev-monitoring svc/prometheus 9090:9090
```

### 주요 대시보드

- **클러스터 개요**: 전체 클러스터 상태
- **서비스별 메트릭**: 각 마이크로서비스 성능
- **인프라 모니터링**: 노드 및 파드 상태

## 🔧 트러블슈팅

### 일반적인 문제들

#### 1. ArgoCD Application 동기화 실패

```bash
# Application 상태 확인
argocd app get dev-user-service

# 수동 동기화
argocd app sync dev-user-service
```

#### 2. Sealed Secret 복호화 실패

```bash
# Sealed Secret Controller 상태 확인
kubectl get pods -n kube-system | grep sealed-secrets

# 새 시크릿 생성
./scripts/generate-sealed-secret.sh
```

#### 3. Kong Ingress 라우팅 문제

```bash
# Kong 상태 확인
kubectl get pods -n kong

# Ingress 리소스 확인
kubectl get ingress -A
```

### 로그 확인

```bash
# 서비스 로그 확인
kubectl logs -f deployment/user-service -n dev-user-service

# ArgoCD 로그 확인
kubectl logs -f deployment/argocd-application-controller -n argocd
```
