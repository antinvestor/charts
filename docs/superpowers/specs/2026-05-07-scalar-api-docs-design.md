# Scalar API Documentation — Design

**Date:** 2026-05-07
**Status:** Draft (pending implementation plan)
**Repos touched:** `antinvestor/charts` (new chart), `stawi.org/deployment.manifests` (rollout)

## 1. Goal & Scope

Replace the Swagger UI–based `service-api` deployment in the gateway namespace with a Scalar (`scalarapi/api-reference`) deployment, packaged as a reusable Helm chart designed for growth. As part of the same change, retire `api.stawi.im` in favour of `api.antinvestor.com`.

**In scope**

- New `scalar` Helm chart at `~/code/antinvestor/charts/charts/scalar/`.
- Replace the raw-manifest Swagger UI deployment in `~/code/stawi.org/deployment.manifests/namespaces/gateway/unified-api/` with a `HelmRelease` consuming the new chart.
- Hostname swap: `api.stawi.im` → `api.antinvestor.com` across all gateway and per-service routes/CORS lists.
- TLS, DNS, and gateway listener resources for `api.antinvestor.com`.

**Out of scope**

- Per-service OpenAPI spec quality audits across `~/code/{antinvestor,stawi*}` (deferred, tracked per service).
- Other `*.stawi.im` subdomains (`static.stawi.im`, `app.stawi.im`, `prod.stawi.im`, `r.stawi.im`, `info@stawi.im`).
- Per-spec auth gating — docs site stays public, mirroring current behaviour.
- Scalar's MCP / AI-agent integration — values keys reserved, no implementation.
- Self-bundling Scalar's JS — relying on Scalar's CDN for the runtime bundle.

## 2. Topology

```
api.stawi.org    ─┐
api.stawi.dev    ─┼─► Envoy Gateway ──► HTTPRoute "unified-api-core" (PathPrefix /)
api.antinvestor.com ─┘                  │
                                        ├─► backendRef: service-api (gateway ns)  ◄── Scalar (new)
                                        │      • serves landing page + API_REFERENCE_CONFIG
                                        │      • browser fetches /<slug>/swagger.json same-origin
                                        │
                                        └─► other HTTPRoutes for /files, /profile, /payment, …
                                               → routed to actual service backends in their namespaces
                                                 which serve /swagger.json from common.NewOpenAPIHandler
```

Key points:

- Specs are fetched **client-side, same-origin** through the gateway. No server-side proxying, no CORS pain.
- Service-side: zero Go changes. Every service already serves `/swagger.json` via Frame's `NewOpenAPIHandler`. The chart simply lists the slugs.
- The K8s `Service` named `service-api` is preserved so `unified-api-core.yaml`'s `backendRef` keeps working without edits.
- The chart lives at `~/code/antinvestor/charts/charts/scalar` and is consumed via `HelmRelease` from the existing `antinvestor` HelmRepository, mirroring the Colony chart pattern.

## 3. Chart Structure

```
scalar/
├── Chart.yaml                  # name: scalar, type: application; appVersion tracks scalarapi/api-reference
├── values.yaml                 # documented defaults (see §4)
├── values.schema.json          # JSON Schema validation for values
├── README.md                   # consumer-facing docs (sources schema, theming, examples)
├── templates/
│   ├── _helpers.tpl
│   ├── deployment.yaml         # 2 replicas, scalarapi/api-reference image, mounts config
│   ├── service.yaml            # name configurable; defaults to releaseName so existing HTTPRoute keeps working
│   ├── configmap-config.yaml   # renders API_REFERENCE_CONFIG JSON from .Values.sources + customization
│   ├── configmap-css.yaml      # rendered when .Values.customCss is inline
│   ├── configmap-landing.yaml  # rendered landing-page HTML from .Values.landing structured values
│   ├── httproute.yaml          # optional; .Values.gateway.enabled=false by default
│   ├── hpa.yaml
│   ├── pdb.yaml
│   ├── networkpolicy.yaml
│   ├── serviceaccount.yaml
│   ├── prejob-validate.yaml    # Helm pre-install/upgrade hook job — see §6
│   └── NOTES.txt
├── examples/
│   ├── minimal-values.yaml
│   ├── full-extensible-values.yaml
│   └── per-tenant-values.yaml
└── tests/
    └── values-render.bats
```

Structural decisions:

