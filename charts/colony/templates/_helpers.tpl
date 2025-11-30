

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
{{- if .Values.image.tag }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
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
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{/*
ServiceAccount name
*/}}
{{- define "colony.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default .Release.Name .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image tag hash
*/}}
{{- define "colony.imageHash" -}}
{{- (sha256sum .Values.image.tag) | trunc 8 -}}
{{- end -}}