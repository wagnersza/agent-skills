# Workloads

Production-ready patterns for Kubernetes workload resources.

## Deployment

Rolling update with probes, security context, and resource management.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  labels: { app: api-server, version: v1.4.0, component: backend, part-of: myplatform }
spec:
  replicas: 3
  revisionHistoryLimit: 5
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxUnavailable: 1, maxSurge: 1 }
  selector:
    matchLabels: { app: api-server }
  template:
    metadata:
      labels: { app: api-server, version: v1.4.0, component: backend, part-of: myplatform }
    spec:
      serviceAccountName: api-server
      terminationGracePeriodSeconds: 30
      securityContext:
        runAsNonRoot: true
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: api-server
          image: registry.example.com/api-server:v1.4.0
          ports: [{ containerPort: 8080, protocol: TCP }]
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: ["ALL"] }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 256Mi }
          startupProbe:
            httpGet: { path: /healthz, port: 8080 }
            failureThreshold: 30
            periodSeconds: 10
          livenessProbe:
            httpGet: { path: /healthz, port: 8080 }
            periodSeconds: 10
          readinessProbe:
            httpGet: { path: /ready, port: 8080 }
            periodSeconds: 5
          env:
            - name: DB_HOST
              valueFrom: { configMapKeyRef: { name: api-server-config, key: db-host } }
            - name: DB_PASSWORD
              valueFrom: { secretKeyRef: { name: api-server-secrets, key: db-password } }
          volumeMounts: [{ name: tmp, mountPath: /tmp }]
      volumes: [{ name: tmp, emptyDir: {} }]
```

## StatefulSet

Ordered pod management with per-replica persistent storage and exec-based probes.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  labels: { app: postgres, component: database }
spec:
  serviceName: postgres-headless
  replicas: 3
  podManagementPolicy: OrderedReady
  selector:
    matchLabels: { app: postgres }
  template:
    metadata:
      labels: { app: postgres, component: database }
    spec:
      serviceAccountName: postgres
      securityContext: { runAsNonRoot: true, fsGroup: 999, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: postgres
          image: registry.example.com/postgres:16.2
          ports: [{ containerPort: 5432 }]
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
          resources:
            requests: { cpu: 250m, memory: 512Mi }
            limits: { cpu: "1", memory: 1Gi }
          startupProbe: { exec: { command: ["pg_isready", "-U", "postgres"] }, failureThreshold: 30, periodSeconds: 10 }
          livenessProbe: { exec: { command: ["pg_isready", "-U", "postgres"] }, periodSeconds: 10 }
          readinessProbe: { exec: { command: ["pg_isready", "-U", "postgres"] }, periodSeconds: 5 }
          volumeMounts: [{ name: data, mountPath: /var/lib/postgresql/data }]
  volumeClaimTemplates:
    - metadata: { name: data }
      spec: { accessModes: ["ReadWriteOnce"], storageClassName: gp3-encrypted, resources: { requests: { storage: 50Gi } } }
```

## DaemonSet

