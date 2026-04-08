---
name: kubernetes-manifests
description: Writes Kubernetes manifests and Helm charts with production-grade defaults. Use when creating Deployments, StatefulSets, Services, Ingress, ConfigMaps, Secrets, RBAC, NetworkPolicies, storage resources, or Helm charts. Always hands off kubectl apply/delete and helm install/upgrade to the user.
---

# Kubernetes Manifests

## Overview

Write Kubernetes manifests that are secure, observable, and safe to apply. The agent writes manifests and validates locally — the user applies. This skill never runs `kubectl apply`, `kubectl delete`, `kubectl patch`, `helm install`, `helm upgrade`, or `helm uninstall`. Every change ends with a handoff: the exact command, a summary of resources, verification steps, and a rollback plan.

## When to Use

- Creating Deployments, StatefulSets, DaemonSets, Jobs, CronJobs
- Configuring Services, Ingress, IngressClass, NetworkPolicies
- Managing ConfigMaps and Secrets
- Setting up PersistentVolumeClaims and StorageClasses
- Creating Helm charts or Kustomize overlays
- Writing RBAC resources (Roles, ClusterRoles, ServiceAccounts)
- Any task involving `.yaml` manifest files for Kubernetes

**When NOT to use:**
- Debugging running workloads (use `kubernetes-debugging`)
- Testing manifests beyond local validation (use `kubernetes-testing`)
- Provisioning clusters with Terraform (use `infrastructure-as-code`)

**New code only:** When working in existing Kubernetes projects, only modify what was asked. Don't refactor surrounding manifests, add policies to existing namespaces, or "improve" resource names unless the user requests it.

## The Workflow

```
Task: Create or modify Kubernetes manifests
        |
        v
  1. Understand current state
     +-- Manifests exist? -> Read them, understand structure
     +-- Cluster access? -> kubectl get ns, kubectl api-resources
     +-- Greenfield? -> Scaffold: namespace, RBAC, NetworkPolicy
        |
        v
  2. Write manifests
     +-- Follow existing project conventions
     +-- Resource requests and limits on every container
     +-- Liveness and readiness probes
     +-- Security context: runAsNonRoot, readOnlyRootFilesystem
     +-- Dedicated ServiceAccount (never default)
     +-- NetworkPolicy (default-deny + explicit allows)
        |
        v
  3. Validate locally (non-negotiable)
     +-- kubectl apply --dry-run=client -f <file>
     +-- kubeval or kubeconform for schema validation
     +-- helm lint && helm template (for charts)
        |
        v
  4. Handoff (NEVER run apply or delete)
     +----------------------------------------------+
     | Manifests ready for apply!                    |
     |                                               |
     | Execute:  kubectl apply -f <path>             |
     | Resources: 3 Deployments, 2 Services,         |
     |            1 NetworkPolicy                    |
     | Verify:   kubectl get pods -n <ns>            |
     | Rollback: kubectl delete -f <path>            |
     +----------------------------------------------+
        |
        v
  5. After user applies -> Verify with kubernetes-debugging skill
```

## Reference Guide

| File | Content | Load When |
|---|---|---|
| workloads.md | Deployment, StatefulSet, DaemonSet, Job, CronJob patterns | Writing workload manifests |
| networking.md | Service, Ingress, IngressClass, Gateway API | Configuring network resources |
| configuration.md | ConfigMap, Secret, environment variables, volume mounts | Managing application config |
| storage.md | PVC, StorageClass, CSI drivers, volume patterns | Setting up persistent storage |
| helm-charts.md | Chart structure, values.yaml, templates, dependencies | Creating or modifying Helm charts |
| gitops.md | ArgoCD, Flux, directory conventions, sync strategies | Setting up GitOps workflows |
| service-mesh.md | Istio, Linkerd, sidecar injection, traffic policies | Adding service mesh configuration |
| custom-operators.md | CRD authoring, operator patterns, controller-runtime | Building custom operators |
| cost-optimization.md | Right-sizing, autoscaling, spot/preemptible, bin-packing | Reducing cluster costs |
| multi-cluster.md | Federation, multi-cluster Services, failover patterns | Spanning multiple clusters |

## Inline Patterns

### Deployment with Security Context, Probes, and Resource Limits

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  labels:
    app: myapp
    version: v1.2.0
    component: backend
    part-of: myplatform
spec:
  replicas: 3
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
        version: v1.2.0
        component: backend
        part-of: myplatform
    spec:
      serviceAccountName: myapp
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: myapp
          image: registry.example.com/myapp:v1.2.0
          ports:
            - containerPort: 8080
              protocol: TCP
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
          startupProbe:
            httpGet:
              path: /healthz
              port: 8080
            failureThreshold: 30
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            periodSeconds: 5
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: myapp-secrets
                  key: db-password
```

### ServiceAccount + Role + RoleBinding (Least Privilege RBAC)

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp
  namespace: myapp-ns
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: myapp-role
  namespace: myapp-ns
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["myapp-secrets"]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myapp-binding
  namespace: myapp-ns
subjects:
  - kind: ServiceAccount
    name: myapp
    namespace: myapp-ns
roleRef:
  kind: Role
  name: myapp-role
  apiGroup: rbac.authorization.k8s.io
```

### NetworkPolicy (Default-Deny + Explicit Allow)

