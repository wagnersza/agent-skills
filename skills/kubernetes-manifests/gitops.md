# GitOps

Production-ready patterns for GitOps workflows with ArgoCD and Flux.

## Core Principles

1. **Declarative** — the entire system is described declaratively in Git.
2. **Versioned and immutable** — Git provides the audit trail; every change is a commit.
3. **Pulled automatically** — agents pull desired state from Git (no `kubectl apply` from CI).
4. **Continuously reconciled** — agents detect and correct drift from the declared state.

## ArgoCD Application

Defines what to deploy and where, with automated sync and self-healing.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api-server
  namespace: argocd
  finalizers: [resources-finalizer.argocd.argoproj.io]
spec:
  project: platform
  source:
    repoURL: https://github.com/example/k8s-manifests.git
    targetRevision: main
    path: apps/api-server/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true        # Delete resources removed from Git
      selfHeal: true     # Revert manual changes on cluster
    syncOptions: [CreateNamespace=true, PruneLast=true, ApplyOutOfSyncOnly=true]
    retry:
      limit: 5
      backoff: { duration: 5s, factor: 2, maxDuration: 3m }
```

## ArgoCD ApplicationSet

Generate Applications dynamically across clusters or directories.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: platform-apps
  namespace: argocd
spec:
  generators:
    - clusters:                              # Deploy to all matching clusters
        selector:
          matchLabels: { env: production }
    - git:                                   # One app per directory
        repoURL: https://github.com/example/k8s-manifests.git
        revision: main
        directories: [{ path: "apps/*" }]
  template:
    metadata:
      name: "{{path.basename}}-{{name}}"
    spec:
      project: platform
      source:
        repoURL: https://github.com/example/k8s-manifests.git
        targetRevision: main
        path: "{{path}}/overlays/{{metadata.labels.env}}"
      destination:
        server: "{{server}}"
        namespace: "{{path.basename}}"
      syncPolicy:
        automated: { prune: true, selfHeal: true }
```

## ArgoCD AppProject

RBAC boundaries for sources and destinations.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform
  namespace: argocd
spec:
  sourceRepos:
    - "https://github.com/example/k8s-manifests.git"
    - "https://charts.bitnami.com/bitnami"
  destinations:
    - server: https://kubernetes.default.svc
      namespace: "production"
    - server: https://kubernetes.default.svc
      namespace: "staging"
  clusterResourceWhitelist: [{ group: "", kind: Namespace }]
  roles:
    - name: deployer
      policies: ["p, proj:platform:deployer, applications, sync, platform/*, allow"]
      groups: [platform-team]
```

## Flux GitRepository and Kustomization

Flux pulls from a GitRepository source and applies via Kustomization.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: k8s-manifests
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/example/k8s-manifests.git
  ref: { branch: main }
  secretRef: { name: git-credentials }
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: api-server
  namespace: flux-system
spec:
  interval: 5m
  sourceRef: { kind: GitRepository, name: k8s-manifests }
  path: ./apps/api-server/overlays/production
  prune: true
  wait: true
  timeout: 5m
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: api-server
      namespace: production
```

## Flux HelmRelease

Declarative Helm release managed by Flux.

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.bitnami.com/bitnami
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: postgresql
  namespace: production
spec:
  interval: 10m
  chart:
    spec:
      chart: postgresql
      version: "15.5.x"
      sourceRef: { kind: HelmRepository, name: bitnami, namespace: flux-system }
  values:
    auth: { database: myapp, existingSecret: postgresql-credentials }
    primary:
      persistence: { size: 50Gi, storageClass: gp3-encrypted }
  upgrade:
    remediation: { retries: 3 }