- **Two-ConfigMap split.** `configmap-config.yaml` holds the `API_REFERENCE_CONFIG` JSON (single source of truth). `configmap-css.yaml` holds optional larger CSS mounted at `/styles/custom.css`. Reloader annotations on the Deployment trigger rolling restarts on either change (matches the existing Antinvestor reloader pattern).
- **Service name pinning.** `.Values.service.name` defaults to `service-api` so the existing `unified-api-core` HTTPRoute keeps working unchanged. Renaming becomes opt-in later.
- **HTTPRoute optional.** `.Values.gateway.enabled` defaults to `false` because `unified-api-core` already exists. Set to `true` if a future deployment wants the chart to own its route end-to-end.
- **Schema validation.** `values.schema.json` is enforced by Helm — catches malformed `sources[]` entries (missing `slug`, bad URL, duplicate `default: true`) at render time.
- **Examples and tests in-tree.** Mirrors the Colony chart conventions (`charts/colony/examples/`, `values.schema.json`).

## 4. Values Schema

Annotated `values.yaml` (canonical defaults; trimmed of repeated infra blocks):

```yaml
image:
  repository: scalarapi/api-reference
  tag: latest                  # pinned in deployment.manifests; flux ImagePolicy bumps it
  digest: ""                   # when set, deployment uses repository@digest
  pullPolicy: IfNotPresent

replicas: 2
resources:
  requests: { cpu: 10m, memory: 80Mi }
  limits:   { cpu: 200m, memory: 400Mi }

service:
  name: service-api            # pinned for HTTPRoute back-compat; override in future
  port: 80
  targetPort: 8080

# ──── Catalog ────────────────────────────────────────────────────────────────
sources:
  - slug: profile
    title: "Profile API"
    description: "User management & authentication"
    icon: "user"
    group: identity
    url: /profile/swagger.json
    default: true              # exactly one allowed; chart validates
  - slug: tenancy
    title: "Tenancy API"
    group: identity
    url: /tenancy/swagger.json
  # … one entry per service

groups:
  identity:       { label: "Identity",       order: 1, color: "#1976d2" }
  platform:       { label: "Platform",       order: 2, color: "#10b981" }
  finance:        { label: "Finance",        order: 3, color: "#f59e0b" }
  communications: { label: "Communications", order: 4, color: "#7c3aed" }
  operations:     { label: "Operations",     order: 5, color: "#64748b" }

# ──── Theming ────────────────────────────────────────────────────────────────
theme: default                 # one of Scalar's preset themes
layout: modern                 # modern | classic
darkMode: auto                 # auto | light | dark | force-light | force-dark

customCss: |                   # inline string; small overrides
  :root {
    --scalar-color-accent: #1976d2;
  }
# customCssConfigMapRef:
#   name: scalar-extra-css
#   key: custom.css

# ──── Landing page ───────────────────────────────────────────────────────────
landing:
  enabled: true
  hero:
    title: "Antinvestor APIs"
    tagline: "APIs powering modern distributed financial systems"
  cards: []                    # auto-generated from sources[] when empty

# ──── Customization (passed to API_REFERENCE_CONFIG) ─────────────────────────
customization:
  showSidebar: true
  hideModels: false
  hideSearch: false
  defaultOpenAllTags: false
  persistAuth: true
  expandAllResponses: false
  hiddenClients: []            # e.g., ['curl', 'fetch']
  tagsSorter: alpha            # alpha | order | <custom>
  operationsSorter: method     # alpha | method | order

# ──── Per-tenant overrides ───────────────────────────────────────────────────
tenants: []
# tenants:
#   - hostname: api.antinvestor.com
#     theme: purple
#     landing:
#       hero: { title: "Antinvestor Platform" }
#     sourcesFilter: [profile, tenancy, files, payment]

# ──── Reserved (no-op for now) ───────────────────────────────────────────────
agent: { enabled: false }
mcp:   { enabled: false }

# ──── Standard infra blocks ──────────────────────────────────────────────────
hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80

pdb:
  enabled: true
  minAvailable: 1

networkPolicy:
  enabled: true

observability:
  serviceMonitor:
    enabled: false             # cluster-level synthetic checks cover this by default

gateway:
  enabled: false
  hostnames: []
  parentRef:
    name: default
    namespace: gateway
    sectionName: https
  pathPrefix: /
  cors:
    allowOrigins: ["*"]
    # allowHeaders auto-include the antinvestor-service-exposure required set
```

