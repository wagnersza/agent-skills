# Helm Charts

Production-ready patterns for Helm chart development, testing, and operations.

## Chart Structure

```
mychart/
  Chart.yaml          # Metadata, versioning, dependencies
  Chart.lock          # Pinned dependency versions
  values.yaml         # Default configuration values
  values.schema.json  # JSON Schema for values validation
  templates/          # Kubernetes manifest templates
    _helpers.tpl      # Shared template definitions
    deployment.yaml
    service.yaml
    ingress.yaml
    NOTES.txt         # Post-install usage instructions
  charts/             # Packaged subcharts
  tests/              # In-cluster test pods
```

## Chart.yaml

Chart metadata with dependencies and semantic versioning.

```yaml
apiVersion: v2
name: api-server
description: Backend API server for the platform
type: application
version: 1.4.0        # Chart version — bump on any chart change
appVersion: "2.1.0"   # Application version deployed by this chart
keywords: [api, backend, rest]
maintainers:
  - name: Platform Team
    email: platform@example.com

dependencies:
  - name: postgresql
    version: "15.5.x"
    repository: "https://charts.bitnami.com/bitnami"
    condition: postgresql.enabled
  - name: redis
    version: "~19.0"
    repository: "https://charts.bitnami.com/bitnami"
    condition: redis.enabled
```

## values.yaml

Sensible defaults with all configurable options.

```yaml
replicaCount: 2
image:
  repository: registry.example.com/api-server
  tag: ""              # Overridden by appVersion if empty
  pullPolicy: IfNotPresent
nameOverride: ""
fullnameOverride: ""
serviceAccount: { create: true, annotations: {}, name: "" }
service: { type: ClusterIP, port: 80, targetPort: 8080 }
ingress:
  enabled: false
  className: nginx
  annotations: {}
  hosts:
    - host: api.example.com
      paths: [{ path: /, pathType: Prefix }]
  tls: []
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits: { cpu: 500m, memory: 256Mi }
livenessProbe:
  httpGet: { path: /healthz, port: http }
  periodSeconds: 10
readinessProbe:
  httpGet: { path: /readyz, port: http }
  periodSeconds: 5
autoscaling: { enabled: false, minReplicas: 2, maxReplicas: 10, targetCPUUtilizationPercentage: 80 }
persistence: { enabled: false, storageClass: "", accessModes: [ReadWriteOnce], size: 10Gi }
env: []
envFrom: []
nodeSelector: {}
tolerations: []
affinity: {}
```

## Template Helpers (_helpers.tpl)

Reusable named templates for consistent naming and labeling.

```yaml
{{- define "mychart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "mychart.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "mychart.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 }}
{{ include "mychart.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "mychart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mychart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "mychart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "mychart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
```

## Deployment Template

Uses helpers, range for env vars, and toYaml for nested values.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels: {{- include "mychart.labels" . | nindent 4 }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels: {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels: {{- include "mychart.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "mychart.serviceAccountName" . }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports: [{ name: http, containerPort: {{ .Values.service.targetPort }}, protocol: TCP }]
          {{- with .Values.env }}
          env:
            {{- range . }}
            - name: {{ .name }}
              {{- if .value }}
              value: {{ .value | quote }}
              {{- else if .valueFrom }}
              valueFrom: {{- toYaml .valueFrom | nindent 16 }}
              {{- end }}
            {{- end }}
          {{- end }}
          {{- with .Values.envFrom }}
          envFrom: {{- toYaml . | nindent 12 }}
          {{- end }}
          livenessProbe: {{- toYaml .Values.livenessProbe | nindent 12 }}
          readinessProbe: {{- toYaml .Values.readinessProbe | nindent 12 }}
          resources: {{- toYaml .Values.resources | nindent 12 }}
```

## Service Template

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "mychart.fullname" . }}
  labels: {{- include "mychart.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
      name: http
  selector: {{- include "mychart.selectorLabels" . | nindent 4 }}
```

## Helm Hooks

Lifecycle hooks for database migrations and tests. Hook weight ordering: lower numbers run first (`-10` before `-5` before `0`).

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "mychart.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          command: ["./migrate", "--up"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef: { name: "{{ include "mychart.fullname" . }}-db", key: url }
---
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "mychart.fullname" . }}-test
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: curlimages/curl:8.7.1
      command: ["curl", "--fail", "http://{{ include "mychart.fullname" . }}:{{ .Values.service.port }}/healthz"]
```

## Production Overrides (values-prod.yaml)

```yaml
replicaCount: 5
resources:
  requests: { cpu: 500m, memory: 512Mi }
  limits: { cpu: "2", memory: 1Gi }
autoscaling: { enabled: true, minReplicas: 5, maxReplicas: 20, targetCPUUtilizationPercentage: 70 }
persistence: { enabled: true, storageClass: gp3-encrypted, size: 100Gi }
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/rate-limit: "100"
  hosts:
    - host: api.example.com
      paths: [{ path: /, pathType: Prefix }]
  tls:
    - secretName: api-tls
      hosts: [api.example.com]
```

## Testing

```bash
helm lint ./mychart --strict --values values-prod.yaml       # Lint for errors
helm template my-release ./mychart --values values-prod.yaml  # Render locally
helm install my-release ./mychart --dry-run --debug           # Dry-run against API
helm test my-release --timeout 5m                             # In-cluster tests
ct lint-and-install --charts ./mychart --target-branch main   # CI chart-testing
helm unittest ./mychart                                       # Unit test templates
```

## Common Commands

```bash
helm install my-release ./mychart -n production --create-namespace --values values-prod.yaml
helm upgrade my-release ./mychart -n production --values values-prod.yaml --atomic --timeout 10m
helm rollback my-release 0 -n production --wait
helm diff upgrade my-release ./mychart -n production --values values-prod.yaml
helm package ./mychart --version 1.4.0 --app-version 2.1.0
helm push mychart-1.4.0.tgz oci://registry.example.com/charts
helm list -n production --all
helm history my-release -n production
```

## Best Practices

1. **Pin chart dependency versions** — use exact versions or tilde ranges (`~15.5`) in `Chart.yaml` to avoid surprise breaking changes.
2. **Use `--atomic` for upgrades** — automatically rolls back if the release fails, preventing half-deployed states.
3. **Template before apply** — always run `helm template` or `helm diff` to review rendered manifests before installing or upgrading.
4. **Keep values minimal** — only expose configuration that varies between environments; hardcode sensible defaults in templates.
5. **Use subcharts sparingly** — prefer separate releases for databases and infrastructure services; subcharts couple lifecycle and complicate upgrades.
6. **Add values.schema.json** — JSON Schema validation catches misconfiguration at lint time instead of at deploy time.
7. **Clean up hooks** — always set `hook-delete-policy: before-hook-creation,hook-succeeded` to prevent stale hook resources.
8. **Follow semantic versioning** — bump chart `version` on every change; bump `appVersion` only when the application itself changes.
