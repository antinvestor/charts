# Colony Helm Chart

Production-ready Helm chart for deploying microservices on Kubernetes with standardized patterns for OAuth2, OpenTelemetry, and Gateway API.

**Version:** 1.4.7

## Quick Start

```bash

# 0. Test using command and progress once satisfied by the result
 helm install testsvc charts/colony/ -f charts/colony/examples/values-production.yaml --dry-run --debug



# 1. Create OAuth2 secret (if using OAuth2)
kubectl create secret generic myservice-oauth2-cli \
  --from-literal=client-secret='your-secret' -n core

# 2. Install (release name = service name)
helm install myservice ./colony \
  --set image.repository=ghcr.io/antinvestor/myservice \
  --set image.tag=v1.0.0 \
  --set gateway.hostname=myservice.antinvestor.com \
  -n core
```

## Features

- ✅ **Kubernetes Orchestration** - Deployment, Service, HPA, PDB, ServiceAccount
- ✅ **Gateway API** - HTTPRoute & GRPCRoute with CORS support
- ✅ **Security** - Non-root containers, dropped capabilities, SecurityContext
- ✅ **Observability** - OpenTelemetry with auto-injected Kubernetes metadata
- ✅ **OAuth2** - Hydra integration with JWT audience verification
- ✅ **GitOps** - FluxCD image automation
- ✅ **Migrations** - Pre-install/upgrade Helm hooks
- ✅ **Network Policies** - Optional traffic isolation
- ✅ **Values Schema** - Validation for required fields

## Prerequisites

- Kubernetes 1.25+
- Gateway API CRDs
- Helm 3.4+ (for schema validation)

## Installation

### 1. Minimal Configuration

```yaml
# values.yaml
image:
  repository: ghcr.io/antinvestor/myservice
  tag: v1.0.0

gateway:
  enabled: true
  hostname: myservice.antinvestor.com  # Required

oauth2:
  enabled: true
  clientSecretRef:
    name: ""  # Defaults to {release-name}-oauth2-cli
    key: client-secret
```

```bash
helm install myservice ./colony -f values.yaml -n core
```

### 2. Production Configuration

```yaml
# Production settings
replicaCount: 3

serviceAccount:
  create: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/myservice

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70

podDisruptionBudget:
  enabled: true
  minAvailable: 50%

networkPolicy:
  enabled: true
  ingressNamespace: envoy-gateway-system
  datastoreNamespace: datastore
  telemetryNamespace: telemetry

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 400Mi

# Environment variables from ConfigMaps/Secrets
envFrom:
  - configMapRef:
      name: app-config
  - secretRef:
      name: database-creds

# Additional environment variables
env:
  - name: DATABASE_URL
    value: "postgres://$(DB_USER):$(DB_PASS)@pooler-rw.datastore:5432/mydb"
  - name: LOG_LEVEL
    value: "info"
```

See `examples/values-production.yaml` for a complete example.

## Configuration Reference

### Image (Required)

```yaml
image:
  repository: ghcr.io/antinvestor/myservice  # Required
  tag: v1.0.0  # Required
  pullPolicy: IfNotPresent
  pullSecrets:
    - name: ghcr-auth
```

### ServiceAccount

```yaml
serviceAccount:
  create: true  # Default: true
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/ROLE
  name: ""  # Defaults to release name
```

### Gateway API

```yaml
gateway:
  enabled: true
  type: http  # or grpc
  hostname: myservice.antinvestor.com  # Required
  parentRef:
    kind: Gateway
    name: default
    namespace: envoy-gateway-system
    sectionName: https
  cors:  # HTTP only
    enabled: true
    allowOrigins:
      - "https://*"
    allowMethods:
      - GET
      - POST
      - PUT
      - DELETE
    allowCredentials: true
```

### OAuth2

```yaml
oauth2:
  enabled: true
  serviceUri: https://oauth2.antinvestor.com
  adminUri: http://service-authentication-oauth2-hydra-admin.core:4445
  clientSecretRef:
    name: ""  # Defaults to {release-name}-oauth2-cli
    key: client-secret
  audience: "service_notifications,service_profile"
  jwtVerifyAudience: "service_myservice"
```

