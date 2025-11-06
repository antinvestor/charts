{{/*
Expand the name of the chart.
*/}}
{{- define "colony.name" -}}
{{- .Values.serviceName | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "colony.fullname" -}}
{{- .Values.serviceName | default .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "colony.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "colony.labels" -}}
helm.sh/chart: {{ include "colony.chart" . }}
{{ include "colony.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "colony.selectorLabels" -}}
app.kubernetes.io/name: {{ include "colony.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Application service name
*/}}
{{- define "colony.serviceName" -}}
{{- .Values.opentelemetry.serviceName | default .Values.serviceName }}
{{- end }}

{{/*
OAuth2 JWT Verify Audience
*/}}
{{- define "colony.oauth2JwtAudience" -}}
{{- .Values.oauth2.jwtVerifyAudience | default (printf "service_%s" .Values.serviceName) }}
{{- end }}

{{/*
Gateway hostname
*/}}
{{- define "colony.gatewayHostname" -}}
{{- .Values.gateway.hostname | default (printf "%s.chamamobile.com" .Values.serviceName) }}
{{- end }}

{{/*
External DNS name
*/}}
{{- define "colony.externalDNSName" -}}
{{- .Values.externalDNS.dnsName | default (printf "%s.chamamobile.com" .Values.serviceName) }}
{{- end }}

{{/*
OAuth2 Secret Name - Consistent naming across deployments
*/}}
{{- define "colony.oauth2SecretName" -}}
{{- if .Values.oauth2.clientSecretRef.name }}
{{- .Values.oauth2.clientSecretRef.name }}
{{- else }}
{{- printf "%s-oauth2-secret" .Values.serviceName }}
{{- end }}
{{- end }}
