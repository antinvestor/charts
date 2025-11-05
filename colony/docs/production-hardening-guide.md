# Production Hardening Guide

This guide provides step-by-step instructions for implementing the critical and high-priority security and reliability improvements identified in the security audit.

## Quick Start

### Critical Issues (Implement Immediately)

1. [OAuth2 Secret Management](#1-oauth2-secret-management)
2. [Network Policies](#2-network-policies)
3. [Resource Limits](#3-resource-limits-review)

### High Priority (Implement Within Sprint)

4. [Pod Anti-Affinity](#4-pod-anti-affinity)
5. [Termination Grace Period](#5-termination-grace-period)
6. [Pod Disruption Budget](#6-improved-pod-disruption-budget)

---

## 1. OAuth2 Secret Management

### Problem
OAuth2 client secrets stored in values files can be accidentally committed to git.

### Solution
Use Kubernetes Secret references instead of inline values.

### Implementation

#### Step 1: Create Kubernetes Secret

```bash
# Create secret for each service
kubectl create secret generic myservice-oauth2-secret \
  -n core \
  --from-literal=client-secret='your-secure-secret-here'
```

#### Step 2: Update Values

```yaml
# values.yaml
oauth2:
  enabled: true
  # Option 1: Use secret reference (RECOMMENDED)
  clientSecretRef:
    name: myservice-oauth2-secret
    key: client-secret
  
  # Option 2: Direct value (backwards compatibility)
  # clientSecret: "your-secret"  # DON'T USE IN PRODUCTION
```

#### Step 3: Update Deployment Template

Add to `templates/deployment.yaml`:

```yaml
{{- if .Values.oauth2.enabled }}
{{- if .Values.oauth2.clientSecretRef }}
- name: OAUTH2_SERVICE_CLIENT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ .Values.oauth2.clientSecretRef.name }}
      key: {{ .Values.oauth2.clientSecretRef.key }}
{{- else if .Values.oauth2.clientSecret }}
- name: OAUTH2_SERVICE_CLIENT_SECRET
  value: {{ .Values.oauth2.clientSecret }}
{{- end }}
{{- end }}
```

### Verification

```bash
# Check secret is mounted
kubectl exec -n core deployment/myservice -- env | grep OAUTH2_SERVICE_CLIENT_SECRET

# Should show: OAUTH2_SERVICE_CLIENT_SECRET=your-secure-secret-here
```

---

## 2. Network Policies

### Problem
Without NetworkPolicies, pods can communicate with any service, increasing attack surface.

### Solution
Implement deny-by-default NetworkPolicy with explicit allow rules.

### Implementation

#### Step 1: Create NetworkPolicy Template

Create `templates/networkpolicy.yaml`:

```yaml
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "colony.fullname" . }}
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "colony.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "colony.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # Allow from Gateway/Ingress Controller
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.networkPolicy.ingressNamespace }}
      ports:
        {{- if .Values.service.http.enabled }}
        - protocol: TCP
          port: {{ .Values.service.http.targetPort }}
        {{- end }}
        {{- if .Values.service.grpc.enabled }}
        - protocol: TCP
          port: {{ .Values.service.grpc.targetPort }}
        {{- end }}
    
    # Allow from same namespace (service-to-service)
    - from:
        - podSelector: {}
      {{- if or .Values.service.http.enabled .Values.service.grpc.enabled }}
      ports:
        {{- if .Values.service.http.enabled }}
        - protocol: TCP
          port: {{ .Values.service.http.targetPort }}
        {{- end }}
        {{- if .Values.service.grpc.enabled }}
        - protocol: TCP
          port: {{ .Values.service.grpc.targetPort }}
        {{- end }}
      {{- end }}
    
    # Additional ingress rules
    {{- with .Values.networkPolicy.additionalIngressRules }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  
  egress:
    # Allow DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
        - podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    
    # Allow to datastore namespace (databases, NATS)
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.networkPolicy.datastoreNamespace }}
    
    # Allow to same namespace (service-to-service)
    - to:
        - podSelector: {}
    
    # Allow to telemetry
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ .Values.networkPolicy.telemetryNamespace }}
      ports:
        - protocol: TCP
          port: 4317  # OTLP gRPC
        - protocol: TCP
          port: 4318  # OTLP HTTP
    
    # Additional egress rules
    {{- with .Values.networkPolicy.additionalEgressRules }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}
```

#### Step 2: Add Values Configuration

Add to `values.yaml`:

```yaml
# Network Policy
networkPolicy:
  enabled: false  # Enable in production
  ingressNamespace: envoy-gateway-system
  datastoreNamespace: datastore
  telemetryNamespace: telemetry
  # Additional custom rules
  additionalIngressRules: []
  additionalEgressRules: []
  # Example additional egress for external APIs:
  # additionalEgressRules:
  #   - to:
  #       - namespaceSelector: {}
  #     ports:
  #       - protocol: TCP
  #         port: 443
```

#### Step 3: Enable in Production

```yaml
# production-values.yaml
networkPolicy:
  enabled: true
```

### Verification

```bash
# Check NetworkPolicy is created
kubectl get networkpolicy -n core

# Test connectivity
kubectl exec -n core deployment/myservice -- nc -zv other-service.core 80

# Should succeed for allowed, timeout for denied
```

---

## 3. Resource Limits Review

### Problem
Default resource limits may cause OOMKills or insufficient CPU.

### Solution
Profile application and set appropriate limits.

### Implementation

#### Step 1: Profile Current Usage

```bash
# Monitor resource usage over 24-48 hours
kubectl top pods -n core -l app.kubernetes.io/name=myservice --containers

# Get detailed metrics
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/namespaces/core/pods" | jq '.items[] | select(.metadata.labels."app.kubernetes.io/name"=="myservice") | .containers[]'
```

#### Step 2: Analyze Usage Patterns

```bash
# Using Prometheus (if available)
# Query: container_memory_usage_bytes{pod=~"myservice.*"}
# Query: container_cpu_usage_seconds_total{pod=~"myservice.*"}

# Look for:
# - Peak memory usage
# - Average memory usage
# - CPU spikes
# - OOMKill events
```

#### Step 3: Set Appropriate Limits

**Formula:**
- **Memory Limit** = Peak Usage × 1.5 (50% headroom)
- **Memory Request** = Average Usage × 1.2 (20% headroom)
- **CPU Limit** = Peak Usage × 1.3 (30% headroom)
- **CPU Request** = Average Usage

**Example:**
```yaml
# If profiling shows:
# - Average memory: 300Mi
# - Peak memory: 600Mi
# - Average CPU: 150m
# - Peak CPU: 800m

resources:
  limits:
    cpu: 1000m      # 800m × 1.3 = 1040m, rounded to 1000m
    memory: 1Gi     # 600Mi × 1.5 = 900Mi, rounded up to 1Gi
  requests:
    cpu: 150m       # Average usage
    memory: 360Mi   # 300Mi × 1.2 = 360Mi
```

#### Step 4: Test Under Load

```bash
# Load test
k6 run --vus 100 --duration 5m load-test.js

# Monitor during test
watch -n 1 'kubectl top pods -n core -l app.kubernetes.io/name=myservice'

# Check for OOMKills
kubectl get events -n core | grep OOM
```

### Verification

```bash
# Check pod is not throttled
kubectl describe pod -n core <pod-name> | grep -A 5 "Resource Requests"

# Check HPA is scaling appropriately
kubectl get hpa -n core myservice -o yaml
```

---

## 4. Pod Anti-Affinity

### Problem
Multiple replicas may schedule on the same node, reducing availability.

### Solution
Spread pods across different nodes using anti-affinity rules.

### Implementation

#### Step 1: Add Affinity to Deployment

Update `templates/deployment.yaml`:

```yaml
spec:
  template:
    spec:
      {{- if .Values.affinity }}
      affinity:
        {{- toYaml .Values.affinity | nindent 8 }}
      {{- else if .Values.podAntiAffinity.enabled }}
      affinity:
        podAntiAffinity:
          {{- if eq .Values.podAntiAffinity.type "required" }}
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchExpressions:
                  - key: app.kubernetes.io/name
                    operator: In
                    values:
                      - {{ include "colony.fullname" . }}
              topologyKey: kubernetes.io/hostname
          {{- else }}
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app.kubernetes.io/name
                      operator: In
                      values:
                        - {{ include "colony.fullname" . }}
                topologyKey: kubernetes.io/hostname
          {{- end }}
      {{- end }}
      containers:
        # ... existing containers ...
```

#### Step 2: Add Values Configuration

Add to `values.yaml`:

```yaml
# Pod Anti-Affinity
podAntiAffinity:
  enabled: true
  type: preferred  # or "required" for strict enforcement

# For custom affinity rules
affinity: {}
```

### Types Explained

**Preferred (Soft):**
- Tries to spread pods across nodes
- Tolerates scheduling on same node if necessary
- **Recommended for most cases**

**Required (Hard):**
- Must spread pods across nodes
- May leave pods pending if not enough nodes
- Use only if you have enough nodes

### Verification

```bash
# Check pod distribution
kubectl get pods -n core -l app.kubernetes.io/name=myservice -o wide

# Should see pods on different nodes
# Example output:
# NAME            NODE
# myservice-abc   node-1
# myservice-def   node-2
# myservice-ghi   node-3
```

---

## 5. Termination Grace Period

### Problem
Default 30s may not be enough for graceful shutdown.

### Solution
Increase termination grace period and add preStop hook.

### Implementation

#### Step 1: Add Termination Config

Update `templates/deployment.yaml`:

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds }}
      containers:
        - name: {{ include "colony.fullname" . }}
          # ... existing config ...
          {{- if .Values.lifecycle }}
          lifecycle:
            {{- toYaml .Values.lifecycle | nindent 12 }}
          {{- end }}
```

#### Step 2: Add Values Configuration

Add to `values.yaml`:

```yaml
# Graceful termination
terminationGracePeriodSeconds: 60

# Lifecycle hooks
lifecycle:
  preStop:
    exec:
      command:
        - /bin/sh
        - -c
        - sleep 10  # Allow time for load balancer de-registration
```

### How It Works

1. **SIGTERM sent** to container
2. **preStop hook runs** (10s sleep)
3. **Load balancers** remove pod from rotation
4. **Application** handles SIGTERM and shuts down gracefully
5. **After terminationGracePeriodSeconds** (60s), SIGKILL sent if still running

### Application Requirements

Your application should:
```go
// Example in Go
func main() {
    // Setup signal handling
    sigChan := make(chan os.Signal, 1)
    signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)
    
    // Start server
    go server.ListenAndServe()
    
    // Wait for signal
    <-sigChan
    
    // Graceful shutdown
    ctx, cancel := context.WithTimeout(context.Background(), 50*time.Second)
    defer cancel()
    server.Shutdown(ctx)
}
```

### Verification

```bash
# Test graceful shutdown
kubectl delete pod -n core myservice-xyz

# Watch logs - should see graceful shutdown messages
kubectl logs -n core myservice-xyz --previous

# Check no connection errors during rollout
while true; do curl -s https://myservice.com/healthz || echo "FAIL"; sleep 0.1; done
```

---

## 6. Improved Pod Disruption Budget

### Problem
Current `minAvailable: 1` with 2 replicas prevents node drains.

### Solution
Use percentage-based or `maxUnavailable` configuration.

### Implementation

#### Step 1: Update PDB Template

Update `templates/pdb.yaml`:

```yaml
{{- if .Values.podDisruptionBudget.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "colony.fullname" . }}
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "colony.labels" . | nindent 4 }}
spec:
  {{- if .Values.podDisruptionBudget.minAvailable }}
  minAvailable: {{ .Values.podDisruptionBudget.minAvailable }}
  {{- else if .Values.podDisruptionBudget.maxUnavailable }}
  maxUnavailable: {{ .Values.podDisruptionBudget.maxUnavailable }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "colony.selectorLabels" . | nindent 6 }}
{{- end }}
```

#### Step 2: Update Values

Update `values.yaml`:

```yaml
# Pod Disruption Budget
podDisruptionBudget:
  enabled: true
  # Use one of the following:
  minAvailable: 50%    # Keep at least 50% of pods
  # maxUnavailable: 1  # OR: Allow at most 1 pod unavailable
