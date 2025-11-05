# Colony Helm Chart

A simplified, flexible Helm chart for deploying microservices on Kubernetes with standardized patterns for OAuth2, OpenTelemetry, and Kubernetes-native features.

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Examples](#examples)
- [Resource Templates](#resource-templates)
- [Advanced Usage](#advanced-usage)

## Overview

Colony is a lightweight Helm chart focused on Kubernetes orchestration and core observability for microservices. It generates essential Kubernetes resources while allowing applications to manage their own integration patterns.

**Generated Resources:**

- **Deployment** with security contexts, health probes, and resource limits
- **Service** (ClusterIP) with gRPC and HTTP ports
- **HorizontalPodAutoscaler** for auto-scaling
- **PodDisruptionBudget** for high availability
- **Gateway Routes** (HTTPRoute or GRPCRoute) for external access
- **DNSEndpoint** for external DNS configuration
- **FluxCD** ImageRepository and ImagePolicy for GitOps
- **Migration Job** for database migrations (pre-install/pre-upgrade)

## Features

### Core Capabilities

✅ **Kubernetes Orchestration**
- Production-ready Deployment with security contexts
- Service discovery via ClusterIP services
- Auto-scaling with HorizontalPodAutoscaler
- High availability with PodDisruptionBudget
- Rolling updates with zero-downtime deployments
- Pod anti-affinity for node distribution
- Graceful termination (60s grace period)

✅ **OAuth2 & Security**
- Built-in Hydra OAuth2 integration
- JWT audience verification
- Service-to-service authentication
- Secure container contexts (non-root, dropped capabilities)
- Kubernetes Secret references for sensitive data
- Network policies for traffic isolation

✅ **Observability**
- OpenTelemetry configuration (traces, metrics, logs)
- Kubernetes metadata injection (pod name, IP, node)
- Standardized resource attributes
- Integration with OpenTelemetry Collector

✅ **Gateway API**
- Support for both HTTPRoute and GRPCRoute
- CORS configuration for HTTP services
- External DNS integration with Cloudflare
- TLS/HTTPS termination

✅ **GitOps & Automation**
- FluxCD image automation
- Helm hook-based migration jobs
- Automatic image updates via ImagePolicy

✅ **Application Flexibility**
- Applications manage their own database connections
- Applications handle queue/messaging integration
- Custom environment variables via `env` list
- Custom volumes and volume mounts support

## Quick Start

### Prerequisites

- Kubernetes cluster (1.25+)
- Gateway API CRDs installed
- FluxCD for GitOps automation (optional)

### Installation

1. **Create a values file** for your service (e.g., `values-myservice.yaml`):

```yaml
serviceName: myservice
namespace: core

image:
  registry: ghcr.io
  repository: antinvestor/myservice
  tag: v1.0.0

gateway:
  enabled: true
  type: http  # or grpc
  hostname: myservice.chamamobile.com

oauth2:
  enabled: true
  clientSecret: your-client-secret

# Add your database/queue connections
env:
  - name: DATABASE_URL
    value: "postgres://user:pass@pooler-rw.datastore:5432/myservice"
  - name: LOG_LEVEL
    value: "info"
```

2. **Install the chart**:

```bash
helm install myservice ./charts/colony -f values-myservice.yaml
```

3. **Upgrade the chart**:

```bash
helm upgrade myservice ./charts/colony -f values-myservice.yaml
```

## Design Philosophy

Colony follows a **separation of concerns** approach:

### What Colony Manages ✅

- **Kubernetes Resources**: Deployment, Service, HPA, PDB, Gateway Routes
- **Core Configuration**: Logging, service ports, OAuth2, OpenTelemetry
- **Kubernetes Metadata**: Automatic pod/node info injection for OTEL
- **GitOps**: FluxCD image automation
- **Migrations**: Pre-install/upgrade database migration jobs

### What Applications Manage 🔧

- **Database Connections**: Apps specify their own DATABASE_URL via `env`
- **Queue/Messaging**: Apps configure NATS, Kafka, RabbitMQ as needed
- **Caching**: Apps manage Redis, Memcached connections
- **Custom Logic**: App-specific environment variables and configurations

This approach provides **maximum flexibility** while maintaining **standardized deployment patterns**.

### Security Context

All containers run with:
- `allowPrivilegeEscalation: false`
- `runAsNonRoot: true`
- Capabilities dropped: `ALL`
- `seccompProfile: RuntimeDefault`

Migration jobs additionally use:
- `runAsUser: 1001`
- `runAsGroup: 1001`
- `readOnlyRootFilesystem: true`

## Configuration

### Required Values

```yaml
serviceName: ""      # e.g., profile, tenancy, ledger (used directly as resource name)
namespace: core      # Kubernetes namespace

image:
  registry: ghcr.io
  repository: ""     # e.g., antinvestor/profile
  tag: ""           # e.g., v1.22.0
```

**Important:** `serviceName` is used directly for all resources. If you set `serviceName: profile`, you get:
- Deployment: `profile`
- Service: `profile.core.svc.cluster.local`
- OTEL service name: `profile`

### Logging Configuration

```yaml
logging:
  enabled: true
  level: info  # Options: debug, info, warn, error
```

Sets the `LOG_LEVEL` environment variable.

### Gateway Configuration

**For HTTP services:**

```yaml
gateway:
  enabled: true
  type: http
  hostname: myservice.chamamobile.com
  cors:
    enabled: true
    allowOrigins:
      - "https://*"
      - "http://localhost:5173"
    allowMethods:
      - GET
      - POST
      - PUT
      - DELETE
    allowCredentials: true
```

**For gRPC services:**

```yaml
gateway:
  enabled: true
  type: grpc
  hostname: myservice.chamamobile.com
```

### OAuth2 Configuration

```yaml
oauth2:
  enabled: true
  serviceUri: https://oauth2.chamamobile.com
  adminUri: http://service-authentication-oauth2-hydra-admin.core:4445
  clientSecret: "your-client-secret"
  audience: "service_partition,service_notifications"
  jwtVerifyAudience: "service_myservice"  # Defaults to service_{serviceName}
```

### OpenTelemetry Configuration

```yaml
opentelemetry:
  enabled: true
  environment: production
  endpoint: http://opentelemetry-collector.telemetry.svc.cluster.local:4317
  exporters:
    traces: otlp
    metrics: otlp
    logs: otlp
```

### Migration Job

```yaml
migration:
  enabled: true
  command: ["migrate"]
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

The migration job runs as a Helm pre-install/pre-upgrade hook.

### Custom Environment Variables

Add application-specific environment variables:

```yaml
env:
  # Database connection
  - name: DATABASE_USERNAME
    valueFrom:
      secretKeyRef:
        name: hub-core-app
        key: username
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: hub-core-app
        key: password
  - name: DATABASE_URL
    value: "postgres://$(DATABASE_USERNAME):$(DATABASE_PASSWORD)@pooler-rw.datastore.svc.cluster.local:5432/myservice"
  
  # Queue connection
  - name: QUEUE_USERNAME
    valueFrom:
      secretKeyRef:
        name: queue-myservice-secret
        key: username
  - name: QUEUE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: queue-myservice-secret
        key: password
  - name: EVENTS_QUEUE_URL
    value: "nats://$(QUEUE_USERNAME):$(QUEUE_PASSWORD)@queue.datastore.svc.cluster.local:4222?..."
  
  # Application-specific
  - name: FEATURE_FLAG_X
    value: "true"
  - name: API_TIMEOUT
    value: "30s"
```

## Examples

### Minimal HTTP Service

```yaml
serviceName: api
namespace: core

image:
  registry: ghcr.io
  repository: antinvestor/api
  tag: v1.0.0

gateway:
  enabled: true
  type: http
  hostname: api.chamamobile.com

oauth2:
  enabled: true
  clientSecret: "my-secret"
```

```bash
helm install api ./charts/colony -f values-api.yaml
```

### gRPC Service with Database

```yaml
serviceName: profile
namespace: core

image:
  registry: ghcr.io
  repository: antinvestor/profile
  tag: v2.1.0

gateway:
  enabled: true
  type: grpc
  hostname: profile.chamamobile.com

oauth2:
  enabled: true
  clientSecret: "profile-secret"
  audience: "service_notifications"

env:
  - name: DATABASE_USERNAME
    valueFrom:
      secretKeyRef:
        name: hub-core-app
        key: username
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: hub-core-app
        key: password
  - name: DATABASE_URL
    value: "postgres://$(DATABASE_USERNAME):$(DATABASE_PASSWORD)@pooler-rw.datastore.svc.cluster.local:5432/profile"
```

```bash
helm install profile ./charts/colony -f values-profile.yaml
```

## Resource Templates

The chart generates the following Kubernetes resources:

| Template | Description | Condition |
|----------|-------------|-----------|
| `deployment.yaml` | Main application deployment | Always |
| `service.yaml` | ClusterIP service | Always |
| `hpa.yaml` | HorizontalPodAutoscaler | `autoscaling.enabled=true` |
| `pdb.yaml` | PodDisruptionBudget | `podDisruptionBudget.enabled=true` |
| `httproute.yaml` | Gateway API HTTPRoute | `gateway.enabled=true` & `gateway.type=http` |
| `grpcroute.yaml` | Gateway API GRPCRoute | `gateway.enabled=true` & `gateway.type=grpc` |
| `dnsendpoint.yaml` | External DNS endpoint | `externalDNS.enabled=true` |
| `fluxcd-imagerepository.yaml` | FluxCD ImageRepository | `fluxcd.enabled=true` |
| `fluxcd-imagepolicy.yaml` | FluxCD ImagePolicy | `fluxcd.enabled=true` |
| `migration-job.yaml` | Pre-install/upgrade migration | `migration.enabled=true` |

## Advanced Usage

### Custom Volumes and Volume Mounts

```yaml
volumes:
  - name: config
    configMap:
      name: my-config
  - name: cache
    emptyDir: {}

volumeMounts:
  - name: config
    mountPath: /etc/config
    readOnly: true
  - name: cache
    mountPath: /tmp/cache
```

### Disable Optional Features

```yaml
# Disable OAuth2
oauth2:
  enabled: false

# Disable Gateway exposure
gateway:
  enabled: false

# Disable migration job
migration:
  enabled: false

# Disable auto-scaling
autoscaling:
  enabled: false

# Disable external DNS
externalDNS:
  enabled: false
```

### Adjust Resource Limits

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 2Gi
  requests:
    cpu: 500m
    memory: 1Gi
```

### Customize Autoscaling

```yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 75
```

### Health Probe Customization

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 60
  periodSeconds: 20
  timeoutSeconds: 10
  failureThreshold: 5

readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 10
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

## Environment Variables

Colony automatically sets the following environment variables:

### Logging
- `LOG_LEVEL` - Configurable log level (debug, info, warn, error)

### Service Ports
- `HTTP_PORT` - HTTP service port (from `service.http.targetPort`)
- `GRPC_PORT` - gRPC service port (from `service.grpc.targetPort`)

### OAuth2
- `OAUTH2_SERVICE_URI` - OAuth2 service URL
- `OAUTH2_SERVICE_ADMIN_URI` - OAuth2 admin URL
- `OAUTH2_SERVICE_CLIENT_SECRET` - OAuth2 client secret
- `OAUTH2_SERVICE_AUDIENCE` - Services this service can access
- `OAUTH2_JWT_VERIFY_AUDIENCE` - This service's JWT audience

### OpenTelemetry
- `OTEL_SERVICE_NAME` - Service identifier (defaults to `serviceName`)
- `OTEL_RESOURCE_ATTRIBUTES` - Comma-separated resource attributes including Kubernetes metadata
- `OTEL_EXPORTER_OTLP_PROTOCOL` - OTLP protocol (grpc/http)
- `OTEL_TRACES_EXPORTER` - Traces exporter (otlp)
- `OTEL_METRICS_EXPORTER` - Metrics exporter (otlp)
- `OTEL_LOGS_EXPORTER` - Logs exporter (otlp)
- `OTEL_EXPORTER_OTLP_ENDPOINT` - OTLP collector endpoint
- `OTEL_EXPORTER_OTLP_INSECURE` - Use insecure connection
- `OTEL_EXPORTER_OTLP_COMPRESSION` - Compression (gzip)
- Additional OTEL metrics configuration

### Kubernetes Metadata (via Downward API)
- `K8S_POD_NAME` - Current pod name
- `K8S_POD_NAMESPACE` - Current namespace
- `K8S_POD_IP` - Current pod IP address
- `K8S_NODE_NAME` - Node where pod is running

These are automatically included in `OTEL_RESOURCE_ATTRIBUTES` for complete observability context.

See [OpenTelemetry Kubernetes Metadata](docs/opentelemetry-kubernetes-metadata.md) for detailed documentation.

## Best Practices

### 1. Service Naming

- Use simple, descriptive names: `profile`, `ledger`, `api`
- Avoid prefixes like `service-` (the chart doesn't add them)
- Use consistent naming across environments

### 2. Resource Allocation

- Profile your service before setting resource limits
- Use HPA to handle traffic variability
- Configure PDB for production workloads (minAvailable: 1)
- Start conservative, scale up based on metrics

### 3. Database Migrations

- Test migrations thoroughly in staging
- Use `activeDeadlineSeconds` to prevent stuck migrations
- Keep migrations idempotent and reversible
- Monitor migration job logs during deployments

### 4. Observability

- Always enable OpenTelemetry for production services
- Kubernetes metadata is automatically injected
- Add custom attributes via `env` for business context
- Use consistent naming conventions for easier querying

### 5. Security

- Never commit secrets to git - use external secret managers
- Rotate OAuth2 client secrets regularly
- Use least-privilege RBAC policies
- Enable Pod Security Standards

### 6. Gateway & External Access

- Use HTTPS with proper TLS certificates
- Configure CORS appropriately for HTTP services
- Test gateway routes after deployment
- Use External DNS for automatic DNS management

## Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n core -l app.kubernetes.io/name=myservice

# Check pod events
kubectl describe pod -n core <pod-name>

# Check logs
kubectl logs -n core <pod-name>
```

### Migration Job Fails

```bash
# Check migration job logs
kubectl logs -n core job/myservice-migration

# Check job status
kubectl get job -n core myservice-migration -o yaml

# Delete failed job to retry
kubectl delete job -n core myservice-migration
helm upgrade myservice ./charts/colony -f values.yaml
```

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n core myservice

# Check HTTPRoute/GRPCRoute
kubectl get httproute -n core myservice -o yaml
kubectl get grpcroute -n core myservice -o yaml

# Check Gateway status
kubectl get gateway -n envoy-gateway-system default -o yaml

# Test internal service
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl http://myservice.core/healthz
```

### OpenTelemetry Not Working

```bash
# Check OTEL environment variables
kubectl exec -n core deployment/myservice -- env | grep OTEL

# Verify collector is reachable
kubectl exec -n core deployment/myservice -- nc -zv opentelemetry-collector.telemetry 4317

# Check application logs for OTEL errors
kubectl logs -n core -l app.kubernetes.io/name=myservice | grep -i otel
```

## Key Differences from Traditional Helm Charts

Colony takes a **minimalist approach**:

### ❌ What Colony Doesn't Do
- No automatic database URL generation
- No automatic queue URL generation  
- No CORS environment variable management
- No CronJob resources (manage separately)
- No secret generation (except for migrations)

### ✅ What Colony Does Well
- Kubernetes orchestration (Deployment, Service, HPA, PDB)
- Core observability (OAuth2, OpenTelemetry with K8s metadata)
- Gateway API integration (HTTPRoute, GRPCRoute)
- GitOps automation (FluxCD ImagePolicy)
- Migration job management

This separation allows:
- **Applications** to own their integration patterns
- **Colony** to focus on Kubernetes best practices
- **Maximum flexibility** for different use cases

## Further Reading

- **[CHANGELOG.md](CHANGELOG.md)** - Version history and breaking changes
- **[docs/opentelemetry-kubernetes-metadata.md](docs/opentelemetry-kubernetes-metadata.md)** - OTEL integration details
- **[Gateway API Documentation](https://gateway-api.sigs.k8s.io/)** - HTTPRoute and GRPCRoute specs
- **[FluxCD Image Automation](https://fluxcd.io/flux/guides/image-update/)** - Automated image updates

## License

Copyright © Antinvestor Team

## Support

For issues or questions:
- Create an issue in the repository
- Consult the [CHANGELOG.md](CHANGELOG.md) for migration guides
- Review example values files for common patterns
