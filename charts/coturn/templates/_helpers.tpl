{{- define "coturn.name" -}}
coturn
{{- end }}

{{- define "coturn.fullname" -}}
{{ include "coturn.name" . }}
{{- end }}