```

### Recommendations by Replica Count

| Replicas | Recommended Configuration | Reasoning |
|----------|---------------------------|-----------|
| 2 | `maxUnavailable: 1` | Allows voluntary disruptions |
| 3-4 | `minAvailable: 50%` | Maintains quorum |
| 5+ | `minAvailable: 60%` or `maxUnavailable: 2` | High availability |

### Verification

```bash
# Check PDB status
kubectl get pdb -n core myservice -o yaml

# Test node drain
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# PDB should allow drain while keeping minimum pods
kubectl get pods -n core -l app.kubernetes.io/name=myservice
```

---

## Production Deployment Checklist

Use this checklist before deploying to production:

```yaml
# production-values.yaml

# ✅ Critical Security
oauth2:
  clientSecretRef:
    name: myservice-oauth2-secret
    key: client-secret

networkPolicy:
  enabled: true

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 200m
    memory: 400Mi

# ✅ High Availability
replicaCount: 3

podAntiAffinity:
  enabled: true
  type: preferred

terminationGracePeriodSeconds: 60

podDisruptionBudget:
  enabled: true
  minAvailable: 50%

# ✅ Reliability
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20

livenessProbe:
  initialDelaySeconds: 60
  periodSeconds: 10
  failureThreshold: 6

readinessProbe:
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3

