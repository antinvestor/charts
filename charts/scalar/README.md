# Scalar API Reference Helm Chart

Multi-spec OpenAPI documentation portal for Antinvestor APIs with Scalar UI integration.

**Version:** 0.1.0

## Overview

This Helm chart deploys Scalar (`scalarapi/api-reference`) as a Kubernetes application that serves multiple OpenAPI specifications from a single web UI. The chart provides sensible defaults for Antinvestor's unified API documentation portal (`api.antinvestor.com`), with optional customization for theming and CSS.

**Architecture:**

The `service-api` Service name is preserved by default to ensure compatibility with existing HTTPRoute definitions in the gateway namespace. Specs are fetched client-side from backend services through the gateway (same-origin); no server-side proxying is required. Each service continues to serve `/swagger.json` via its own handler.

The image (`scalarapi/api-reference`) runs **Caddy** (not nginx). Caddy reads the `API_REFERENCE_CONFIG` environment variable — a JSON object literal — and substitutes it into the static `index.html` at request time via Caddy's template module. The chart renders this JSON from `values.yaml` into a ConfigMap and injects it as an env var in the Deployment.

**Key features:**

- Multi-spec OpenAPI catalog with grouped navigation
- Themeable UI with dark mode support and inline CSS customization
- Kubernetes-native: HPA, PDB, NetworkPolicy, ServiceMonitor
- Auto-scaling and pod disruption budgets
- Two replicas by default with configurable resource limits

## Values Reference

All configuration options are documented in [values.yaml](values.yaml). Key sections:

- `image` — Container image and pull policy
- `sources[]` — API catalog (slug, title, URL, grouping, default)
- `theme`, `darkMode`, `customCss` — UI theming; `customCss` is injected into the `API_REFERENCE_CONFIG` JSON and picked up by Scalar's JS at runtime
- `replicas`, `hpa`, `pdb` — Scaling and disruption budgets
- `networkPolicy` — Traffic isolation
- `gateway` — Optional HTTPRoute creation (disabled by default)

## Examples

The `examples/` directory contains complete Helm values files for common deployments:

- `minimal-values.yaml` — Two-spec defaults (Profile & Tenancy)
- `full-extensible-values.yaml` — Production with theming, groups, and scaling

After release, deploy with example values: `helm install api-docs ./scalar -f examples/minimal-values.yaml -n gateway`

## Migration from Swagger UI

This chart replaces the raw-manifest Swagger UI deployment (`service-api`) in the gateway namespace. To migrate:

1. **Before:** Consumers deployed raw `service-api.yaml` Deployment/Service manifests.
2. **After:** Replace with a `HelmRelease` referencing this chart (see `examples/`).
3. **Compatibility:** The chart preserves the `service-api` Service name by default (`.Values.service.name: service-api`), so existing `HTTPRoute` `backendRef` entries continue to work unchanged.
4. **Spec configuration:** Instead of baking specs into the deployment, list them in `.Values.sources[]` with their `/slug/swagger.json` paths.

For complete migration details and topology diagram, see `docs/superpowers/specs/2026-05-07-scalar-api-docs-design.md` § 5.

## v0.1 Scope and Deferred Features

The following features are **reserved for future releases** and are no-ops in v0.1:

- **Per-host theming via `tenants[]`**: The image has no per-host routing capability — the same `API_REFERENCE_CONFIG` env var is served to all clients. The `tenants` schema key is accepted but ignored.
- **Landing-page customization**: Customization of the Scalar landing page is constrained to what `API_REFERENCE_CONFIG` supports (e.g., `theme`, `customCss`). The static `index.html` inside the image cannot be overridden without rebuilding the image; doing so would break Caddy's template substitution of the config object.

## Versioning

This chart follows semantic versioning. Breaking changes are documented in CHANGELOG.md.
