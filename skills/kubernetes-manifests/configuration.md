# Configuration

Production-ready patterns for Kubernetes configuration resources.

## ConfigMaps

### Key-Value Pairs

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-server-config
  labels: { app: api-server }
data:
  db-host: "postgres-headless.database-ns.svc.cluster.local"
  db-port: "5432"
  log-level: "info"
  cache-ttl: "300"
```

### Multi-Line Config File

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    server {
      listen 8080;
      location / { proxy_pass http://api-server:80; }
      location /health { return 200 'ok'; }
    }
```

## Secrets

Four common types — values are base64-encoded in `data`, plain text in `stringData`.

```yaml
# Opaque — general-purpose credentials
apiVersion: v1
kind: Secret
metadata:
  name: api-server-secrets
  labels: { app: api-server }
type: Opaque
data:
  db-password: cGFzc3dvcmQxMjM=
  api-key: YWJjZGVmMTIzNDU2
---
# TLS — certificate and private key
apiVersion: v1
kind: Secret
metadata:
  name: myapp-tls
type: kubernetes.io/tls
data:
  tls.crt: LS0tLS1CRUdJTi...
  tls.key: LS0tLS1CRUdJTi...
---
# Docker registry — image pull credentials
apiVersion: v1
kind: Secret
metadata:
  name: registry-credentials
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: eyJhdXRocyI6...
---
# Basic auth
apiVersion: v1
kind: Secret
metadata:
  name: basic-auth
type: kubernetes.io/basic-auth
stringData:
  username: admin
  password: changeme-use-external-secrets
```

## Usage Methods

### Environment Variables

```yaml
# Individual keys from ConfigMap and Secret
env:
  - name: DB_HOST
    valueFrom: { configMapKeyRef: { name: api-server-config, key: db-host } }
  - name: DB_PASSWORD
    valueFrom: { secretKeyRef: { name: api-server-secrets, key: db-password } }

# Bulk load with prefix
envFrom:
  - configMapRef: { name: api-server-config }
    prefix: APP_
  - secretRef: { name: api-server-secrets }
    prefix: SECRET_
```

### Volume Mounts

```yaml
# Full ConfigMap as directory
volumes:
  - name: config
    configMap: { name: nginx-config, defaultMode: 0444 }
containers:
  - name: nginx
    volumeMounts: [{ name: config, mountPath: /etc/nginx/conf.d, readOnly: true }]

# Single key via subPath (does not hide existing files)
volumes:
  - name: config
    configMap: { name: api-server-config }
containers:
  - name: api-server
    volumeMounts: [{ name: config, mountPath: /app/config/settings.yaml, subPath: settings.yaml, readOnly: true }]
```

### Projected Volumes

Combine multiple sources into a single mount point.

```yaml
volumes:
  - name: app-config
    projected:
      sources:
        - configMap:
            name: api-server-config
            items: [{ key: db-host, path: db-host }]
        - secret:
            name: api-server-secrets
            items: [{ key: db-password, path: db-password, mode: 0400 }]
```

## Immutable Configs

Prevents accidental changes and improves cluster performance. Append version suffix for rollouts.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-server-config-v3
  labels: { app: api-server, version: v3 }
immutable: true
data:
  db-host: "postgres-headless.database-ns.svc.cluster.local"
  log-level: "info"
```

## External Secrets Operator

Sync secrets from AWS Secrets Manager (or other providers) into Kubernetes.

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef: { name: external-secrets-sa }
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-server-secrets
spec:
  refreshInterval: 1h
  secretStoreRef: { name: aws-secrets-manager, kind: SecretStore }
  target: { name: api-server-secrets, creationPolicy: Owner }
  data:
    - secretKey: db-password
      remoteRef: { key: myplatform/production/api-server, property: db-password }
```

## Sealed Secrets

Encrypt secrets for safe storage in Git repositories.

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: api-server-secrets
  namespace: myapp-ns
spec:
  encryptedData:
    db-password: AgBy3i4OJSWK+PiTySYZZA9rO...
    api-key: AgCtr8QLGHO+PJQZ1kFn2h0R5a...
  template:
    metadata:
      name: api-server-secrets
      labels: { app: api-server }
    type: Opaque
```

## Dynamic Updates

Force pod restart when a ConfigMap changes using a checksum annotation.

```yaml
# In Deployment spec.template.metadata.annotations:
annotations:
  checksum/config: "sha256-of-configmap-data"
# Helm: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
# Plain manifests: update the value in CI when the ConfigMap changes
```

## Best Practices

1. **Separate sensitive from non-sensitive** — ConfigMaps for config, Secrets for credentials.
2. **Enable encryption at rest** — configure `EncryptionConfiguration` for Secrets in etcd.
3. **Set restrictive file permissions** — `defaultMode: 0444` for ConfigMaps, `mode: 0400` for Secrets.
4. **Rotate secrets regularly** — use External Secrets Operator with `refreshInterval` for automatic rotation.
5. **Never hardcode credentials** — reference via `secretKeyRef` or volume mounts, never inline.
6. **Validate before deploy** — confirm ConfigMap and Secret references exist before applying Deployments.
7. **Version immutable configs** — append suffixes (e.g., `config-v3`) and update pod references to roll out.