```

## Flux Image Automation

Automatically update image tags in Git when new images are pushed.

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: api-server
  namespace: flux-system
spec:
  imageRepositoryRef: { name: api-server }
  policy:
    semver: { range: ">=2.0.0 <3.0.0" }
---
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageUpdateAutomation
metadata:
  name: api-server
  namespace: flux-system
spec:
  interval: 5m
  sourceRef: { kind: GitRepository, name: k8s-manifests }
  git:
    checkout: { ref: { branch: main } }
    commit:
      author: { name: fluxcdbot, email: flux@example.com }
      messageTemplate: "chore: update api-server to {{.NewTag}}"
    push: { branch: main }
  update: { path: ./apps/api-server, strategy: Setters }
```

## Secret Management — Sealed Secrets

Encrypt secrets in Git with Bitnami Sealed Secrets.

```bash
kubectl create secret generic db-creds \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system --format yaml > sealed-db-creds.yaml
```

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-creds
  namespace: production
spec:
  encryptedData:
    password: AgBy8h...encrypted-base64...
  template:
    metadata: { name: db-creds, namespace: production }
    type: Opaque
```

## Secret Management — SOPS with Age

Encrypt specific fields in-place with Mozilla SOPS.

```yaml
# .sops.yaml — repository-level config
creation_rules:
  - path_regex: .*secrets.*\.yaml$
    encrypted_regex: "^(data|stringData)$"
    age: age1ql3z7hjy54pw3hyww5ayyfg7z...
```

```yaml
# Flux Kustomization with SOPS decryption
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: secrets
  namespace: flux-system
spec:
  interval: 5m
  sourceRef: { kind: GitRepository, name: k8s-manifests }
  path: ./secrets
  prune: true
  decryption:
    provider: sops
    secretRef: { name: sops-age }
```

## Repository Strategies

**Mono-repo** — single repository with `apps/<name>/{base,overlays/{staging,production}}`, `infra/`, and `clusters/{staging,production}/kustomization.yaml`.

**Multi-repo** — per-app deploy repos owned by app teams, plus a `fleet-config/` repo owned by the platform team containing cluster definitions and AppProject/RBAC configs.

## ArgoCD vs Flux Comparison

| Aspect              | ArgoCD                              | Flux                                  |
|---------------------|-------------------------------------|---------------------------------------|
| **UI/UX**           | Rich web UI, CLI, SSO               | CLI-only, optional Weave GitOps UI    |
| **Architecture**    | Centralized server + API            | Distributed controllers per cluster   |
| **Multi-tenancy**   | AppProjects with RBAC               | Namespaced Kustomizations + RBAC      |
| **Image automation**| Argo Image Updater (separate)       | Built-in ImagePolicy + Automation     |
| **Helm support**    | Native rendering in Application     | HelmRelease CRD with remediation      |
| **Learning curve**  | Lower (UI helps onboarding)         | Higher (CRD-native, CLI-first)        |
| **Scalability**     | Single control plane, sharding      | Per-cluster, lightweight footprint    |

## Best Practices

1. **Separate code and manifest repos** — application source and deployment manifests live in different repositories to decouple build and deploy pipelines.
2. **Protect the main branch** — require pull request reviews and status checks before merging manifest changes.
3. **Encrypt all secrets in Git** — use Sealed Secrets, SOPS, or external secret operators; never commit plaintext secrets.
4. **Enable auto-sync with pruning** — set `prune: true` and `selfHeal: true` to ensure the cluster always matches Git.
5. **Configure notifications** — alert on sync failures, degraded health, and drift detection via Slack, PagerDuty, or webhooks.
6. **Use progressive delivery** — integrate Argo Rollouts or Flagger for canary and blue-green deployments instead of immediate full rollouts.
7. **Follow semantic versioning for charts** — tag manifests and chart versions so rollbacks target a known-good state.
8. **Stay DRY with overlays** — use Kustomize overlays or Helm value files per environment instead of duplicating manifests.
9. **Monitor reconciliation metrics** — track sync duration, failure rate, and drift count in Prometheus/Grafana dashboards.
10. **Test manifests before merge** — run `kustomize build`, `helm template`, and policy checks (OPA/Kyverno) in CI on every pull request.