**Secret Creation:**
```bash
kubectl create secret generic myservice-oauth2-cli \
  --from-literal=client-secret='secret-here' -n core
```

### OpenTelemetry

```yaml
opentelemetry:
  enabled: true
  environment: production
  protocol: grpc
  endpoint: http://opentelemetry-collector.telemetry:4317
  insecure: true
  compression: gzip
  exporters:
    traces: otlp
    metrics: otlp
    logs: otlp
```

Automatically injects Kubernetes metadata (pod name, namespace, IP, node) into OTEL resource attributes.

### External DNS

```yaml
externalDNS:
  enabled: true
  # Uses gateway.hostname automatically
  recordTTL: 180
  recordType: CNAME
  targets:
    - "prod.antinvestor.com"
  cloudflareProxied: true
```

### Migration Job

```yaml
migration:
  enabled: true
  args: ["migrate"]
  env: []
  ttlSecondsAfterFinished: 300
  backoffLimit: 2
  activeDeadlineSeconds: 1800
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"
```

Runs as a pre-install/pre-upgrade Helm hook.

### Environment Variables

**Bulk injection from ConfigMaps/Secrets:**
```yaml
envFrom:
  - configMapRef:
      name: app-config
  - secretRef:
      name: app-secrets
```

**Individual variables:**
```yaml
env:
  - name: DATABASE_URL
    value: "postgres://user:pass@host:5432/db"
  - name: SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: app-secret
        key: secret-key
```

## Automatically Set Environment Variables

Colony automatically sets these environment variables:

| Variable | Source | Description |
|----------|--------|-------------|
| `LOG_LEVEL` | `logging.level` | Log level (debug/info/warn/error) |
| `HTTP_PORT` | `service.http.targetPort` | HTTP port |
| `GRPC_PORT` | `service.grpc.targetPort` | gRPC port |
| `OAUTH2_SERVICE_URI` | `oauth2.serviceUri` | OAuth2 service URL |
| `OAUTH2_SERVICE_ADMIN_URI` | `oauth2.adminUri` | OAuth2 admin URL |
| `OAUTH2_SERVICE_CLIENT_ID` | Release name | OAuth2 client ID |
| `OAUTH2_SERVICE_CLIENT_SECRET` | Secret | OAuth2 client secret |
| `OAUTH2_SERVICE_AUDIENCE` | `oauth2.audience` | OAuth2 audience |
| `OAUTH2_JWT_VERIFY_AUDIENCE` | `oauth2.jwtVerifyAudience` | JWT verification audience |
| `OTEL_SERVICE_NAME` | Release name | OpenTelemetry service name |
| `OTEL_RESOURCE_ATTRIBUTES` | Auto-generated | OTEL attributes with K8s metadata |
| `K8S_POD_NAME` | Downward API | Pod name |
| `K8S_POD_NAMESPACE` | Downward API | Namespace |
| `K8S_POD_IP` | Downward API | Pod IP |
| `K8S_NODE_NAME` | Downward API | Node name |

## Generated Resources

| Resource | Condition | Description |
|----------|-----------|-------------|
| Deployment | Always | Main application deployment |
| Service | Always | ClusterIP service |
| ServiceAccount | `serviceAccount.create=true` | Pod identity |
| HPA | `autoscaling.enabled=true` | Horizontal autoscaling |
| PDB | `podDisruptionBudget.enabled=true` | Disruption budget |
| HTTPRoute | `gateway.enabled=true` & `type=http` | Gateway API HTTP route |
| GRPCRoute | `gateway.enabled=true` & `type=grpc` | Gateway API gRPC route |
| DNSEndpoint | `externalDNS.enabled=true` | External DNS record |
| NetworkPolicy | `networkPolicy.enabled=true` | Network isolation |
| FluxCD ImageRepository | `fluxcd.enabled=true` | Image monitoring |
| FluxCD ImagePolicy | `fluxcd.enabled=true` | Image update policy |
| Migration Job | `migration.enabled=true` | Pre-install/upgrade hook |