### 4.1 `values.schema.json` enforces

- `sources[].slug` matches `^[a-z0-9-]+$`, unique across the array.
- `sources[].url` starts with `/` (same-origin) or is an absolute URL.
- At most one `sources[*].default: true`. Zero is OK; Scalar picks the first.
- `theme` ∈ Scalar's known preset names (`default`, `moon`, `purple`, `solarized`, `bluePlanet`, `saturn`, `kepler`, `mars`, `deepSpace`, `laserwave`).
- `layout` ∈ `[modern, classic]`. `darkMode` ∈ `[auto, light, dark, force-light, force-dark]`.
- `tenants[].hostname` is a valid DNS name; unique across `tenants[]`.
- `tenants[].sourcesFilter[]` entries reference existing `sources[].slug`.
- `groups{}` keys referenced by `sources[].group` must exist.

### 4.2 Render flow

1. `helm template` produces:
   - `configmap/scalar-config` — full `API_REFERENCE_CONFIG` JSON, plus per-tenant variants under separate keys (`config.json`, `config.api.antinvestor.com.json`, …).
   - `configmap/scalar-landing` — rendered landing HTML.
   - `configmap/scalar-css` — only when `customCss` inline is set.
2. The Pod mounts these read-only at `/docs/configs/`, `/docs/landing.html`, `/docs/styles/custom.css`.
3. `API_REFERENCE_CONFIG` env points at the right config file. When `tenants[]` is non-empty, an init container — rendered inline in `deployment.yaml` (no separate template) — materializes a host-routing nginx snippet into a shared `emptyDir` volume that selects the per-host config; otherwise the single config is used unconditionally and no init container is rendered.

### 4.3 Why this is "extensible"

- Adding a service = one entry under `sources:` in the HelmRelease values. No chart changes, no new K8s objects.
- Independent rebrand of `api.antinvestor.com` = one entry under `tenants:`. No fork.
- Reorganizing the catalog = edit `groups{}` once. No source changes.
- Bigger Scalar features (auth, MCP, hooks) land as new top-level keys with sensible defaults — never break existing HelmReleases.

## 5. Migration Plan

Two parallel changes — the chart (additive) and the deployment.manifests swap. Sequenced for zero-downtime and reversibility.

### Phase 0 — Pre-flight (no cluster changes)

1. Build and tag chart `v0.1.0` at `~/code/antinvestor/charts/charts/scalar/`. `helm lint` + `helm template` for each example values file in CI.
2. Local end-to-end smoke: `helm template` → `docker run scalarapi/api-reference` mounting the rendered config; assert every `sources[].url` resolves against a mock.
3. Probe each backing service's `/swagger.json` against the **current production** gateway. Failures block the migration PR.

### Phase 1 — Provision `api.antinvestor.com` infra (additive)

Both hostnames live during this phase.

- New `namespaces/gateway/gateway-config/tls-antinvestor-com.yaml` — Cloudflare origin cert ExternalSecret, modeled on `tls-stawi-im.yaml`. Vault path: `antinvestor/gateway/tls/cf-antinvestor-com-origin`. Cert provisioned in Cloudflare and stashed in Vault before manifest apply.
- New `namespaces/gateway/gateway-config/dnsendpoint-antinvestor-com.yaml` — only if `api.antinvestor.com` doesn't already resolve via wildcard DNS. ExternalDNS already permits `antinvestor.com` (line 57 of `external-dns.yaml`).
- Update `namespaces/gateway/gateway-config/gateway.yaml` — add a new TLS listener entry referencing `cf-antinvestor-com-origin` *without removing* the `cf-stawi-im-origin` listener.
- `kustomization.yaml` updates in `gateway-config/`.

**Gate:** `curl -v https://api.antinvestor.com/healthz` returns 200; TLS chain validates against Cloudflare origin cert.

### Phase 2 — Add `api.antinvestor.com` to existing routes (additive)

For all ~22 service HelmReleases under `namespaces/{identity,platform,finance,communications,operations,product-opportunities}/.../service-*.yaml` plus gateway-level `unified-api-core.yaml`, `thesa-api.yaml`, `auth-routes.yaml`:

- `gateway.hostnames` and HTTPRoute `hostnames` arrays gain `api.antinvestor.com` *without* removing `api.stawi.im`. After this phase every public endpoint answers on both hostnames.

