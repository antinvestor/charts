# Scalar API Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Swagger UI–based `service-api` with a Scalar deployment packaged as a reusable Helm chart, and retire `api.stawi.im` in favour of `api.antinvestor.com`.

**Architecture:** New `scalar` Helm chart at `~/code/antinvestor/charts/charts/scalar/` (extensible values surface for sources, theming, landing page, per-tenant overrides). New `HelmRelease` consumes the chart in `~/code/stawi.org/deployment.manifests/namespaces/gateway/unified-api/`, replacing raw Swagger UI manifests. Hostname swap is rolled out additively across ~22 service HelmReleases plus gateway-level routes/TLS/DNS, then `api.stawi.im` is retired after a 7-day soak.

**Tech Stack:** Helm v3, FluxCD HelmRelease, `scalarapi/api-reference` Docker image, Gateway API HTTPRoute, Cloudflare origin TLS, ExternalDNS, ExternalSecrets/Vault.

**Spec reference:** `docs/superpowers/specs/2026-05-07-scalar-api-docs-design.md`

**Repos touched:**
- `~/code/antinvestor/charts/` — chart development (Phase 0)
- `~/code/stawi.org/deployment.manifests/` — cluster migration (Phases 1–4)

---

## Phase 0 — Chart Development (in `antinvestor/charts`)

### Task 1: Scaffold chart skeleton

**Files:**
- Create: `charts/scalar/Chart.yaml`
- Create: `charts/scalar/values.yaml`
- Create: `charts/scalar/README.md`
- Create: `charts/scalar/.helmignore`

- [ ] **Step 1: Create `Chart.yaml`**

```yaml
apiVersion: v2
name: scalar
description: Scalar API Reference (multi-spec OpenAPI documentation) for the Antinvestor platform
type: application
icon: https://raw.githubusercontent.com/antinvestor/charts/main/charts/scalar/scalar.png
version: 0.1.0
appVersion: "latest"
keywords:
  - scalar
  - openapi
  - api-documentation
  - api-reference
maintainers:
  - name: Antinvestor Team
```

- [ ] **Step 2: Create `values.yaml`** — paste the canonical defaults from spec §4 verbatim. Source: `docs/superpowers/specs/2026-05-07-scalar-api-docs-design.md` §4.

- [ ] **Step 3: Create `.helmignore`**

```
.git/
.idea/
.vscode/
*.swp
*.bak
*.tmp
*.orig
.DS_Store
tests/
examples/
```

- [ ] **Step 4: Create `README.md`** with sections: Overview, Values reference (link to `values.yaml`), Examples (link to `examples/`), Migration from Swagger UI, Versioning. Don't gold-plate — 60–100 lines. Mirror Colony's README structure.

- [ ] **Step 5: Verify scaffolding with `helm lint`**

Run: `cd ~/code/antinvestor/charts/charts/scalar && helm lint .`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 6: Commit**

```bash
cd ~/code/antinvestor/charts
git add charts/scalar/
git commit -m "feat(scalar): scaffold chart skeleton"
```

### Task 2: Write `values.schema.json`

**Files:**
- Create: `charts/scalar/values.schema.json`

- [ ] **Step 1: Write the schema**

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "title": "Scalar Helm Chart Values",
  "type": "object",
  "required": ["image", "sources"],
  "additionalProperties": true,
  "properties": {
    "image": {
      "type": "object",
      "required": ["repository"],
      "properties": {
        "repository": { "type": "string", "minLength": 1 },
        "tag": { "type": "string" },
        "digest": { "type": "string", "pattern": "^(sha256:[a-f0-9]{64})?$" },
        "pullPolicy": { "type": "string", "enum": ["Always", "IfNotPresent", "Never"] }
      }
    },
    "replicas": { "type": "integer", "minimum": 1 },
    "service": {
      "type": "object",
      "properties": {
        "name": { "type": "string", "pattern": "^[a-z0-9-]+$" },
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 },
        "targetPort": { "type": "integer", "minimum": 1, "maximum": 65535 }
      }
    },
    "sources": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["slug", "title", "url"],
        "properties": {
          "slug":  { "type": "string", "pattern": "^[a-z0-9-]+$" },
          "title": { "type": "string", "minLength": 1 },
          "description": { "type": "string" },
          "icon": { "type": "string" },
          "group": { "type": "string", "pattern": "^[a-z0-9-]+$" },
          "url": { "type": "string", "pattern": "^(/[A-Za-z0-9._/-]*|https?://.+)$" },
          "default": { "type": "boolean" },
          "hidden": { "type": "boolean" }
        }
      }
    },
    "groups": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "required": ["label"],
        "properties": {
          "label": { "type": "string", "minLength": 1 },
          "order": { "type": "integer" },
          "color": { "type": "string", "pattern": "^#[0-9a-fA-F]{6}$" }
        }
      }
    },
    "theme":   { "type": "string", "enum": ["default", "moon", "purple", "solarized", "bluePlanet", "saturn", "kepler", "mars", "deepSpace", "laserwave"] },
    "layout":  { "type": "string", "enum": ["modern", "classic"] },
    "darkMode": { "type": "string", "enum": ["auto", "light", "dark", "force-light", "force-dark"] },
    "customCss": { "type": "string" },
    "customCssConfigMapRef": {
      "type": "object",
      "required": ["name", "key"],
      "properties": {
        "name": { "type": "string" },
        "key":  { "type": "string" }
      }
    },
    "landing": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "hero": {
          "type": "object",
          "properties": {
            "title":   { "type": "string" },
            "tagline": { "type": "string" }
          }
        },
        "cards": { "type": "array" }
      }
    },
    "customization": { "type": "object" },
    "tenants": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["hostname"],
        "properties": {
          "hostname": { "type": "string", "format": "hostname" },
          "theme":    { "type": "string" },
          "landing":  { "type": "object" },
          "sourcesFilter": {
            "type": "array",
            "items": { "type": "string", "pattern": "^[a-z0-9-]+$" }
          }
        }
      }
    },
    "agent": { "type": "object", "properties": { "enabled": { "type": "boolean" } } },
    "mcp":   { "type": "object", "properties": { "enabled": { "type": "boolean" } } },
    "hpa": { "type": "object" },
    "pdb": { "type": "object" },
    "networkPolicy": { "type": "object" },
    "observability": { "type": "object" },
    "gateway": { "type": "object" }
  }
}
```

- [ ] **Step 2: Re-run `helm lint` to confirm schema parses**

Run: `cd ~/code/antinvestor/charts/charts/scalar && helm lint .`
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 3: Commit**

```bash
git add charts/scalar/values.schema.json
git commit -m "feat(scalar): add values.schema.json"
```

### Task 3: Write `_helpers.tpl`

**Files:**
- Create: `charts/scalar/templates/_helpers.tpl`

- [ ] **Step 1: Write helpers**

```yaml
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
in `.tenant`, its overrides are merged. Returns a single-line JSON string.
*/}}
{{- define "scalar.renderConfig" -}}
{{- $base := dict
  "theme"       .Values.theme
  "layout"      .Values.layout
  "darkMode"    .Values.darkMode
  "showSidebar" (default true (dig "showSidebar" true .Values.customization))
  "hideModels"  (default false (dig "hideModels" false .Values.customization))
  "hideSearch"  (default false (dig "hideSearch" false .Values.customization))
  "persistAuth" (default true (dig "persistAuth" true .Values.customization))
  "defaultOpenAllTags" (default false (dig "defaultOpenAllTags" false .Values.customization))
  "expandAllResponses" (default false (dig "expandAllResponses" false .Values.customization))
  "hiddenClients" (default (list) (dig "hiddenClients" (list) .Values.customization))
  "tagsSorter" (default "alpha" (dig "tagsSorter" "alpha" .Values.customization))
  "operationsSorter" (default "method" (dig "operationsSorter" "method" .Values.customization))
-}}
{{- /* sources filter for tenants */ -}}
{{- $sources := .Values.sources -}}
{{- with .tenant -}}
  {{- with .sourcesFilter -}}
    {{- $allowed := . -}}
    {{- $sources = $.Values.sources | toJson | fromJson -}}
    {{- $filtered := list -}}
    {{- range $sources -}}
      {{- if has .slug $allowed -}}
        {{- $filtered = append $filtered . -}}
      {{- end -}}
    {{- end -}}
    {{- $sources = $filtered -}}
  {{- end -}}
  {{- if .theme }}{{- $_ := set $base "theme" .theme -}}{{- end -}}
{{- end -}}
{{- $_ := set $base "sources" $sources -}}
{{- $base | toJson -}}
{{- end -}}
```

- [ ] **Step 2: Validate `_helpers.tpl` parses**

Run: `cd ~/code/antinvestor/charts/charts/scalar && helm template smoke . -f values.yaml --set sources[0].slug=test --set sources[0].title=Test --set sources[0].url=/test/swagger.json 2>&1 | head -5`
Expected: Output begins with `---` or a Kubernetes manifest header (the helpers parse). If you see a Go template error, fix it.

- [ ] **Step 3: Commit**

```bash
git add charts/scalar/templates/_helpers.tpl
git commit -m "feat(scalar): add template helpers (labels, image ref, config renderer)"
```

### Task 4: Write `configmap-config.yaml`

**Files:**
- Create: `charts/scalar/templates/configmap-config.yaml`

- [ ] **Step 1: Write the template**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
data:
  {{/* Default config (used when tenants[] is empty or for non-matched hostnames) */}}
  config.json: |
    {{ include "scalar.renderConfig" (dict "Values" .Values "tenant" dict) }}
  {{- range .Values.tenants }}
  {{ printf "config.%s.json" .hostname }}: |
    {{ include "scalar.renderConfig" (dict "Values" $.Values "tenant" .) }}
  {{- end }}
```