## Design Philosophy

**What Colony Manages:**
- Kubernetes resources (Deployment, Service, HPA, PDB, etc.)
- Core configuration (logging, ports, OAuth2, OpenTelemetry)
- Gateway routing and external access
- GitOps automation

**What Applications Manage:**
- Database connections (via `env` or `envFrom`)
- Queue/messaging configuration
- Caching setup
- Application-specific logic

This separation provides maximum flexibility while maintaining standardized deployment patterns.

## Examples

### HTTP Service with Database

```yaml
image:
  repository: ghcr.io/antinvestor/api
  tag: v1.0.0

gateway:
  enabled: true
  type: http
  hostname: api.antinvestor.com
  cors:
    enabled: true
    allowOrigins: ["https://*"]

oauth2:
  enabled: true

envFrom:
  - secretRef:
      name: database-credentials

env:
  - name: DATABASE_URL
    value: "postgres://$(DB_USER):$(DB_PASS)@pooler-rw.datastore:5432/api"
```

### gRPC Service

```yaml
image:
  repository: ghcr.io/antinvestor/profile
  tag: v2.1.0

service:
  grpc:
    enabled: true
    port: 50051
  http:
    enabled: false

gateway:
  enabled: true
  type: grpc
  hostname: profile.antinvestor.com

oauth2:
  enabled: true
  audience: "service_notifications"
```

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n core -l app.kubernetes.io/name=myservice
kubectl describe pod -n core <pod-name>
kubectl logs -n core <pod-name>
```

### Check Gateway Routes
```bash
kubectl get httproute -n core myservice -o yaml
kubectl get grpcroute -n core myservice -o yaml
```

### Verify OAuth2 Secret
```bash
kubectl get secret myservice-oauth2-cli -n core
```

### Test Service Internally
```bash
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl http://myservice.core/healthz
```

### Check Migration Job
```bash
kubectl logs -n core job/myservice-migration
kubectl get job -n core myservice-migration
```

## Key Concepts

### Release Name = Service Name
The Helm release name is used as the service name throughout the chart. This is the Helm-native approach.

```bash
# Release name "myservice" creates:
# - Deployment: myservice
# - Service: myservice.core.svc.cluster.local
# - OAuth2 client ID: myservice
# - OTEL service name: myservice
helm install myservice ./colony -n core
```

### Namespace via CLI
Specify namespace using Helm's `-n` flag instead of in values:

```bash
helm install myservice ./colony -n core
helm install myservice ./colony -n staging
```

### Gateway Hostname
The `gateway.hostname` is used for:
- HTTPRoute/GRPCRoute hostname
- External DNS record (if enabled)

### Values Schema
The chart includes `values.schema.json` for validation. Helm 3.4+ will validate:
- Required fields (`image.repository`, `image.tag`)
- Data types and value ranges
- Enum values

## Best Practices

1. **Always use HTTPS in production** - Configure TLS in your Gateway
2. **Enable NetworkPolicy** - Restrict traffic to necessary services only
3. **Use ServiceAccount with IAM** - For cloud provider integration (IRSA/Workload Identity)
4. **Set resource limits** - Profile your service and set appropriate limits
5. **Enable PodDisruptionBudget** - Ensure availability during node maintenance
6. **Use envFrom for bulk config** - Simpler than individual env vars
7. **Test migrations thoroughly** - Use `activeDeadlineSeconds` to prevent hangs
8. **Monitor with OpenTelemetry** - Enable for all production services
9. **Use FluxCD for GitOps** - Automate image updates
10. **Keep secrets out of Git** - Use external secret managers or create manually

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and migration guides.

## License

Copyright © Antinvestor Team

## Support

For issues or questions:
- Check the examples in `examples/values-production.yaml`
- Review the CHANGELOG for migration guides
- Create an issue in the repository
