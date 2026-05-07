{{/*
Chart name and version label.
*/}}
{{- define "scalar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Image tag (defaults to Chart.AppVersion if not set).
*/}}
{{- define "scalar.imageTag" -}}
{{- default .Chart.AppVersion .Values.image.tag -}}
{{- end -}}

{{/*
Image reference: prefers digest if set, falls back to tag.
*/}}
{{- define "scalar.imageRef" -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest -}}
{{- else -}}
{{- printf "%s:%s" .Values.image.repository (include "scalar.imageTag" .) -}}
{{- end -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "scalar.labels" -}}
helm.sh/chart: {{ include "scalar.chart" . }}
app.kubernetes.io/name: {{ default .Release.Name .Values.service.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ include "scalar.imageTag" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: api-documentation
{{- end }}

{{/*
Selector labels (must remain stable across upgrades).
*/}}
{{- define "scalar.selectorLabels" -}}
app.kubernetes.io/name: {{ default .Release.Name .Values.service.name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service name (defaults to Release.Name; override allows preserving "service-api" for HTTPRoute back-compat).
*/}}
{{- define "scalar.serviceName" -}}
{{- default .Release.Name .Values.service.name -}}
{{- end -}}

{{/*
Render the API_REFERENCE_CONFIG JSON for a given context. If a tenant is passed
via .tenant, its overrides are merged. Returns a single-line JSON string.
Validates tenant.sourcesFilter slugs exist in .Values.sources; fails otherwise.
*/}}
{{- define "scalar.renderConfig" -}}
{{- $values := .Values -}}
{{- $tenant := .tenant | default dict -}}
{{- $base := dict
  "theme"       $values.theme
  "layout"      $values.layout
  "darkMode"    $values.darkMode
  "showSidebar" (default true (dig "showSidebar" true $values.customization))
  "hideModels"  (default false (dig "hideModels" false $values.customization))
  "hideSearch"  (default false (dig "hideSearch" false $values.customization))
  "persistAuth" (default true (dig "persistAuth" true $values.customization))
  "defaultOpenAllTags" (default false (dig "defaultOpenAllTags" false $values.customization))
  "expandAllResponses" (default false (dig "expandAllResponses" false $values.customization))
  "hiddenClients" (default (list) (dig "hiddenClients" (list) $values.customization))
  "tagsSorter" (default "alpha" (dig "tagsSorter" "alpha" $values.customization))
  "operationsSorter" (default "method" (dig "operationsSorter" "method" $values.customization))
-}}
{{- /* Build set of available slugs for validation */ -}}
{{- $availableSlugs := list -}}
{{- range $values.sources -}}
  {{- $availableSlugs = append $availableSlugs .slug -}}
{{- end -}}
{{- /* Apply tenant overrides */ -}}
{{- $sources := $values.sources -}}
{{- with $tenant.sourcesFilter -}}
  {{- $allowed := . -}}
  {{- /* Validate each filtered slug exists */ -}}
  {{- range $allowed -}}
    {{- if not (has . $availableSlugs) -}}
      {{- fail (printf "tenant sourcesFilter references unknown source slug '%s'" .) -}}
    {{- end -}}
  {{- end -}}
  {{- /* Filter sources to only those allowed */ -}}
  {{- $filtered := list -}}
  {{- range $values.sources -}}
    {{- if has .slug $allowed -}}
      {{- $filtered = append $filtered . -}}
    {{- end -}}
  {{- end -}}
  {{- $sources = $filtered -}}
{{- end -}}
{{- if $tenant.theme -}}
  {{- $_ := set $base "theme" $tenant.theme -}}
{{- end -}}
{{- $_ := set $base "sources" $sources -}}
{{- $base | toJson -}}
{{- end -}}