**Gate:** Generated probe iterates every `sources[].slug` and curls both `https://api.stawi.im/<slug>/swagger.json` and `https://api.antinvestor.com/<slug>/swagger.json`. Both must return identical 200 OpenAPI bodies.

### Phase 3 — Cut Scalar in (replace `service-api` workload)

In one PR to `deployment.manifests`:

- Delete the raw manifests block in `namespaces/gateway/unified-api/service-api.yaml` (Deployment, Service, HPA, PDB, ImagePolicy/ImageRepository, ServiceAccount).
- Delete `swagger-ui-config.yaml`.
- Add a new `namespaces/gateway/unified-api/service-api.yaml` containing only a `HelmRelease` for the `scalar` chart, with the full `sources[]` and theme/customCss.
- Update `kustomization.yaml` to drop `swagger-ui-config.yaml`.
- Keep `unified-api-core.yaml` HTTPRoute untouched — backendRef still names `service-api` and the chart preserves that K8s Service name.

Flux reconciles. Old pods torn down by Helm; new pods come up. RollingUpdate (`maxUnavailable: 1, maxSurge: 1`) plus PDB (`minAvailable: 1`) keeps at least one pod ready.

**Gate:** Synthetic probe loads `https://api.stawi.org/`, `https://api.stawi.dev/`, `https://api.antinvestor.com/` — confirms HTTP 200 + Scalar's `<scalar-app>` element + every `sources[]` URL fetches successfully.

**Rollback:** `git revert` the chart-cut PR. Flux reapplies the prior raw `service-api.yaml`. ~3 minutes back to the old Swagger UI. No data loss because nothing here is stateful.

### Phase 4 — Retire `api.stawi.im` (subtractive)

Only after Phase 3 has been stable for the soak window (recommended **7 days**, finalized in the rollout PR).

- Remove `api.stawi.im` from every `gateway.hostnames` / HTTPRoute `hostnames` array touched in Phase 2.
- Delete `unified-api-dns-stawi-im.yaml`, `tls-stawi-im.yaml`. Remove `cf-stawi-im-origin` listener block from `gateway.yaml`.
- Update `kustomization.yaml` files to drop deletions.
- Stale DNS records for `api.stawi.im` continue to resolve (CDN-level), but the gateway refuses TLS for that SNI. Clients receive a clean error.

### 5.1 Per-phase gate summary

| Phase | Gate |
|------|------|
| 0    | Chart `helm lint` clean; spec URLs verified against current prod |
| 1    | TLS cert valid for `api.antinvestor.com`; gateway accepts new listener |
| 2    | Every spec URL returns identical content on both hostnames |
| 3    | Scalar UI loads on all three hostnames; every catalog entry renders |
| 4    | (After soak) `api.stawi.im` traffic is zero in gateway access logs |

## 6. Robustness, Observability, Testing

### 6.1 Pod hardening

- `runAsNonRoot: true`, `runAsUser: 101`, `runAsGroup: 101` (matches Swagger UI baseline; Scalar image runs as the same nginx user).
- `readOnlyRootFilesystem: true` with explicit `emptyDir` volumes for `/var/cache/nginx` and `/tmp`. Render configs come from read-only ConfigMap mounts.
- `allowPrivilegeEscalation: false`, drop `ALL` capabilities, `seccompProfile: RuntimeDefault`.
- Dedicated ServiceAccount with `automountServiceAccountToken: false` — Scalar makes no Kubernetes API calls.
- NetworkPolicy permits ingress from the gateway namespace only and egress to DNS. The main pod requires no other egress — the JS bundle is fetched by the **client browser** from Scalar's CDN, not from the pod.
- The pre-install/upgrade validation Job (§6.3) runs under a separate ServiceAccount and a separate NetworkPolicy that additionally allows egress to the in-cluster gateway Service (port 80/443) so it can curl every `sources[].url`. This Job's policy is independent of the main Deployment's policy.

### 6.2 Health probes

- Liveness: `GET /` → 200. Period 10s, timeout 5s, failureThreshold 3 → restart.
- Readiness: `GET /` → 200 *and* `GET /configs/config.json` → 200 (asserts rendered config ConfigMap mounted). Period 5s, timeout 3s, failureThreshold 3 → out of rotation.
- Startup: `GET /` → 200, period 5s, failureThreshold 30 (~150s for cold start).

### 6.3 Render determinism and validation