# ✅ Security
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault

# ✅ Observability
opentelemetry:
  enabled: true
  environment: production

# ✅ Gateway
gateway:
  enabled: true
  hostname: myservice.chamamobile.com
  cors:
    enabled: true
    allowOrigins:
      - "https://*"
```

---

## Testing Production Configuration

### 1. Chaos Testing

```bash
# Install chaos-mesh or similar
# Test pod deletion
chaos run pod-kill --namespace core --label app.kubernetes.io/name=myservice

# Test network delay
chaos run network-delay --namespace core --delay 100ms

# Test resource pressure
chaos run stress --namespace core --cpu-workers 4
```

### 2. Load Testing

```bash
# k6 load test
k6 run --vus 100 --duration 5m scripts/load-test.js

# Monitor metrics
kubectl top pods -n core -l app.kubernetes.io/name=myservice
kubectl get hpa -n core myservice --watch
```

### 3. Deployment Testing

```bash
# Test rolling update with zero downtime
# Terminal 1: Continuous requests
./scripts/health-check-loop.sh

# Terminal 2: Deploy new version
helm upgrade myservice ./charts/colony -f production-values.yaml

# Should see:
# ✅ No failed health checks
# ✅ Gradual pod replacement
# ✅ HPA maintains replica count
```

---

## Rollback Procedures

### If Deployment Fails

```bash
# Quick rollback
helm rollback myservice -n core

