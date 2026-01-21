{{- define "stalwart.fullname" -}}
{{ .Release.Name }}-stalwart
{{- end }}

{{- define "stalwart.labels" -}}
app.kubernetes.io/name: stalwart
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: Helm
{{- end }}

{{- define "stalwart.selectorLabels" -}}
app.kubernetes.io/name: stalwart
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