- `values.schema.json` enforced by Helm at install/upgrade. Bad values (duplicate slugs, missing groups, malformed URLs) rejected before any pod starts.
- Chart includes a `helm.sh/hook: pre-install,pre-upgrade` Job that runs `jq -e .` over the rendered `API_REFERENCE_CONFIG` JSON and curls every `sources[].url` (in-cluster, against the gateway). Hook failure aborts the upgrade — Flux marks the HelmRelease unhealthy and surfaces in alerts.
- Reloader annotations on the Deployment watch the config and CSS ConfigMaps. A values change triggers a rolling restart automatically; pods that come up with a broken config fail readiness and never receive traffic (PDB ensures the old replica stays in rotation).

### 6.4 Observability

- Standard Antinvestor pod labels and `app.kubernetes.io/*` selectors flow into Prometheus scrape config and Grafana dashboards via existing kube-state-metrics scraping.
- nginx access logs follow the standard sidecar/log-aggregator pattern — no chart-specific logging config.
- A small synthetic uptime probe (Blackbox Exporter target list) is added with one entry per hostname (`api.stawi.org`, `api.stawi.dev`, `api.antinvestor.com`) hitting `/`. Alert rule fires if any returns non-2xx for 2 minutes.
- The chart emits a `ServiceMonitor` only when `.Values.observability.serviceMonitor.enabled: true` (default `false`) — kept off by default to avoid duplicating cluster-level synthetic checks.

### 6.5 CI / tests

- Chart-side: `helm lint`, `helm template` against each `examples/*-values.yaml`. `helm unittest` cases for source-slug uniqueness, per-tenant config materialization, conditional CSS ConfigMap rendering.
- Schema-side: a Go test in `~/code/antinvestor/charts/` parses `values.schema.json` and round-trips example values.
- A `make verify-specs` target in the chart runs the in-cluster pre-install Job logic locally against a `kubectl port-forward` of the gateway, useful before opening the Phase-3 PR.

### 6.6 Image / supply-chain

- `scalarapi/api-reference` pinned by digest in production via Flux ImagePolicy (mirrors the existing Swagger UI ImagePolicy pattern).
- Chart includes `image.digest` as a values key; rendered Deployment uses `repository@digest` form when set, falling back to `repository:tag` only in non-prod overlays.
- `Chart.yaml.appVersion` tracks Scalar's released tag and is updated together with the digest by a renovate-style PR cadence.

### 6.7 Backwards-compatibility assertions

- `service/service-api` keeps its name → no HTTPRoute change.
- The `URLS` env-var format consumed by the old Swagger UI is **not** preserved. The migration PR removes `swagger-ui-config.yaml` outright. There are no other consumers of those env vars or the custom CSS ConfigMap (verified by `grep -r swagger-ui-config ~/code/stawi.org/deployment.manifests/`).
- Existing client URLs of the form `https://api.stawi.org/<slug>/swagger.json` continue to resolve — those are routed by per-service HTTPRoutes (unchanged). Only the *catalog UI shell* (`/`) swaps from Swagger UI to Scalar.

## 7. Open Items For Implementation Plan

1. Soak window between Phase 3 and Phase 4 — recommended 7 days; finalized in the rollout PR description.
2. Whether `customCss` is materialized via inline string or referencing a separately-managed ConfigMap — both supported; the prod HelmRelease picks one at consumption time.
3. Whether to enable Scalar's `agent` / `mcp` features in a follow-up.
4. Whether to add per-tenant `sourcesFilter` for `api.antinvestor.com` from day one. Default: identical catalog on all hostnames; revisit when there's a reason to diverge.

## 8. References

- Existing Swagger UI deployment: `~/code/stawi.org/deployment.manifests/namespaces/gateway/unified-api/service-api.yaml`
- Existing custom CSS ConfigMap: `~/code/stawi.org/deployment.manifests/namespaces/gateway/unified-api/swagger-ui-config.yaml`
- Existing HTTPRoute: `~/code/stawi.org/deployment.manifests/namespaces/gateway/unified-api/unified-api-core.yaml`
- Frame OpenAPI handler: `~/code/antinvestor/common/openapi.go`
- Service exposure standard: `antinvestor-service-exposure` skill
- Colony chart (reference for chart conventions): `~/code/antinvestor/charts/charts/colony/`
- Scalar Docker image: `scalarapi/api-reference` (Docker Hub)
- Scalar configuration reference: <https://scalar.com/scalar/scalar-api-references/configuration>
