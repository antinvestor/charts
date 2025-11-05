# OAuth2 Secret Auto-Generation

## Overview

Colony Helm chart can automatically generate OAuth2 client secrets if they don't exist. This ensures:
- **Consistent naming** across all deployments (`{serviceName}-oauth2-secret`)
- **Secure random generation** using OpenSSL (32 bytes, base64 encoded)
- **No manual secret creation** required
- **Idempotent** - only creates secret if it doesn't already exist

## How It Works

When `oauth2.autoGenerateSecret: true`, the chart:

1. **Pre-Install/Pre-Upgrade Hook** runs before deployment
2. **Checks** if secret `{serviceName}-oauth2-secret` exists
3. **Generates** secure random secret if it doesn't exist
4. **Creates** Kubernetes Secret with proper labels and annotations
5. **Deployment** references the auto-generated secret

## Configuration

### Enable Auto-Generation (Default)

```yaml
serviceName: myservice

oauth2:
  enabled: true
  autoGenerateSecret: true  # Enabled by default
```

This automatically creates a secret named `myservice-oauth2-secret` with key `client-secret`.

### Secret Naming Convention

| Service Name | Generated Secret Name | Key Name |
|--------------|----------------------|----------|
| `profile` | `profile-oauth2-secret` | `client-secret` |
| `tenancy` | `tenancy-oauth2-secret` | `client-secret` |
| `ledger` | `ledger-oauth2-secret` | `client-secret` |
| `myservice` | `myservice-oauth2-secret` | `client-secret` |

### Custom Secret Name

Override the default naming:

```yaml
oauth2:
  autoGenerateSecret: true
  clientSecretRef:
    name: custom-oauth2-secret  # Use custom name
    key: client-secret
```

### Custom Key Name

Change the key name in the secret:

```yaml
oauth2:
  autoGenerateSecret: true
  secretGenerator:
    secretKey: oauth2-client-secret  # Custom key name
```

### Disable Auto-Generation

Use existing secret or inline value:

```yaml
oauth2:
  autoGenerateSecret: false
  clientSecretRef:
    name: existing-oauth2-secret
    key: client-secret
```

## Examples

### Example 1: Basic Auto-Generation

```yaml
# values.yaml
serviceName: profile
namespace: core

oauth2:
  enabled: true
  autoGenerateSecret: true  # Default
```

**Result:**
- Secret created: `profile-oauth2-secret`
- Key: `client-secret`
- Value: Randomly generated 32-byte base64 string

### Example 2: Multiple Services with Same Pattern

```yaml
# Service 1: profile
serviceName: profile
oauth2:
  autoGenerateSecret: true
# Creates: profile-oauth2-secret

# Service 2: tenancy  
serviceName: tenancy
oauth2:
  autoGenerateSecret: true
# Creates: tenancy-oauth2-secret

# Service 3: ledger
serviceName: ledger
oauth2:
  autoGenerateSecret: true
# Creates: ledger-oauth2-secret
```

All services follow the same naming pattern: `{serviceName}-oauth2-secret`

### Example 3: Custom Configuration

```yaml
serviceName: myservice

oauth2:
  enabled: true
  autoGenerateSecret: true
  clientSecretRef:
    name: myservice-custom-oauth2  # Custom name
    key: oauth-secret  # Custom key
  secretGenerator:
    secretKey: oauth-secret  # Must match clientSecretRef.key
    kubectlVersion: "1.28"  # kubectl version for job
```

### Example 4: Existing Secret (No Auto-Generation)

```yaml
serviceName: myservice

oauth2:
  enabled: true
  autoGenerateSecret: false  # Disable auto-generation
  clientSecretRef:
    name: pre-existing-secret
    key: client-secret
```

## Generated Secret Structure

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myservice-oauth2-secret
  namespace: core
  labels:
    app.kubernetes.io/name: myservice
    app.kubernetes.io/managed-by: Helm
    app.kubernetes.io/component: oauth2-secret
  annotations:
    meta.helm.sh/release-name: myservice
    meta.helm.sh/release-namespace: core