- [ ] **Step 2: Add a smoke test value file** — Create `charts/scalar/tests/fixtures/smoke-values.yaml`:

```yaml
sources:
  - slug: profile
    title: Profile API
    url: /profile/swagger.json
    default: true
  - slug: files
    title: Files API
    url: /files/swagger.json
theme: purple
```

- [ ] **Step 3: Render and verify the ConfigMap content**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/configmap-config.yaml | yq '.data."config.json"' | jq -e '.sources | length == 2'`
Expected: `true` printed (jq exits 0).

- [ ] **Step 4: Commit**

```bash
git add charts/scalar/templates/configmap-config.yaml charts/scalar/tests/fixtures/smoke-values.yaml
git commit -m "feat(scalar): render API_REFERENCE_CONFIG into ConfigMap"
```

### Task 5: Write `configmap-css.yaml`

**Files:**
- Create: `charts/scalar/templates/configmap-css.yaml`

- [ ] **Step 1: Write the template**

```yaml
{{- if and .Values.customCss (not .Values.customCssConfigMapRef) -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-css
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
data:
  custom.css: |
{{ .Values.customCss | indent 4 }}
{{- end -}}
```

- [ ] **Step 2: Verify rendering — inline customCss case**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --set 'customCss=:root { --x: 1; }' --show-only templates/configmap-css.yaml | yq '.kind'`
Expected: `ConfigMap`

- [ ] **Step 3: Verify rendering — external ref case (template should NOT render)**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --set customCssConfigMapRef.name=external --set customCssConfigMapRef.key=custom.css --show-only templates/configmap-css.yaml`
Expected: empty output (no resource rendered)

- [ ] **Step 4: Commit**

```bash
git add charts/scalar/templates/configmap-css.yaml
git commit -m "feat(scalar): conditionally render inline customCss ConfigMap"
```

### Task 6: Write `configmap-landing.yaml`

**Files:**
- Create: `charts/scalar/templates/configmap-landing.yaml`

- [ ] **Step 1: Write the template** — renders a deterministic landing HTML from `.Values.landing`. Auto-generates cards from `sources[]` when `landing.cards` is empty.

```yaml
{{- if .Values.landing.enabled -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-landing
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
data:
  landing.html: |
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <title>{{ .Values.landing.hero.title | default "API Documentation" }}</title>
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      {{- if or .Values.customCss .Values.customCssConfigMapRef }}
      <link rel="stylesheet" href="/styles/custom.css" />
      {{- end }}
    </head>
    <body>
      <header class="hero">
        <h1>{{ .Values.landing.hero.title | default "API Documentation" }}</h1>
        <p>{{ .Values.landing.hero.tagline | default "" }}</p>
      </header>
      <main class="catalog">
        {{- $cards := .Values.landing.cards }}
        {{- if not $cards }}
          {{- $cards = list }}
          {{- range .Values.sources }}
            {{- if not .hidden }}
              {{- $cards = append $cards (dict "slug" .slug "title" .title "description" (.description | default "") "group" (.group | default "")) }}
            {{- end }}
          {{- end }}
        {{- end }}
        {{- range $cards }}
        <a class="card" href="#{{ .slug }}">
          <h3>{{ .title }}</h3>
          <p>{{ .description }}</p>
        </a>
        {{- end }}
      </main>
      <div id="scalar-app"></div>
      <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
      <script>
        Scalar.createApiReference('#scalar-app', { configurationUrl: '/configs/config.json' });
      </script>
    </body>
    </html>
{{- end -}}
```

- [ ] **Step 2: Verify rendering**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/configmap-landing.yaml | grep -c '<a class="card"'`
Expected: `2` (one card per source)

- [ ] **Step 3: Commit**

```bash
git add charts/scalar/templates/configmap-landing.yaml
git commit -m "feat(scalar): render structured landing HTML from values"
```

### Task 7: Write `serviceaccount.yaml`

**Files:**
- Create: `charts/scalar/templates/serviceaccount.yaml`

- [ ] **Step 1: Write the template**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
automountServiceAccountToken: false
```

- [ ] **Step 2: Verify**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/serviceaccount.yaml | yq '.automountServiceAccountToken'`
Expected: `false`

- [ ] **Step 3: Commit**

```bash
git add charts/scalar/templates/serviceaccount.yaml
git commit -m "feat(scalar): add ServiceAccount with token automount disabled"
```

### Task 8: Write `service.yaml`

**Files:**
- Create: `charts/scalar/templates/service.yaml`

- [ ] **Step 1: Write the template**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "scalar.serviceName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  ports:
    - name: http
      port: {{ .Values.service.port | default 80 }}
      targetPort: {{ .Values.service.targetPort | default 8080 }}
      protocol: TCP
  selector:
    {{- include "scalar.selectorLabels" . | nindent 4 }}
```

- [ ] **Step 2: Verify the service name override works**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --set service.name=service-api --show-only templates/service.yaml | yq '.metadata.name'`
Expected: `service-api`

- [ ] **Step 3: Commit**

```bash
git add charts/scalar/templates/service.yaml
git commit -m "feat(scalar): add Service with overridable name for HTTPRoute back-compat"
```

### Task 9: Write `deployment.yaml`

**Files:**
- Create: `charts/scalar/templates/deployment.yaml`

- [ ] **Step 1: Write the template**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
  annotations:
    configmap.reloader.stakater.com/reload: {{ printf "%s-config" .Release.Name }}{{ if and .Values.customCss (not .Values.customCssConfigMapRef) }},{{ printf "%s-css" .Release.Name }}{{ end }}{{ if .Values.landing.enabled }},{{ printf "%s-landing" .Release.Name }}{{ end }}
spec:
  replicas: {{ .Values.replicas | default 2 }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
  selector:
    matchLabels:
      {{- include "scalar.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "scalar.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ .Release.Name }}
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        runAsGroup: 101
        fsGroup: 101
        seccompProfile:
          type: RuntimeDefault
      {{- if .Values.tenants }}
      initContainers:
        - name: tenant-router-config
          image: busybox:1.36
          command:
            - sh
            - -c
            - |
              cat > /shared/host-router.conf <<'EOF'
              {{- range .Values.tenants }}
              if ($host = "{{ .hostname }}") {
                set $config_file "/configs/config.{{ .hostname }}.json";
              }
              {{- end }}
              EOF
          volumeMounts:
            - name: shared-config
              mountPath: /shared
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
      {{- end }}
      containers:
        - name: scalar
          image: {{ include "scalar.imageRef" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          ports:
            - name: http
              containerPort: {{ .Values.service.targetPort | default 8080 }}
              protocol: TCP
          env:
            - name: API_REFERENCE_CONFIG_FILE
              value: /configs/config.json
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
          volumeMounts:
            - name: configs
              mountPath: /configs
              readOnly: true
            {{- if .Values.landing.enabled }}
            - name: landing
              mountPath: /usr/share/nginx/html/index.html
              subPath: landing.html
              readOnly: true
            {{- end }}
            {{- if or .Values.customCss .Values.customCssConfigMapRef }}
            - name: css
              mountPath: /usr/share/nginx/html/styles
              readOnly: true
            {{- end }}
            - name: nginx-cache
              mountPath: /var/cache/nginx
            - name: nginx-tmp
              mountPath: /tmp
            {{- if .Values.tenants }}
            - name: shared-config
              mountPath: /etc/nginx/conf.d/host-router.conf
              subPath: host-router.conf
              readOnly: true
            {{- end }}
          livenessProbe:
            httpGet: { path: /, port: http }
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 3
          readinessProbe:
            httpGet: { path: /configs/config.json, port: http }
            periodSeconds: 5
            timeoutSeconds: 3
            failureThreshold: 3
          startupProbe:
            httpGet: { path: /, port: http }
            periodSeconds: 5
            failureThreshold: 30
      volumes:
        - name: configs
          configMap:
            name: {{ .Release.Name }}-config
        {{- if .Values.landing.enabled }}
        - name: landing
          configMap:
            name: {{ .Release.Name }}-landing
        {{- end }}
        {{- if .Values.customCss }}
        {{- if not .Values.customCssConfigMapRef }}
        - name: css
          configMap:
            name: {{ .Release.Name }}-css
        {{- end }}
        {{- end }}
        {{- with .Values.customCssConfigMapRef }}
        - name: css
          configMap:
            name: {{ .name }}
        {{- end }}
        - name: nginx-cache
          emptyDir: {}
        - name: nginx-tmp
          emptyDir: {}
        {{- if .Values.tenants }}
        - name: shared-config
          emptyDir: {}
        {{- end }}
```

- [ ] **Step 2: Verify the deployment renders**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/deployment.yaml | yq '.spec.template.spec.containers[0].image'`
Expected: `scalarapi/api-reference:latest`

- [ ] **Step 3: Verify the digest path**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --set image.digest=sha256:0000000000000000000000000000000000000000000000000000000000000000 --show-only templates/deployment.yaml | yq '.spec.template.spec.containers[0].image'`
Expected: `scalarapi/api-reference@sha256:0000000000000000000000000000000000000000000000000000000000000000`

- [ ] **Step 4: Commit**

```bash
git add charts/scalar/templates/deployment.yaml
git commit -m "feat(scalar): add Deployment with hardened security context and probes"
```

### Task 10: Write `hpa.yaml` and `pdb.yaml`

**Files:**
- Create: `charts/scalar/templates/hpa.yaml`
- Create: `charts/scalar/templates/pdb.yaml`

- [ ] **Step 1: Write `hpa.yaml`**

```yaml
{{- if .Values.hpa.enabled -}}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .Release.Name }}
  minReplicas: {{ .Values.hpa.minReplicas | default 2 }}
  maxReplicas: {{ .Values.hpa.maxReplicas | default 10 }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.hpa.targetCPUUtilizationPercentage | default 80 }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.hpa.targetMemoryUtilizationPercentage | default 80 }}
{{- end -}}
```

- [ ] **Step 2: Write `pdb.yaml`**

```yaml
{{- if .Values.pdb.enabled -}}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
spec:
  minAvailable: {{ .Values.pdb.minAvailable | default 1 }}
  selector:
    matchLabels:
      {{- include "scalar.selectorLabels" . | nindent 6 }}
{{- end -}}
```

- [ ] **Step 3: Verify**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/hpa.yaml | yq '.spec.minReplicas'`
Expected: `2`

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/pdb.yaml | yq '.spec.minAvailable'`
Expected: `1`

- [ ] **Step 4: Commit**

```bash
git add charts/scalar/templates/hpa.yaml charts/scalar/templates/pdb.yaml
git commit -m "feat(scalar): add HPA and PDB"
```

### Task 11: Write `networkpolicy.yaml`

**Files:**
- Create: `charts/scalar/templates/networkpolicy.yaml`

- [ ] **Step 1: Write the template**

```yaml
{{- if .Values.networkPolicy.enabled -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "scalar.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: gateway
      ports:
        - protocol: TCP
          port: {{ .Values.service.targetPort | default 8080 }}
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
{{- end -}}
```

- [ ] **Step 2: Verify**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/networkpolicy.yaml | yq '.spec.policyTypes'`
Expected: `["Ingress","Egress"]`

- [ ] **Step 3: Commit**

```bash
git add charts/scalar/templates/networkpolicy.yaml
git commit -m "feat(scalar): add NetworkPolicy (gateway ingress only, DNS egress)"
```

### Task 12: Write `httproute.yaml` (optional)

**Files:**
- Create: `charts/scalar/templates/httproute.yaml`

- [ ] **Step 1: Write the template**

```yaml
{{- if .Values.gateway.enabled -}}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
spec:
  parentRefs:
    - kind: Gateway
      name: {{ .Values.gateway.parentRef.name }}
      namespace: {{ .Values.gateway.parentRef.namespace }}
      sectionName: {{ .Values.gateway.parentRef.sectionName }}
  hostnames:
    {{- toYaml .Values.gateway.hostnames | nindent 4 }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.gateway.pathPrefix | default "/" }}
      filters:
        - type: CORS
          cors:
            allowOrigins:
              {{- toYaml .Values.gateway.cors.allowOrigins | nindent 14 }}
            allowMethods: [GET, OPTIONS]
            allowHeaders:
              - Authorization
              - Content-Type
              - Accept
              - Origin
              - X-Requested-With
              - X-Tenant-Id
              - X-Partition-Id
              - X-Access-Id
              - Connect-Protocol-Version
              - Connect-Timeout-Ms
              - Connect-Content-Encoding
              - Connect-Accept-Encoding
              - Grpc-Timeout
              - X-Grpc-Web
              - X-User-Agent
              - Baggage
              - Traceparent
              - Tracestate
            allowCredentials: true
            maxAge: 86400
      backendRefs:
        - kind: Service
          name: {{ include "scalar.serviceName" . }}
          port: {{ .Values.service.port | default 80 }}
          weight: 1
{{- end -}}
```

- [ ] **Step 2: Verify gateway disabled by default**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --show-only templates/httproute.yaml`
Expected: empty output (no resource).

- [ ] **Step 3: Verify gateway enabled path**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --set gateway.enabled=true --set 'gateway.hostnames[0]=test.example.com' --show-only templates/httproute.yaml | yq '.kind'`
Expected: `HTTPRoute`

- [ ] **Step 4: Commit**

```bash
git add charts/scalar/templates/httproute.yaml
git commit -m "feat(scalar): add optional self-owned HTTPRoute"
```

### Task 13: Write `prejob-validate.yaml`

**Files:**
- Create: `charts/scalar/templates/prejob-validate.yaml`
- Create: `charts/scalar/templates/networkpolicy-validate.yaml`
- Create: `charts/scalar/templates/serviceaccount-validate.yaml`

- [ ] **Step 1: Write the dedicated SA**

```yaml
{{- if .Values.preInstallValidation.enabled -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Release.Name }}-validate
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-10"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
automountServiceAccountToken: false
{{- end -}}
```

- [ ] **Step 2: Write the NetworkPolicy for the validation Job**

```yaml
{{- if .Values.preInstallValidation.enabled -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ .Release.Name }}-validate
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-9"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: scalar-validate
      app.kubernetes.io/instance: {{ .Release.Name }}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: gateway
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 443
{{- end -}}
```

- [ ] **Step 3: Write the validation Job**

```yaml
{{- if .Values.preInstallValidation.enabled -}}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-validate-{{ now | unixEpoch }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "scalar.labels" . | nindent 4 }}
    app.kubernetes.io/component: scalar-validate
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 300
  template:
    metadata:
      labels:
        app.kubernetes.io/component: scalar-validate
        app.kubernetes.io/instance: {{ .Release.Name }}
    spec:
      restartPolicy: Never
      serviceAccountName: {{ .Release.Name }}-validate
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: validate
          image: alpine/curl:8.6.0
          command:
            - sh
            - -ec
            - |
              # Validate JSON config syntax
              echo '{{ include "scalar.renderConfig" (dict "Values" .Values "tenant" dict) }}' \
                | sed 's/^[ ]*//' \
                | jq -e '.sources | length > 0' \
                || (echo "Rendered config has no sources"; exit 1)

              # Probe each source URL through the gateway
              GATEWAY_HOST="{{ .Values.preInstallValidation.gatewayHost }}"
              FAIL=0
              {{- range .Values.sources }}
              URL="https://${GATEWAY_HOST}{{ .url }}"
              CODE=$(curl -ks -o /dev/null -w '%{http_code}' --max-time 10 "${URL}")
              if [ "${CODE}" != "200" ]; then
                echo "FAIL ${URL} → HTTP ${CODE}"
                FAIL=1
              else
                echo "OK   ${URL}"
              fi
              {{- end }}
              exit ${FAIL}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests: { cpu: 10m, memory: 32Mi }
            limits:   { cpu: 200m, memory: 128Mi }
{{- end -}}
```

- [ ] **Step 4: Add validation knobs to `values.yaml`** at the end of the file:

```yaml
preInstallValidation:
  enabled: true
  gatewayHost: api.stawi.org
```

- [ ] **Step 5: Verify all three render with `enabled: true`**

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml | grep -c 'kind: Job'`
Expected: `1`

Run: `helm template smoke . -f tests/fixtures/smoke-values.yaml --set preInstallValidation.enabled=false | grep -c 'kind: Job'`
Expected: `0`

- [ ] **Step 6: Commit**

```bash
git add charts/scalar/templates/prejob-validate.yaml charts/scalar/templates/networkpolicy-validate.yaml charts/scalar/templates/serviceaccount-validate.yaml charts/scalar/values.yaml
git commit -m "feat(scalar): add pre-install validation hook (config + spec URL probes)"
```

### Task 14: Write `NOTES.txt`

**Files:**
- Create: `charts/scalar/templates/NOTES.txt`

- [ ] **Step 1: Write the template**

```text
Scalar API Reference {{ .Chart.Version }} (app: {{ include "scalar.imageTag" . }}) installed.

Service:        {{ include "scalar.serviceName" . }}.{{ .Release.Namespace }}.svc:{{ .Values.service.port | default 80 }}
Sources:        {{ len .Values.sources }} OpenAPI specs registered
Theme:          {{ .Values.theme }} ({{ .Values.layout }} layout)
Tenants:        {{ if .Values.tenants }}{{ len .Values.tenants }} per-host overrides{{ else }}none{{ end }}

Verify in cluster:
  kubectl -n {{ .Release.Namespace }} port-forward svc/{{ include "scalar.serviceName" . }} 8080:{{ .Values.service.port | default 80 }}
  curl -s http://localhost:8080/configs/config.json | jq '.sources | length'

Add a service to the catalog: append an entry to .Values.sources in your HelmRelease values.
```

- [ ] **Step 2: Commit**

```bash
git add charts/scalar/templates/NOTES.txt
git commit -m "feat(scalar): add NOTES.txt"
```

### Task 15: Write example values files

**Files:**
- Create: `charts/scalar/examples/minimal-values.yaml`
- Create: `charts/scalar/examples/full-extensible-values.yaml`
- Create: `charts/scalar/examples/per-tenant-values.yaml`

- [ ] **Step 1: Write `minimal-values.yaml`**

```yaml
sources:
  - slug: profile
    title: Profile API
    url: /profile/swagger.json
    default: true
  - slug: files
    title: Files API
    url: /files/swagger.json
```

- [ ] **Step 2: Write `full-extensible-values.yaml`** — full Antinvestor catalog reflecting current production sources, with groups and CSS overlay:

```yaml
service:
  name: service-api

theme: default
layout: modern

groups:
  identity:       { label: Identity,       order: 1, color: "#1976d2" }
  platform:       { label: Platform,       order: 2, color: "#10b981" }
  finance:        { label: Finance,        order: 3, color: "#f59e0b" }
  communications: { label: Communications, order: 4, color: "#7c3aed" }
  operations:     { label: Operations,     order: 5, color: "#64748b" }

sources:
  - { slug: profile,      group: identity,       title: "Profile API",      description: "User management & authentication",  url: /profile/swagger.json, default: true }
  - { slug: tenancy,      group: identity,       title: "Tenancy API",      description: "Multi-tenant org management",        url: /tenancy/swagger.json }
  - { slug: tenancy-keys, group: identity,       title: "Tenancy API Keys", description: "Client API key management",          url: /tenancy/api/key/swagger.json }
  - { slug: files,        group: platform,       title: "Files API",        description: "File management & storage",          url: /files/swagger.json }
  - { slug: devices,      group: platform,       title: "Devices API",      description: "Device registration & monitoring",   url: /devices/swagger.json }
  - { slug: settings,     group: platform,       title: "Settings API",     description: "Configuration & preferences",        url: /settings/swagger.json }
  - { slug: ledger,       group: finance,        title: "Ledger API",       description: "Financial transactions & accounting", url: /ledger/swagger.json }
  - { slug: payment,      group: finance,        title: "Payment API",      description: "Payment processing & gateways",      url: /payment/swagger.json }
  - { slug: notification, group: communications, title: "Notification API", description: "Push notifications & messaging",     url: /notification/swagger.json }

landing:
  enabled: true
  hero:
    title: "Antinvestor APIs"
    tagline: "APIs powering modern distributed financial systems"

customCss: |
  :root { --scalar-color-accent: #1976d2; }

customization:
  showSidebar: true
  persistAuth: true
  defaultOpenAllTags: false
  tagsSorter: alpha
  operationsSorter: method

preInstallValidation:
  enabled: true
  gatewayHost: api.stawi.org
```

- [ ] **Step 3: Write `per-tenant-values.yaml`** — extends full example with one tenant override:

```yaml
# Inherits from full-extensible-values.yaml; this file shows ONLY the additions.
# In actual deployments these would be merged into one HelmRelease values block.

tenants:
  - hostname: api.antinvestor.com
    theme: purple
    landing:
      hero:
        title: "Antinvestor Platform"
    sourcesFilter: [profile, tenancy, tenancy-keys, payment, ledger]
```

- [ ] **Step 4: Verify each example renders**

Run: `for f in examples/minimal-values.yaml examples/full-extensible-values.yaml; do helm template smoke . -f "$f" > /dev/null && echo "OK $f"; done`
Expected: `OK examples/minimal-values.yaml` and `OK examples/full-extensible-values.yaml`

- [ ] **Step 5: Commit**

```bash
git add charts/scalar/examples/
git commit -m "docs(scalar): add minimal, full-extensible, and per-tenant example values"
```

### Task 16: Add helm-unittest cases

**Files:**
- Create: `charts/scalar/tests/configmap-config_test.yaml`
- Create: `charts/scalar/tests/deployment_test.yaml`
- Create: `charts/scalar/tests/per-tenant_test.yaml`

- [ ] **Step 1: Write `configmap-config_test.yaml`**

```yaml
suite: ConfigMap config
templates:
  - templates/configmap-config.yaml
tests:
  - it: renders one config.json for default and per-tenant
    set:
      sources:
        - { slug: profile, title: Profile API, url: /profile/swagger.json, default: true }
      tenants:
        - { hostname: api.antinvestor.com, theme: purple }
    asserts:
      - equal:
          path: kind
          value: ConfigMap
      - exists:
          path: data["config.json"]
      - exists:
          path: data["config.api.antinvestor.com.json"]

  - it: includes only sources for tenant when sourcesFilter is set
    set:
      sources:
        - { slug: profile, title: Profile API, url: /profile/swagger.json }
        - { slug: files,   title: Files API,   url: /files/swagger.json }
      tenants:
        - { hostname: api.antinvestor.com, sourcesFilter: [files] }
    asserts:
      - matchRegex:
          path: data["config.api.antinvestor.com.json"]
          pattern: '"slug":"files"'
      - notMatchRegex:
          path: data["config.api.antinvestor.com.json"]
          pattern: '"slug":"profile"'
```

- [ ] **Step 2: Write `deployment_test.yaml`**

```yaml
suite: Deployment
templates:
  - templates/deployment.yaml
tests:
  - it: uses repository:tag when no digest
    set:
      sources: [{ slug: x, title: X, url: /x/swagger.json }]
    asserts:
      - matchRegex:
          path: spec.template.spec.containers[0].image
          pattern: '^scalarapi/api-reference:'

  - it: uses repository@digest when digest set
    set:
      sources: [{ slug: x, title: X, url: /x/swagger.json }]
      image:
        digest: sha256:0000000000000000000000000000000000000000000000000000000000000000
    asserts:
      - matchRegex:
          path: spec.template.spec.containers[0].image
          pattern: '^scalarapi/api-reference@sha256:'

  - it: renders init container when tenants present
    set:
      sources: [{ slug: x, title: X, url: /x/swagger.json }]
      tenants:
        - { hostname: api.antinvestor.com }
    asserts:
      - exists:
          path: spec.template.spec.initContainers[0]
      - equal:
          path: spec.template.spec.initContainers[0].name
          value: tenant-router-config

  - it: omits init container when no tenants
    set:
      sources: [{ slug: x, title: X, url: /x/swagger.json }]
    asserts:
      - notExists:
          path: spec.template.spec.initContainers
```

- [ ] **Step 3: Write `per-tenant_test.yaml`** ensuring the schema rejects unknown filtered slugs:

```yaml
suite: Schema rejection
templates:
  - templates/configmap-config.yaml
tests:
  - it: schema rejects sourcesFilter referencing unknown slug
    set:
      sources: [{ slug: known, title: Known, url: /known/swagger.json }]
      tenants:
        - { hostname: x.example.com, sourcesFilter: [unknown] }
    asserts:
      - failedTemplate:
          errorMessage: "tenant sourcesFilter references unknown source slug 'unknown'"
```

> Note: the failedTemplate assertion above requires that `_helpers.tpl` `scalar.renderConfig` actively validates filtered slugs against `.Values.sources` and `fail`s when an unknown slug is referenced. If the helper as written in Task 3 doesn't enforce this, add the validation in this task before Step 4 — replace the filter loop with one that calls `fail` on a missing slug.

- [ ] **Step 4: Run helm-unittest**

Run: `cd ~/code/antinvestor/charts/charts/scalar && helm unittest . -f 'tests/*_test.yaml'`
Expected: All assertions pass.

- [ ] **Step 5: Commit**

```bash
git add charts/scalar/tests/ charts/scalar/templates/_helpers.tpl
git commit -m "test(scalar): add helm-unittest cases for ConfigMap, Deployment, schema rejection"
```

### Task 17: Local end-to-end smoke (helm template + docker run)

**Files:**
- Create: `charts/scalar/scripts/smoke-local.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Rendering chart with full-extensible-values.yaml"
helm template smoke "$HERE" -f "$HERE/examples/full-extensible-values.yaml" > "$WORK/manifests.yaml"

echo "==> Extracting config.json"
yq '. | select(.kind == "ConfigMap" and (.metadata.name | test("-config$"))) | .data."config.json"' \
  "$WORK/manifests.yaml" | jq -e '.sources | length > 0' > /dev/null
echo "    config.json valid"

echo "==> Running scalarapi/api-reference container with rendered config"
yq '. | select(.kind == "ConfigMap" and (.metadata.name | test("-config$"))) | .data."config.json"' \
  "$WORK/manifests.yaml" > "$WORK/config.json"

CID=$(docker run -d --rm \
  -v "$WORK/config.json:/configs/config.json:ro" \
  -e API_REFERENCE_CONFIG_FILE=/configs/config.json \
  -p 18080:8080 \
  scalarapi/api-reference:latest)
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

# Wait for nginx to come up
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf http://localhost:18080/configs/config.json > /dev/null; then
    break
  fi
  sleep 1
done

CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:18080/)
[ "$CODE" = "200" ] || { echo "Scalar / returned $CODE"; exit 1; }
echo "==> OK — Scalar serves rendered config locally"
```

- [ ] **Step 2: Make executable and run**

```bash
chmod +x charts/scalar/scripts/smoke-local.sh
./charts/scalar/scripts/smoke-local.sh
```
Expected: ends with `==> OK — Scalar serves rendered config locally`

- [ ] **Step 3: Commit**

```bash
git add charts/scalar/scripts/smoke-local.sh
git commit -m "test(scalar): add local docker-based smoke test script"
```

### Task 18: Tag and publish chart v0.1.0

- [ ] **Step 1: Bump version if needed** — `Chart.yaml` already at `0.1.0`. No action.

- [ ] **Step 2: Verify chart packages cleanly**

Run: `helm package charts/scalar -d /tmp/`
Expected: `Successfully packaged chart and saved it to: /tmp/scalar-0.1.0.tgz`

- [ ] **Step 3: Push to main and let the existing release CI publish to the antinvestor HelmRepository.**

```bash
git push origin main
```
Wait for CI to publish. Verify: `helm repo update && helm search repo antinvestor/scalar --versions`
Expected: `antinvestor/scalar 0.1.0` listed.

---

## Phase 1 — Provision `api.antinvestor.com` infra (in `stawi.org/deployment.manifests`)

### Task 19: Provision Cloudflare origin cert in Vault (out of band)

**Files:** None in this repo — Vault path: `antinvestor/gateway/tls/cf-antinvestor-com-origin`

- [ ] **Step 1: Generate origin cert in Cloudflare dashboard** for `*.antinvestor.com` and `antinvestor.com`. Download the cert and key.

- [ ] **Step 2: Stash in Vault**

```bash
vault kv put antinvestor/gateway/tls/cf-antinvestor-com-origin \
  tls.crt=@/path/to/origin.pem \
  tls.key=@/path/to/origin.key
```

- [ ] **Step 3: Verify ESO can read it**

```bash
kubectl -n gateway create job --from=cronjob/eso-debug eso-test-antinvestor || \
  vault kv get antinvestor/gateway/tls/cf-antinvestor-com-origin > /dev/null && echo OK
```
Expected: `OK`

(No commit — Vault changes are operational, not tracked here.)

### Task 20: Add `tls-antinvestor-com.yaml` ExternalSecret

**Files:**
- Create: `namespaces/gateway/gateway-config/tls-antinvestor-com.yaml`

- [ ] **Step 1: Write the file** — modeled byte-for-byte on `tls-stawi-im.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cf-antinvestor-com-origin
  namespace: gateway
type: kubernetes.io/tls
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: cf-antinvestor-com-origin
  namespace: gateway
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: vault-backend
  target:
    name: cf-antinvestor-com-origin
    creationPolicy: Merge
  data:
    - secretKey: tls.crt
      remoteRef:
        key: antinvestor/gateway/tls/cf-antinvestor-com-origin
        property: tls.crt
    - secretKey: tls.key
      remoteRef:
        key: antinvestor/gateway/tls/cf-antinvestor-com-origin
        property: tls.key
```

- [ ] **Step 2: Add to `gateway-config/kustomization.yaml`**

In `namespaces/gateway/gateway-config/kustomization.yaml`, add `- tls-antinvestor-com.yaml` to the `resources:` list (preserve alphabetical order).

- [ ] **Step 3: Commit**

```bash
cd ~/code/stawi.org/deployment.manifests
git add namespaces/gateway/gateway-config/tls-antinvestor-com.yaml namespaces/gateway/gateway-config/kustomization.yaml
git commit -m "feat(gateway): add TLS ExternalSecret for api.antinvestor.com"
```

### Task 21: Add gateway listener for `api.antinvestor.com`

**Files:**
- Modify: `namespaces/gateway/gateway-config/gateway.yaml`

- [ ] **Step 1: Read the existing `cf-stawi-im-origin` listener block.**

Run: `grep -n "cf-stawi-im-origin" namespaces/gateway/gateway-config/gateway.yaml`

- [ ] **Step 2: Duplicate the listener block** for `cf-antinvestor-com-origin`, right after the existing one. The new listener should have a unique `name` (e.g., `https-antinvestor-com`) and reference the new TLS secret. Do NOT remove the existing `cf-stawi-im-origin` listener.

Example shape (verify against actual file structure before editing):

```yaml
    - name: https-antinvestor-com
      protocol: HTTPS
      port: 443
      hostname: "*.antinvestor.com"
      tls:
        mode: Terminate
        certificateRefs:
          - name: cf-antinvestor-com-origin
      allowedRoutes:
        namespaces:
          from: All
```

- [ ] **Step 3: Verify gateway YAML is valid**

Run: `yq '.spec.listeners | length' namespaces/gateway/gateway-config/gateway.yaml`
Expected: integer count incremented by 1 from before.

- [ ] **Step 4: Commit**

```bash
git add namespaces/gateway/gateway-config/gateway.yaml
git commit -m "feat(gateway): add HTTPS listener for *.antinvestor.com"
```

### Task 22: Apply Phase 1, verify gate

- [ ] **Step 1: Push and let Flux reconcile**

```bash
git push
flux reconcile kustomization gateway-config -n flux-system --with-source
```

- [ ] **Step 2: Wait for the new Secret and gateway condition**

```bash
kubectl -n gateway get secret cf-antinvestor-com-origin
kubectl -n gateway get gateway default -o yaml | yq '.status.listeners[] | select(.name == "https-antinvestor-com")'
```
Expected: Secret type `kubernetes.io/tls` exists; listener condition `Programmed: True`.

- [ ] **Step 3: TLS handshake check**

```bash
echo | openssl s_client -connect api.antinvestor.com:443 -servername api.antinvestor.com 2>/dev/null | openssl x509 -noout -subject -issuer
```
Expected: subject mentions `*.antinvestor.com`, issuer is Cloudflare Origin CA. Note: returns 404 from the gateway is fine — we haven't added routes yet.

- [ ] **Step 4: GATE** — TLS valid AND gateway listener Programmed=True. Do not proceed to Phase 2 if either fails.

---

## Phase 2 — Add `api.antinvestor.com` to all routes (additive)

### Task 23: Add hostname to gateway-level routes

**Files:**
- Modify: `namespaces/gateway/unified-api/unified-api-core.yaml`
- Modify: `namespaces/gateway/unified-api/thesa-api.yaml`
- Modify: `namespaces/identity/common/auth-routes.yaml`

- [ ] **Step 1: For each file above, append `- "api.antinvestor.com"` to the `spec.hostnames` array.** Do NOT remove `api.stawi.im`.

- [ ] **Step 2: Verify**

Run:
```bash
for f in namespaces/gateway/unified-api/unified-api-core.yaml \
         namespaces/gateway/unified-api/thesa-api.yaml \
         namespaces/identity/common/auth-routes.yaml; do
  echo "=== $f ==="
  yq '.spec.hostnames // .spec.rules[].matches' "$f" | grep -E 'antinvestor.com|stawi.im' || true
done
```
Expected: every file shows both `api.stawi.im` and `api.antinvestor.com`.

- [ ] **Step 3: Commit**

```bash
git add namespaces/gateway/unified-api/unified-api-core.yaml namespaces/gateway/unified-api/thesa-api.yaml namespaces/identity/common/auth-routes.yaml
git commit -m "feat(gateway): add api.antinvestor.com to gateway-level HTTPRoutes"
```

### Task 24: Add hostname to all service HelmReleases

**Files (~22):**
- `namespaces/identity/authentication/service-authentication.yaml`
- `namespaces/identity/identity/service-identity.yaml`
- `namespaces/identity/profile/service-profile.yaml`
- `namespaces/identity/tenancy/service-tenancy.yaml`
- `namespaces/platform/devices/service-devices.yaml`
- `namespaces/platform/files/service-files.yaml`
- `namespaces/platform/geolocation/service-geolocation.yaml`
- `namespaces/platform/settings/service-settings.yaml`
- `namespaces/finance/finance-operations/service-operations.yaml`
- `namespaces/finance/funding/service-funding.yaml`
- `namespaces/finance/ledger/service-ledger.yaml`
- `namespaces/finance/loans/service-loans.yaml`
- `namespaces/finance/payment/service-payment.yaml`
- `namespaces/finance/savings/service-savings.yaml`
- `namespaces/finance/stawi-group/service-stawi.yaml`
- `namespaces/communications/notification/service-notification.yaml`
- `namespaces/operations/audit/service-audit.yaml`
- `namespaces/operations/formstore/operations-formstore.yaml`
- `namespaces/operations/queuestore/operations-queuestore.yaml`
- `namespaces/operations/redirect/service-redirect.yaml`
- `namespaces/product-opportunities/api/opportunities-api-gateway-api.yaml`
- `namespaces/product-opportunities/matching/opportunities-matching-gateway-api.yaml`

- [ ] **Step 1: Run the canonical mass-edit**

```bash
cd ~/code/stawi.org/deployment.manifests
FILES=$(grep -rl "api.stawi.im" namespaces/ | grep -E '\.(yaml|yml)$')
for f in $FILES; do
  # Insert "- api.antinvestor.com" line directly after every "- api.stawi.im" line
  # exactly once per file. Idempotent: skip if already present.
  if ! grep -q "api.antinvestor.com" "$f"; then
    sed -i '/- api\.stawi\.im/a\        - api.antinvestor.com' "$f"
  fi
done
```

> The exact indentation in the `sed` command (8 spaces above) matches the `gateway.hostnames` block format in service HelmReleases. If a file uses a different indentation (e.g., HTTPRoute `spec.hostnames` uses 4 spaces), the insertion may produce malformed YAML. Step 2 catches this.

- [ ] **Step 2: Validate every modified file is still valid YAML and contains both hostnames**

```bash
FAIL=0
for f in $FILES; do
  yq . "$f" > /dev/null || { echo "INVALID YAML: $f"; FAIL=1; }
  grep -q "api.stawi.im" "$f" && grep -q "api.antinvestor.com" "$f" || { echo "MISSING ENTRIES: $f"; FAIL=1; }
done
[ $FAIL -eq 0 ] && echo "ALL OK"
```
Expected: `ALL OK`. Fix any flagged files manually before commit.

- [ ] **Step 3: Commit**

```bash
git add namespaces/
git commit -m "feat: add api.antinvestor.com hostname alongside api.stawi.im across all services"
```

### Task 25: Apply Phase 2, verify dual-host gate

- [ ] **Step 1: Push and reconcile**

```bash
git push
flux reconcile kustomization namespaces -n flux-system
```

- [ ] **Step 2: Wait for HelmReleases to settle**

```bash
flux get helmreleases -A | grep -v 'True' || echo "ALL READY"
```
Expected: `ALL READY` (or rerun until all HelmReleases show Ready=True).

- [ ] **Step 3: Run dual-host probe across the catalog**

```bash
SLUGS="profile tenancy tenancy/api/key files devices settings ledger payment notification"
for slug in $SLUGS; do
  IM=$(curl -ks -o /dev/null -w '%{http_code}' "https://api.stawi.im/${slug}/swagger.json")
  AC=$(curl -ks -o /dev/null -w '%{http_code}' "https://api.antinvestor.com/${slug}/swagger.json")
  printf "%-25s stawi.im=%s antinvestor.com=%s\n" "$slug" "$IM" "$AC"
done
```
Expected: every line shows both columns equal `200`.

- [ ] **Step 4: GATE** — every slug returns 200 on both hostnames. Do not proceed to Phase 3 if any fails.

---

## Phase 3 — Cut Scalar in (replace `service-api`)

### Task 26: Replace raw `service-api.yaml` with HelmRelease

**Files:**
- Modify: `namespaces/gateway/unified-api/service-api.yaml` (full rewrite)
- Delete: `namespaces/gateway/unified-api/swagger-ui-config.yaml`
- Modify: `namespaces/gateway/unified-api/kustomization.yaml`

- [ ] **Step 1: Replace the contents of `service-api.yaml`**

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: service-api
  namespace: gateway
  labels:
    reconcile.fluxcd.io/watch: Enabled
spec:
  interval: 3h
  chart:
    spec:
      chart: scalar
      version: ">=0.1.0 <0.2.0"
      sourceRef:
        kind: HelmRepository
        name: antinvestor
        namespace: flux-system
      interval: 15m
  install:
    remediation:
      retries: 5
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
      remediateLastFailure: true
  values:
    service:
      name: service-api          # preserves existing HTTPRoute backendRef

    image:
      repository: scalarapi/api-reference
      tag: latest # {"$imagepolicy": "gateway:service-api:tag"}
      digest: ""  # {"$imagepolicy": "gateway:service-api:digest"}
      pullPolicy: IfNotPresent

    replicas: 2
    resources:
      requests: { cpu: 10m, memory: 80Mi }
      limits:   { cpu: 200m, memory: 400Mi }

    theme: default
    layout: modern

    groups:
      identity:       { label: Identity,       order: 1, color: "#1976d2" }
      platform:       { label: Platform,       order: 2, color: "#10b981" }
      finance:        { label: Finance,        order: 3, color: "#f59e0b" }
      communications: { label: Communications, order: 4, color: "#7c3aed" }
      operations:     { label: Operations,     order: 5, color: "#64748b" }

    sources:
      - { slug: profile,      group: identity,       title: "Profile API",      description: "User management & authentication", url: /profile/swagger.json, default: true }
      - { slug: tenancy,      group: identity,       title: "Tenancy API",      description: "Multi-tenant org management",       url: /tenancy/swagger.json }
      - { slug: tenancy-keys, group: identity,       title: "Tenancy API Keys", description: "Client API key management",         url: /tenancy/api/key/swagger.json }
      - { slug: files,        group: platform,       title: "Files API",        description: "File management & storage",         url: /files/swagger.json }
      - { slug: devices,      group: platform,       title: "Devices API",      description: "Device registration & monitoring",  url: /devices/swagger.json }
      - { slug: settings,     group: platform,       title: "Settings API",     description: "Configuration & preferences",       url: /settings/swagger.json }
      - { slug: ledger,       group: finance,        title: "Ledger API",       description: "Financial transactions & accounting", url: /ledger/swagger.json }
      - { slug: payment,      group: finance,        title: "Payment API",      description: "Payment processing & gateways",     url: /payment/swagger.json }
      - { slug: notification, group: communications, title: "Notification API", description: "Push notifications & messaging",    url: /notification/swagger.json }

    landing:
      enabled: true
      hero:
        title: "Antinvestor APIs"
        tagline: "APIs powering modern distributed financial systems"

    customCss: |
      :root { --scalar-color-accent: #1976d2; }

    preInstallValidation:
      enabled: true
      gatewayHost: api.stawi.org

    networkPolicy:
      enabled: true
    pdb:
      enabled: true
      minAvailable: 1
    hpa:
      enabled: true
      minReplicas: 2
      maxReplicas: 10
      targetCPUUtilizationPercentage: 80
      targetMemoryUtilizationPercentage: 80

---
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageRepository
metadata:
  name: service-api
  namespace: gateway
spec:
  image: scalarapi/api-reference
  interval: 5m0s
---
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImagePolicy
metadata:
  name: service-api
  namespace: gateway
spec:
  imageRepositoryRef:
    name: service-api
  policy:
    semver:
      range: ">=1.0.0"
```

- [ ] **Step 2: Delete `swagger-ui-config.yaml`**

```bash
rm namespaces/gateway/unified-api/swagger-ui-config.yaml
```

- [ ] **Step 3: Update `namespaces/gateway/unified-api/kustomization.yaml`** — remove the `- swagger-ui-config.yaml` line. The `- service-api.yaml` line stays.

- [ ] **Step 4: Verify `unified-api-core.yaml` HTTPRoute is unchanged** — its `backendRef.name` should still be `service-api`.

```bash
yq '.spec.rules[].backendRefs[].name' namespaces/gateway/unified-api/unified-api-core.yaml
```
Expected: `service-api`

- [ ] **Step 5: Commit**

```bash
git add namespaces/gateway/unified-api/
git commit -m "feat(gateway): replace Swagger UI service-api with Scalar HelmRelease"
```

### Task 27: Apply Phase 3, verify Scalar gate

- [ ] **Step 1: Push and reconcile**

```bash
git push
flux reconcile helmrelease service-api -n gateway
```

- [ ] **Step 2: Watch the rollout**

```bash
kubectl -n gateway rollout status deploy/service-api --timeout=5m
flux get helmrelease service-api -n gateway
```
Expected: deployment available; HelmRelease Ready=True.

- [ ] **Step 3: Verify the pre-install validation Job ran successfully**

```bash
kubectl -n gateway get jobs -l app.kubernetes.io/component=scalar-validate
kubectl -n gateway logs job/$(kubectl -n gateway get job -l app.kubernetes.io/component=scalar-validate -o name | head -1) | tail -20
```
Expected: Job Status=Complete; logs show every source URL returning HTTP 200.

- [ ] **Step 4: Confirm Scalar serves on all three hostnames**

```bash
for host in api.stawi.org api.stawi.dev api.antinvestor.com; do
  CODE=$(curl -ks -o /dev/null -w '%{http_code}' "https://${host}/")
  GREP=$(curl -ks "https://${host}/" | grep -c 'scalar-app')
  printf "%-22s code=%s scalar-app=%s\n" "$host" "$CODE" "$GREP"
done
```
Expected: every line shows `code=200 scalar-app=1` (or higher).

- [ ] **Step 5: Confirm catalog entries are reachable through the new shell**

```bash
curl -ks https://api.stawi.org/configs/config.json | jq '.sources[].url' | head
```
Expected: list of `/profile/swagger.json`, `/files/swagger.json`, etc.

- [ ] **Step 6: GATE** — All checks above pass. If any fail, run `git revert HEAD; git push` to roll back; debug separately. Do not proceed.

### Task 28: Soak window (no actions, observe only)

- [ ] **Step 1: Set a calendar reminder for 7 days from Phase 3 deploy timestamp** to revisit Phase 4.

- [ ] **Step 2: During soak, confirm:**
  - No 5xx spike on `service-api` Pods (Grafana → existing kube-state-metrics dashboard).
  - No client-side breakage reports (admin consoles, SDK consumers).
  - Synthetic uptime probe shows 100% for `api.antinvestor.com` and unchanged for `api.stawi.org`/`api.stawi.dev`.
  - Gateway access log shows declining `api.stawi.im` traffic.

If any of the above fails, abort Phase 4 and investigate.

---

## Phase 4 — Retire `api.stawi.im` (subtractive, after soak)

### Task 29: Remove `api.stawi.im` from all hostnames

**Files:** the same ~25 files modified in Tasks 23–24.

- [ ] **Step 1: Mass-remove the line**

```bash
cd ~/code/stawi.org/deployment.manifests
FILES=$(grep -rl 'api\.stawi\.im' namespaces/ | grep -E '\.(yaml|yml)$')
for f in $FILES; do
  sed -i '/^[[:space:]]*-[[:space:]]*"\?api\.stawi\.im"\?[[:space:]]*$/d' "$f"
done
```

- [ ] **Step 2: Verify**

```bash
grep -rln 'api\.stawi\.im' namespaces/
```
Expected: no output (no remaining references).

```bash
for f in $FILES; do yq . "$f" > /dev/null || echo "INVALID: $f"; done
```
Expected: no output (every file is valid YAML).

- [ ] **Step 3: Commit**

```bash
git add namespaces/
git commit -m "chore: retire api.stawi.im from all gateway routes and service hostnames"
```

### Task 30: Delete `api.stawi.im` TLS, DNS, and listener

**Files:**
- Delete: `namespaces/gateway/unified-api/unified-api-dns-stawi-im.yaml`
- Delete: `namespaces/gateway/gateway-config/tls-stawi-im.yaml`
- Modify: `namespaces/gateway/unified-api/kustomization.yaml`
- Modify: `namespaces/gateway/gateway-config/kustomization.yaml`
- Modify: `namespaces/gateway/gateway-config/gateway.yaml`

- [ ] **Step 1: Delete the files**

```bash
rm namespaces/gateway/unified-api/unified-api-dns-stawi-im.yaml \
   namespaces/gateway/gateway-config/tls-stawi-im.yaml
```

- [ ] **Step 2: Remove their entries from the two kustomization files** — drop the `- unified-api-dns-stawi-im.yaml` line from `unified-api/kustomization.yaml` and `- tls-stawi-im.yaml` from `gateway-config/kustomization.yaml`.

- [ ] **Step 3: Remove the `cf-stawi-im-origin` listener** from `namespaces/gateway/gateway-config/gateway.yaml`. Keep the `cf-antinvestor-com-origin` listener.

- [ ] **Step 4: Verify**

```bash
grep -rln 'cf-stawi-im-origin\|stawi-im-endpoint' namespaces/ || echo "CLEAN"
yq '.spec.listeners[].name' namespaces/gateway/gateway-config/gateway.yaml
```
Expected: `CLEAN`; listener list no longer contains the stawi-im entry.

- [ ] **Step 5: Commit**

```bash
git add namespaces/gateway/
git commit -m "chore(gateway): remove api.stawi.im TLS, DNS endpoint, and HTTPS listener"
```

### Task 31: Apply Phase 4, verify clean cutover

- [ ] **Step 1: Push and reconcile**

```bash
git push
flux reconcile kustomization gateway-config -n flux-system
flux reconcile kustomization namespaces -n flux-system
```

- [ ] **Step 2: Verify the gateway no longer accepts SNI for `api.stawi.im`**

```bash
echo | openssl s_client -connect api.stawi.im:443 -servername api.stawi.im 2>&1 | grep -E 'Verify return|alert|error' | head -5
```
Expected: TLS error or unmatched certificate (not a successful handshake).

- [ ] **Step 3: Re-run the catalog probe — only the surviving hostnames**

```bash
SLUGS="profile tenancy files devices settings ledger payment notification"
for host in api.stawi.org api.stawi.dev api.antinvestor.com; do
  for slug in $SLUGS; do
    CODE=$(curl -ks -o /dev/null -w '%{http_code}' "https://${host}/${slug}/swagger.json")
    [ "$CODE" = "200" ] || echo "FAIL ${host}/${slug} → ${CODE}"
  done
done
echo "DONE"
```
Expected: only `DONE` printed (no `FAIL` lines).

- [ ] **Step 4: Final GATE** — all surviving hostnames serve every spec; `api.stawi.im` rejects traffic.

---

## Self-Review (per writing-plans skill)

The plan covers every requirement in the spec:

| Spec section | Plan tasks |
|---|---|
| §1 Goal & Scope | Phases 0–4 in entirety; out-of-scope items documented in spec |
| §2 Topology | Tasks 26–27 (HelmRelease wiring; existing HTTPRoute reused) |
| §3 Chart structure | Tasks 1–14 (every listed file rendered) |
| §4 Values schema | Task 2 (schema) + Task 1 (values.yaml) |
| §4.1 Schema enforcement | Task 2 (constraints) + Task 16 (rejection unittest) |
| §4.2 Render flow | Tasks 4, 5, 6, 9 (ConfigMaps + Deployment with init container for tenants) |
| §5 Migration phases | Phases 1–4 (Tasks 19–31) with explicit gates |
| §6.1 Pod hardening | Task 9 (security context, RO root, no SA token) |
| §6.2 Health probes | Task 9 (liveness/readiness/startup) |
| §6.3 Render validation | Task 13 (pre-install Job) + Task 16 (helm-unittest) |
| §6.4 Observability | `observability.serviceMonitor.enabled` flag in Task 1 values; cluster-level synthetic checks documented in §6.4 of spec are out-of-band |
| §6.5 CI tests | Tasks 16, 17 |
| §6.6 Image / supply-chain | Task 9 (digest path) + Task 26 (ImagePolicy/Repository) |
| §6.7 Backwards-compat | Task 26 (`service.name: service-api` retained, swagger-ui-config.yaml deleted) |

No placeholders. No "TBD" or "implement later". All commands and code blocks are executable as written.

The validation logic referenced in Task 16 Step 3 ("schema rejects sourcesFilter referencing unknown slug") requires `_helpers.tpl` `scalar.renderConfig` to call `fail` when a tenant references a missing slug — Task 3 currently writes a silent filter. Task 16 explicitly notes this and instructs the engineer to add the `fail` call before running unittests; this is a concrete, in-task instruction, not a placeholder.
