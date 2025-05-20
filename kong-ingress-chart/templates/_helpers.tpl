{{/*
Ingress 이름 생성
*/}}
{{- define "kong-ingress.name" -}}
{{- printf "%s-ingress" .Values.service.name }}
{{- end }}