Node-level agent with tolerations, host access, and read-only host filesystem mount.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  labels: { app: node-exporter, component: monitoring }
spec:
  selector:
    matchLabels: { app: node-exporter }
  template:
    metadata:
      labels: { app: node-exporter, component: monitoring }
    spec:
      serviceAccountName: node-exporter
      hostNetwork: true
      hostPID: true
      tolerations: [{ operator: Exists, effect: NoSchedule }]
      securityContext: { runAsNonRoot: true, runAsUser: 65534, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: node-exporter
          image: quay.io/prometheus/node-exporter:v1.7.0
          args: ["--path.rootfs=/host"]
          ports: [{ containerPort: 9100, hostPort: 9100 }]
          securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits: { cpu: 200m, memory: 128Mi }
          volumeMounts: [{ name: rootfs, mountPath: /host, readOnly: true }]
      volumes: [{ name: rootfs, hostPath: { path: / } }]
```

## Job

One-off task with backoff, TTL cleanup, and multi-line script.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migrate-v42
  labels: { app: db-migrate, version: v42 }
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      serviceAccountName: db-migrate
      restartPolicy: OnFailure
      securityContext: { runAsNonRoot: true, seccompProfile: { type: RuntimeDefault } }
      containers:
        - name: migrate
          image: registry.example.com/db-migrate:v42
          securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } }
          resources:
            requests: { cpu: 100m, memory: 128Mi }
            limits: { cpu: 500m, memory: 256Mi }
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -euo pipefail
              echo "Running migrations..."
              /app/migrate up --env production
              echo "Verifying schema..."
              /app/migrate verify
          env:
            - name: DATABASE_URL
              valueFrom: { secretKeyRef: { name: db-migrate-secrets, key: database-url } }
```

## CronJob

Scheduled backup with concurrency control, timezone, and cloud storage.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
  labels: { app: db-backup, component: operations }
spec:
  schedule: "0 2 * * *"
  timeZone: "America/Sao_Paulo"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 2
      ttlSecondsAfterFinished: 172800
      template:
        spec:
          serviceAccountName: db-backup
          restartPolicy: OnFailure
          securityContext: { runAsNonRoot: true, seccompProfile: { type: RuntimeDefault } }
          containers:
            - name: backup
              image: registry.example.com/db-backup:v1.0.3
              securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } }
              resources:
                requests: { cpu: 100m, memory: 256Mi }
                limits: { cpu: 500m, memory: 512Mi }
              command: ["/bin/sh", "-c"]
              args:
                - |
                  set -euo pipefail
                  TIMESTAMP=$(date +%Y%m%d-%H%M%S)
                  pg_dump "$DATABASE_URL" | gzip > /tmp/backup-${TIMESTAMP}.sql.gz
                  aws s3 cp /tmp/backup-${TIMESTAMP}.sql.gz s3://myplatform-backups/postgres/${TIMESTAMP}.sql.gz
              env:
                - name: DATABASE_URL
                  valueFrom: { secretKeyRef: { name: db-backup-secrets, key: database-url } }
              volumeMounts: [{ name: tmp, mountPath: /tmp }]
          volumes: [{ name: tmp, emptyDir: { sizeLimit: 2Gi } }]
```

## Init Containers

Wait for dependencies and run migrations before the main app starts. Add to `spec.initContainers`.

```yaml
initContainers:
  - name: wait-for-postgres
    image: registry.example.com/busybox:1.36
    securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } }
    resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { cpu: 50m, memory: 32Mi } }
    command: ["sh", "-c", "until nc -z postgres-headless 5432; do sleep 2; done"]
  - name: run-migrations
    image: registry.example.com/api-server:v1.4.0
    securityContext: { allowPrivilegeEscalation: false, readOnlyRootFilesystem: true, capabilities: { drop: ["ALL"] } }
    resources: { requests: { cpu: 100m, memory: 128Mi }, limits: { cpu: 500m, memory: 256Mi } }
    command: ["/app/migrate", "up"]
    env:
      - name: DATABASE_URL
        valueFrom: { secretKeyRef: { name: api-server-secrets, key: database-url } }
```

## Best Practices

1. **Set resource requests and limits** on every container including init containers.
2. **Define all three probes** — startup (slow init), liveness (restart if stuck), readiness (stop traffic if unhealthy).
3. **Apply security context** — `runAsNonRoot`, `readOnlyRootFilesystem`, `drop ALL`, `seccompProfile: RuntimeDefault`.
4. **Use consistent labels** — `app`, `version`, `component`, `part-of` on every workload.
5. **Set update strategy explicitly** — `RollingUpdate` for Deployments, `OrderedReady` for StatefulSets.
6. **Create dedicated ServiceAccounts** — never use the default; bind least-privilege RBAC.
7. **Pin image tags** — use immutable tags like `v1.4.0`, never `latest`. Include registry prefix.
8. **Set TTL cleanup on Jobs** — `ttlSecondsAfterFinished` prevents stale completed Jobs from accumulating.