# Or to specific revision
helm rollback myservice 5 -n core

# Check rollback status
helm history myservice -n core
```

### If Migration Fails

```bash
# Check migration logs
kubectl logs -n core job/myservice-migration

# Manual intervention may be needed
# Connect to database and verify state
```

---

## Monitoring Production

### Key Metrics to Watch

1. **Pod Health**
   ```bash
   kubectl get pods -n core -l app.kubernetes.io/name=myservice
   ```

2. **Resource Usage**
   ```bash
   kubectl top pods -n core -l app.kubernetes.io/name=myservice
   ```

3. **HPA Status**
   ```bash
   kubectl get hpa -n core myservice
   ```

4. **PDB Status**
   ```bash
   kubectl get pdb -n core myservice
   ```

5. **Network Policy**
   ```bash
   kubectl get networkpolicy -n core myservice
   ```

### Alerts to Configure

- Pod restart count > 3 in 5 minutes
- Memory usage > 90% of limit
- CPU throttling > 50%
- Failed health checks
- HPA at max replicas
- PDB violations

---

## Support & Troubleshooting

### Common Issues

**Issue: Pods pending with anti-affinity**
```bash
# Check node count
kubectl get nodes

# Solution: Use "preferred" instead of "required" anti-affinity
```

**Issue: OOMKilled pods**
```bash
# Increase memory limits
resources:
  limits:
    memory: 2Gi  # Double current limit
```

**Issue: Network Policy blocking traffic**
```bash
# Temporarily disable to test
networkPolicy:
  enabled: false

# Add specific allow rules
networkPolicy:
  additionalEgressRules:
    - to:
        - podSelector:
            matchLabels:
              app: allowed-service
```

---

## Summary

By implementing these improvements, you'll achieve:

✅ **Enhanced Security**
- Secrets managed via Kubernetes Secrets
- Network isolation via NetworkPolicy
- Defense in depth

✅ **High Reliability**
- Pods distributed across nodes
- Graceful shutdown (60s)
- Improved PDB configuration
- Appropriate resource limits

✅ **Zero-Downtime Deployments**
- Rolling updates with proper health checks
- Multiple replicas with anti-affinity
- PDB prevents all pods being unavailable

✅ **Production Readiness**
- Tested under load
- Chaos engineering validated
- Monitoring and alerting configured

**Next Steps:**
1. Review and implement critical improvements
2. Test in staging environment
3. Gradually roll out to production
4. Monitor and iterate based on metrics
