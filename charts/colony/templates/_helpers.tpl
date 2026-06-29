

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
app.kubernetes.io/version: {{ include "colony.imageTag" . | quote }}
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
{{- (sha256sum (include "colony.imageTag" .)) | trunc 8 -}}
{{- end -}}

{{/*
Image tag (defaults to Chart.AppVersion if not set)
*/}}
{{- define "colony.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end -}}
{{/* Build and validate a canonical OAuth resource audience. */}}
{{- define "colony.oauthAudience" -}}
{{- $base := include "colony.oauthAudienceBaseURL" .base -}}
{{- $path := required "an OAuth audience resource path is required" .path -}}
{{- if not (regexMatch "^/[A-Za-z0-9._~-]+(/[A-Za-z0-9._~-]+)*$" $path) -}}
{{- fail "OAuth audience resource paths must be canonical absolute paths without a trailing slash" -}}
{{- end -}}
{{- printf "%s%s" $base $path -}}
{{- end -}}

{{/* Validate the configurable canonical OAuth audience base URL. */}}
{{- define "colony.oauthAudienceBaseURL" -}}
{{- $base := required "oauth2.audienceBaseURL is required when oauth2 is enabled" . -}}
{{- if not (regexMatch "^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(/[A-Za-z0-9._~-]+)*$" $base) -}}
{{- fail "oauth2.audienceBaseURL must be a canonical HTTPS URL without user info, port, query, fragment, or trailing slash" -}}
{{- end -}}
{{- $base -}}
{{- end -}}

{{/* Validate the exact OAuth token endpoint used for private_key_jwt assertions. */}}
{{- define "colony.oauthClientAssertionAudience" -}}
{{- $audience := required "oauth2.clientAssertionAudience is required when oauth2 is enabled" . -}}
{{- if not (regexMatch "^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(/[A-Za-z0-9._~-]+)+$" $audience) -}}
{{- fail "oauth2.clientAssertionAudience must be a canonical HTTPS endpoint without user info, port, query, fragment, or trailing slash" -}}
{{- end -}}
{{- $audience -}}
{{- end -}}
