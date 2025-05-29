{{/*
Ingress 이름 생성 (서비스 이름 기반)
*/}}
{{- define "kong-ingress.name" -}}
{{- printf "%s-ingress" .Values.service.name -}}
{{- end -}}