type: Opaque
data:
  client-secret: <base64-encoded-random-value>
```

## How to View Generated Secret

```bash
# View secret
kubectl get secret myservice-oauth2-secret -n core

# View decoded value
kubectl get secret myservice-oauth2-secret -n core \
  -o jsonpath='{.data.client-secret}' | base64 -d
```

## Helm Hook Behavior

The secret generation uses Helm hooks:

```yaml
annotations:
  helm.sh/hook: pre-install,pre-upgrade
  helm.sh/hook-weight: "-5"
  helm.sh/hook-delete-policy: before-hook-creation,hook-succeeded
```

**Timeline:**
1. **Pre-Install/Pre-Upgrade** (-10): ServiceAccount, Role, RoleBinding created
2. **Pre-Install/Pre-Upgrade** (-5): Secret generation job runs
3. **Pre-Install/Pre-Upgrade** (1): Migration job runs (if enabled)
4. **Install/Upgrade**: Main deployment starts
5. **Post-Hook**: Job and RBAC resources deleted automatically

## Idempotency

The secret generator is **idempotent**:

```bash
# First install
helm install myservice ./charts/colony -f values.yaml
# Secret created: myservice-oauth2-secret with value: abc123...

# Upgrade (secret exists)
helm upgrade myservice ./charts/colony -f values.yaml
# Secret NOT modified, keeps value: abc123...

# Uninstall and reinstall
helm uninstall myservice
helm install myservice ./charts/colony -f values.yaml
# Secret created with NEW value: xyz789...
```

**Important:** If you uninstall the release, the secret is NOT automatically deleted. Delete manually if needed:

```bash
kubectl delete secret myservice-oauth2-secret -n core
```

## Security Considerations

### ✅ Secure Random Generation

```bash
# Generated using OpenSSL
openssl rand -base64 32
# Example output: kJ3mN9pQ2rS5tU8vW1xY4zA6bC7dE9fG0hI2jK5lM8n=
```

- **Entropy:** 256 bits (32 bytes)
- **Character Set:** Base64 (A-Z, a-z, 0-9, +, /, =)
- **Length:** ~44 characters
- **Cryptographically secure:** Uses OpenSSL's random number generator

### ✅ RBAC Permissions

The secret generator job has minimal permissions:

```yaml
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list", "create", "patch", "update"]
```

**Scoped to:**
- Only the deployment namespace
- Only `secrets` resource
- Only necessary verbs

### ✅ Job Security Context

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

## Troubleshooting

### Issue: Secret Generation Job Fails

```bash
# Check job logs
kubectl logs -n core job/myservice-oauth2-secret-gen

# Common issues:
# 1. RBAC permissions
# 2. Image pull errors
# 3. kubectl version compatibility
```

**Solution:**
```yaml
# Adjust kubectl version
oauth2:
  secretGenerator:
    kubectlVersion: "1.29"  # Use newer version
```

### Issue: Secret Not Found

```bash
# Check if secret exists
kubectl get secret myservice-oauth2-secret -n core

# Check job status
kubectl get job -n core | grep oauth2-secret-gen

# If job failed, check logs
kubectl logs -n core job/myservice-oauth2-secret-gen
```

**Solution:**
```bash
# Manually create secret
kubectl create secret generic myservice-oauth2-secret \
  -n core \
  --from-literal=client-secret="$(openssl rand -base64 32)"
```

### Issue: Secret Already Exists with Different Structure

```bash
# Delete existing secret
kubectl delete secret myservice-oauth2-secret -n core

# Reinstall/upgrade to regenerate
helm upgrade myservice ./charts/colony -f values.yaml
```

### Issue: Need to Rotate Secret

```bash
# Method 1: Delete and regenerate
kubectl delete secret myservice-oauth2-secret -n core
helm upgrade myservice ./charts/colony -f values.yaml

