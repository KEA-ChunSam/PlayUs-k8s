<div align="center">
  <img width="80" alt="Logo_REAL" src="https://github.com/user-attachments/assets/3dc13b9c-c793-44e9-9e02-713abeb15d2a" />
  <h1>PlayUs Kubernetes Infrastructure</h1>
    <p><em>GitOps 기반으로 PlayUs MSA 서비스를 Kubernetes에 배포 및 관리합니다</em></p>
    <p>
        <img src="https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white" alt="Kubernetes"/>
        <img src="https://img.shields.io/badge/Kong-0B1E2D?style=for-the-badge&logo=kong&logoColor=white" alt="Kong"/>
        <img src="https://img.shields.io/badge/Helm-0F1689?style=for-the-badge&logo=helm&logoColor=white" alt="Helm"/>        <img src="https://img.shields.io/badge/ArgoCD-FD6D4E?style=for-the-badge&logo=argo&logoColor=white" alt="ArgoCD"/>
    </p>
    <p>
        <img src="https://img.shields.io/badge/구축기간-2025.05~06-26A69A?style=for-the-badge" alt="구축기간"/>
    </p>
</div>

<br>

### 아키텍처 요약

PlayUs는 다음과 같은 마이크로서비스로 구성됩니다.

- **user-service**: 사용자 관리 서비스
- **community-service**: 커뮤니티 및 게시판 서비스
- **search-service**: 검색 기능 서비스
- **twp-service**: 직관팟 기능 서비스

### 기술 스택
- **Orchestration**: Kubernetes
- **Configuration Management**: Kustomize, Helm
- **GitOps Delivery**: ArgoCD
- **API Gateway**: Kong Ingress Controller
- **Secret Management**: Sealed Secrets
- **Monitoring**: LGTM Stack

<br>

### 🚀 빠른 시작

**전체 초기 배포**

```bash
./deploy-all.sh
```
**수동 배포**

```bash
# 특정 서비스만 배포 (예: user-service)
kustomize build overlays/develop/user-service | kubectl apply -f -
```

**Sealed Secrets 참고**

시크릿을 안전하게 관리하기 위해 Bitnami의 Sealed Secrets를 사용합니다.<br>
자세한 내용은 [공식 저장소](https://github.com/bitnami-labs/sealed-secrets.git)를 참고하세요.
