# 클러스터 인증서 생성 스크립트
#!/bin/bash
# scripts/generate-kong-certs.sh

openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
    -keyout cluster.key -out cluster.crt \
    -days 1095 -subj "/CN=kong_clustering"

kubectl create secret tls kong-cluster-cert \
    --cert=cluster.crt \
    --key=cluster.key \
    -n msa-dev
