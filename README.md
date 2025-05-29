# PlayUs Kubernetes 배포 환경

이 리포지토리는 PlayUs 서비스의 Kubernetes 배포 환경을 관리합니다. GitOps 방식으로 ArgoCD를 사용하여 자동화된 배포를 구현하고 있습니다.

## 프로젝트 구조

```
.
├── argocd/              # ArgoCD 애플리케이션 정의
├── base/                # 기본 Kubernetes 매니페스트
│   ├── community-service/
│   ├── match-service/
│   ├── monitoring/
│   ├── search-service/
│   ├── twp-service/
│   └── user-service/
├── kong-ingress-chart/ # Kong Ingress Controller 설정
├── manifests/          # 공통 매니페스트
├── overlays/           # 환경별 오버레이 설정
│   └── develop/        # 개발 환경 설정
├── scripts/            # 유틸리티 스크립트
└── shared/             # 공유 리소스
```

## 주요 컴포넌트

- **ArgoCD**: GitOps 기반의 지속적 배포 도구
- **Kong Ingress Controller**: API 게이트웨이 및 인그레스 컨트롤러
- **Kustomize**: Kubernetes 리소스 커스터마이징 도구

## 환경

현재 지원되는 환경:
- 개발 환경 (develop)

## 시작하기

### 사전 요구사항

- kubectl
- kustomize
- argocd CLI
- helm

### 개발 환경 설정

1. ArgoCD 설치 및 접속:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

2. ArgoCD 애플리케이션 배포:
```bash
kubectl apply -f argocd/dev-applicationset.yaml
```

3. 네임스페이스 생성:
```bash
kubectl apply -f argocd/dev-namespaces.yaml
```

## 모니터링

모니터링은 Prometheus와 Grafana를 사용하여 구성되어 있으며, `base/monitoring` 디렉토리에서 설정을 관리합니다.

## 배포 프로세스

1. 코드 변경사항을 main 브랜치에 머지
2. ArgoCD가 변경사항을 감지하고 자동으로 배포
3. ArgoCD 대시보드에서 배포 상태 확인