```yaml
# Default deny all ingress and egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: myapp-ns
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-myapp
  namespace: myapp-ns
spec:
  podSelector:
    matchLabels:
      app: myapp
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432
    - to:  # Allow DNS to CoreDNS
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

### Secrets Handling

Never hardcode credentials. Reference Secret resources or external secret managers:

```yaml
# Good: Reference a Secret resource
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: myapp-secrets
        key: db-password

# Good: Mount secrets as a volume
volumes:
  - name: tls-certs
    secret:
      secretName: myapp-tls

# Bad: Hardcoded secret — NEVER do this
env:
  - name: DB_PASSWORD
    value: "supersecret123"

# Bad: Secret in a ConfigMap — NEVER do this
apiVersion: v1
kind: ConfigMap
data:
  db-password: "supersecret123"
```

## Constraints

### MUST DO

1. Write declarative YAML manifests (no imperative `kubectl create` commands for resource creation)
2. Set resource requests and limits on all containers
3. Define liveness and readiness probes
4. Use Secrets for sensitive data (never hardcode credentials)
5. Apply least-privilege RBAC permissions
6. Include NetworkPolicies for network segmentation
7. Use namespaces for logical isolation
8. Apply consistent labels: `app`, `version`, `component`, `part-of`
9. Pin specific image tags (never `latest` in production)
10. Set security context: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop ALL capabilities`

### MUST NOT DO

1. Run `kubectl apply`, `kubectl delete`, `kubectl patch`, `helm install/upgrade/uninstall`
2. Deploy without resource limits
3. Store secrets in ConfigMaps or plain env vars
4. Use the default ServiceAccount for application pods
5. Allow unrestricted network access (no NetworkPolicy = allow-all)
6. Run containers as root without justification
7. Skip health checks
8. Use `latest` tag for production images

## The Handoff

Every apply or delete ends with a handoff. This is non-negotiable.

### Template

```
Manifests ready for apply!

Execute:     kubectl apply -f <path> -n <namespace>
Resources:   <bullet list of resources being created/modified>
Verify:      kubectl get pods -n <namespace>
             kubectl get svc -n <namespace>
             kubectl logs -l app=<name> -n <namespace>
Rollback:    kubectl delete -f <path> -n <namespace>
             (or) kubectl rollout undo deployment/<name> -n <namespace>
```

### Handoff Rules

1. **Always show the dry-run output** before the handoff summary
2. **Always include verification commands** — `kubectl get`, `kubectl describe`, `kubectl logs` commands the user can run after apply to confirm resources are healthy
3. **Always include rollback** — what to do if the apply goes wrong
4. **Never run apply, delete, patch, or helm install/upgrade yourself**
5. **If the change deletes resources** — highlight them prominently and explain why

## Secrets

Never store secrets in manifest files committed to git.

| Secret Type | Where to Store |
|---|---|
| Database passwords | Sealed Secrets, External Secrets Operator, or cloud secret managers |
| API keys | External Secrets Operator syncing from AWS SSM, GCP Secret Manager, Azure Key Vault |
| TLS certificates | cert-manager with Let's Encrypt, or cloud-managed certificates |
| Docker registry credentials | `imagePullSecrets` referencing a Secret created out-of-band |
| Encryption keys | HashiCorp Vault with Vault Agent injector |

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll just kubectl apply this small change" | Small changes break production. Always handoff. |
| "This namespace doesn't need a NetworkPolicy" | Default is allow-all. Every namespace needs default-deny. |
| "Resource limits slow down development" | OOMKills in production slow down everything more. |
| "The default ServiceAccount is fine" | Default SA may have broad permissions. Always create a dedicated one. |
| "I'll add probes later" | Pods without probes receive traffic before they're ready and stay alive when broken. |
| "latest tag is fine for dev" | Dev images leak to staging. Pin versions everywhere. |
| "I know what the cluster state is" | Run the commands. Assumptions kill uptime. |
| "Security context is overkill for internal services" | Lateral movement exploits internal services first. Harden everything. |
| "Helm lint passed, so the chart is correct" | Lint checks structure, not semantics. Run template + kubeconform too. |

## Red Flags

- Running `kubectl apply`, `delete`, `patch` without user confirmation
- Missing resource requests/limits
- Missing liveness/readiness probes
- Using `latest` image tag
- Using default ServiceAccount
- No NetworkPolicy in the namespace
- Running containers as root
- Secrets stored in ConfigMaps
- Skipping validation (dry-run, lint)
- Modifying existing manifests beyond what was asked

## Verification

After completing Kubernetes manifests:

- [ ] All containers have resource requests and limits
- [ ] Liveness and readiness probes defined
- [ ] Security context: non-root, read-only rootfs, drop ALL capabilities
- [ ] Dedicated ServiceAccount (not default)
- [ ] NetworkPolicy present (default-deny + explicit allows)
- [ ] Secrets not hardcoded (reference Secret resources or external managers)
- [ ] Image tags pinned (not `latest`)
- [ ] Labels consistent (`app`, `version`, `component`)
- [ ] `kubectl --dry-run=client` passes
- [ ] Handoff template provided with execute, verify, rollback

## See Also

- For debugging running workloads after apply, use the `kubernetes-debugging` skill
- For testing manifests with policy engines and integration tests, use the `kubernetes-testing` skill
- For provisioning clusters with Terraform, use the `infrastructure-as-code` skill
