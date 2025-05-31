# 실행 권한 부여: chmod +x deploy-kong.sh
# 개발 환경 실행: ./deploy-kong.sh dev
# 운영 환경 실행: ./deploy-kong.sh prod

#!/bin/bash

ENV=$1  # "develop" 또는 "production"

if [[ "$ENV" == "develop" ]]; then
  echo "🚧 Deploying Kong for DEV environment..."
  helm upgrade --install ingress-kong kong/kong \
    --namespace dev-gateway \
    --create-namespace \
    --set ingressController.enabled=true \
    --set ingressController.watchNamespace="" \
    --set env.database=postgres \
    --set postgresql.enabled=true \
    --set postgresql.auth.username=kong \
    --set postgresql.auth.password=kong \
    --set postgresql.auth.database=kong \
    --set env.pg_user=kong \
    --set env.pg_password=kong \
    --set env.pg_database=kong \
    --set proxy.type=LoadBalancer

elif [[ "$ENV" == "production" ]]; then
  echo "🚀 Deploying Kong for PROD environment..."
  helm upgrade --install ingress-kong kong/kong \
    --namespace prod-gateway \
    --create-namespace \
    --set ingressController.enabled=true \
    --set ingressController.watchNamespace="" \
    --set env.database=postgres \
    --set postgresql.enabled=false \
    --set env.pg_host=postgres-kong.prod-db.svc.cluster.local \
    --set env.pg_user=kong \
    --set env.pg_password=kong \
    --set env.pg_database=kong \
    --set proxy.type=LoadBalancer

else
  echo "❌ Unknown environment: $ENV"
  echo "Usage: ./deploy-kong.sh dev|prod"
  exit 1
fi