# Method 2: Update manually
NEW_SECRET=$(openssl rand -base64 32)
kubectl create secret generic myservice-oauth2-secret \
  -n core \
  --from-literal=client-secret="${NEW_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new secret
kubectl rollout restart deployment/myservice -n core
```

## Migration from Manual Secrets

If you have existing manually created secrets:

### Option 1: Keep Existing Secret

```yaml
oauth2:
  autoGenerateSecret: false  # Disable auto-generation
  clientSecretRef:
    name: my-existing-secret
    key: my-key
```

### Option 2: Rename to Match Convention

```bash
# Copy existing secret to new name
kubectl get secret old-oauth2-secret -n core -o yaml | \
  sed 's/name: old-oauth2-secret/name: myservice-oauth2-secret/' | \
  kubectl apply -f -

# Enable auto-generation (will not overwrite)
oauth2:
  autoGenerateSecret: true
```

### Option 3: Migrate Value

```bash
# Get existing secret value
OLD_VALUE=$(kubectl get secret old-oauth2-secret -n core \
  -o jsonpath='{.data.secret-key}' | base64 -d)

# Create new secret with same value
kubectl create secret generic myservice-oauth2-secret \
  -n core \
  --from-literal=client-secret="${OLD_VALUE}"

# Enable auto-generation (will not overwrite)
oauth2:
  autoGenerateSecret: true
```

## Best Practices

### ✅ Use Auto-Generation in Production

```yaml
oauth2:
  autoGenerateSecret: true  # Recommended
```

**Benefits:**
- No manual secret management
- Consistent naming across services
- Secure random generation
- Helm-managed lifecycle

### ✅ Use Same Key Name Across Services

```yaml
oauth2:
  secretGenerator:
    secretKey: client-secret  # Standard key name
```

**Benefits:**
- Consistent across all services
- Easier to remember
- Simpler documentation

### ✅ Document Secret Rotation

```bash
# Create rotation runbook
cat > OAUTH2_SECRET_ROTATION.md <<EOF
1. Delete secret: kubectl delete secret {service}-oauth2-secret -n {namespace}
2. Upgrade release: helm upgrade {service} ./charts/colony -f values.yaml
3. Verify new secret: kubectl get secret {service}-oauth2-secret -n {namespace}
4. Restart deployment: kubectl rollout restart deployment/{service} -n {namespace}
5. Verify application: curl https://{service}.{domain}/healthz
EOF
```

### ⚠️ Backup Secrets Before Uninstall

```bash
# Backup all OAuth2 secrets
kubectl get secrets -n core -l app.kubernetes.io/component=oauth2-secret \
  -o yaml > oauth2-secrets-backup.yaml

# Restore if needed
kubectl apply -f oauth2-secrets-backup.yaml
```

## Advanced Configuration

### Custom Image for Secret Generation

```yaml
# values.yaml
oauth2:
  autoGenerateSecret: true
  secretGenerator:
    # Use custom image with specific tools
    image: myregistry.com/custom-kubectl:1.28
    imagePullPolicy: Always
```

### Multiple Secrets per Service

```yaml
# Generate multiple OAuth2 secrets
oauth2:
  autoGenerateSecret: true
  clientSecretRef:
    name: myservice-oauth2-secret
    
# Additional secrets via additionalSecrets
additionalSecrets:
  - name: myservice-oauth2-backup-secret
    type: Opaque
    data:
      client-secret: <manually-provided>
```

## Summary

**Auto-generation is:**
- ✅ **Enabled by default** (`autoGenerateSecret: true`)
- ✅ **Idempotent** (won't overwrite existing secrets)
- ✅ **Secure** (32-byte random, base64 encoded)
- ✅ **Consistent** (`{serviceName}-oauth2-secret` naming)
- ✅ **Managed** (Helm hooks, proper RBAC)

**Recommended for:**
- New deployments
- Standardized environments
- Multiple services with similar patterns

**Not recommended for:**
- Services requiring specific secret values
- External secret management systems (Vault, etc.)
- Strict secret rotation requirements
