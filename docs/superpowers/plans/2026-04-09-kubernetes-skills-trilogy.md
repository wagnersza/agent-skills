# Kubernetes Skills Trilogy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create three Kubernetes skills (`kubernetes-manifests`, `kubernetes-debugging`, `kubernetes-testing`) mirroring the existing infrastructure trilogy.

**Architecture:** Each skill lives in its own directory under `skills/`. The `kubernetes-manifests` skill has 10 supporting reference files loaded on demand. The other two skills are self-contained. All three follow the standard skill anatomy (frontmatter, overview, when to use, process, rationalizations, red flags, verification). The README and CLAUDE.md are updated to register the new skills.

**Tech Stack:** Markdown (SKILL.md files), YAML examples (Kubernetes manifests)

**Spec:** `docs/superpowers/specs/2026-04-08-kubernetes-skills-trilogy-design.md`

---

### Task 1: Create `kubernetes-manifests/SKILL.md`

**Files:**
- Create: `skills/kubernetes-manifests/SKILL.md`

- [ ] **Step 1: Create the SKILL.md file**

Write the main skill file with:
- Frontmatter (`name: kubernetes-manifests`, `description` with trigger conditions)
- Overview: agent writes manifests/Helm charts, user applies. Never runs `kubectl apply/delete` or `helm install/upgrade`.
- When to Use: creating Deployments/StatefulSets/DaemonSets/Jobs, configuring Services/Ingress/NetworkPolicies, managing ConfigMaps/Secrets, setting up storage, creating Helm charts. NOT for: debugging running workloads (use `kubernetes-debugging`), testing manifests (use `kubernetes-testing`), Terraform for cluster provisioning (use `infrastructure-as-code`).
- The Workflow (ASCII flowchart from spec):
  1. Understand current state (existing manifests? cluster access? greenfield?)
  2. Write manifests (conventions, resource limits, probes, security context, ServiceAccount, NetworkPolicy)
  3. Validate locally (`kubectl --dry-run=client`, `kubeval`/`kubeconform`, `helm lint`/`helm template`)
  4. Handoff (never apply/delete)
  5. After user applies → verify with `kubernetes-debugging`
- Reference Guide table (10 entries with file, content, load-when columns — matching spec)
- Inline patterns section with YAML examples:
  - Deployment with security context, probes, resource limits (from Jeff Allan reference)
  - ServiceAccount + Role + RoleBinding (least privilege RBAC)
  - NetworkPolicy (default-deny + explicit allow)
  - Secrets handling (reference Secret resources, never hardcode)
- Constraints: MUST DO (10 items from spec) and MUST NOT DO (8 items from spec)
- The Handoff section with template and 5 rules (matching IaC handoff pattern)
- Secrets table (where to store each type, matching IaC pattern but for K8s: Sealed Secrets, External Secrets Operator, cloud secret managers)
- Common Rationalizations table (9 rows from spec)
- Red Flags (10 items from spec)
- Verification checklist (10 items from spec)
- See Also section cross-referencing `kubernetes-debugging`, `kubernetes-testing`, `infrastructure-as-code`

- [ ] **Step 2: Validate the file**

Run: `head -5 skills/kubernetes-manifests/SKILL.md`
Expected: YAML frontmatter with `name: kubernetes-manifests`

Verify line count is between 300-450 lines:
Run: `wc -l skills/kubernetes-manifests/SKILL.md`

- [ ] **Step 3: Commit**

```bash
git add skills/kubernetes-manifests/SKILL.md
git commit -m "feat: add kubernetes-manifests skill — core workflow and inline patterns"
```

---

### Task 2: Create `kubernetes-manifests` reference files (batch 1: workloads, networking, configuration, storage)

**Files:**
- Create: `skills/kubernetes-manifests/workloads.md`
- Create: `skills/kubernetes-manifests/networking.md`
- Create: `skills/kubernetes-manifests/configuration.md`
- Create: `skills/kubernetes-manifests/storage.md`

- [ ] **Step 1: Create `workloads.md`**

Production-ready YAML examples for each workload type, inspired by Jeff Allan's reference:
- **Deployment** pattern: RollingUpdate strategy, resource requests/limits, liveness/readiness probes, security context, ConfigMap/Secret refs, volume mounts
- **StatefulSet** pattern: OrderedReady pod management, volumeClaimTemplates, exec-based probes (e.g., postgres with `pg_isready`)
- **DaemonSet** pattern: node-exporter style, tolerations for NoSchedule, hostNetwork/hostPID, host filesystem mounts
- **Job** pattern: backoffLimit, ttlSecondsAfterFinished, OnFailure restart, multi-line shell script
- **CronJob** pattern: schedule, timeZone, Forbid concurrency, backup example with cloud storage
- **Init Containers** pattern: wait-for-dependency + run-migration before main app
- Best practices summary (8 items: resource management, health checks, security, labels, update strategy, service accounts, image tags, TTL cleanup)

- [ ] **Step 2: Create `networking.md`**

Production-ready YAML examples:
- **Service types**: ClusterIP (internal), Headless (StatefulSet direct pod DNS), NodePort (external via node ports), LoadBalancer (cloud provider)
- **Ingress**: NGINX ingress with TLS termination, path-based routing, cert-manager annotations
- **NetworkPolicy**: Default deny-all, frontend→backend rules, backend→database rules, cross-namespace monitoring access, DNS (port 53) + external HTTPS (443) egress
- **DNS patterns**: same-namespace (`service-name`), cross-namespace (`svc.namespace.svc.cluster.local`), StatefulSet pods (`pod-0.headless.ns.svc.cluster.local`)
- **EndpointSlice**: modern alternative to Endpoints
- Best practices (8 items: deny-all first, least privilege, prefer ClusterIP, DNS names over IPs, TLS at ingress, health checks, rate limiting, metrics)

- [ ] **Step 3: Create `configuration.md`**

Production-ready YAML examples:
- **ConfigMaps**: key-value pairs, multi-line configs, file-based creation
- **Secrets**: Opaque, TLS (`kubernetes.io/tls`), Docker registry, basic auth
- **Usage methods**: env vars (individual + bulk with prefix), volume mounts (full + subPath), projected volumes
- **Immutable configs**: `immutable: true` for critical configurations
- **External Secrets Operator**: SecretStore + ExternalSecret with AWS Secrets Manager, refresh interval
- **Sealed Secrets**: SealedSecret resource for safe GitOps
- **Dynamic updates**: checksum annotation pattern to force pod restart on ConfigMap change
- Best practices (7 items: separate sensitive/non-sensitive, encryption at rest, restrictive file permissions, rotation, no hardcoding, validate before deploy, version configs)

- [ ] **Step 4: Create `storage.md`**

Production-ready YAML examples:
- **StorageClass**: AWS EBS (gp3) with encryption/IOPS, GCE PD with regional replication, Azure Premium SSD, NFS with CSI
- **PersistentVolume**: static provisioning with node affinity
- **PersistentVolumeClaim**: dynamic provisioning, ReadWriteMany for shared storage, block volumes
- **StatefulSet volumes**: volumeClaimTemplates for per-replica storage
- **Volume Snapshots**: VolumeSnapshot + VolumeSnapshotClass with CSI driver
- **Volume Expansion**: `allowVolumeExpansion: true` in StorageClass
- **Ephemeral volumes**: memory-backed emptyDir (with sizeLimit), disk-backed emptyDir, projected volumes (secrets + configs + downwardAPI)
- **CSI examples**: AWS EBS CSI driver, Secrets Store CSI driver
- Best practices (8 items: use StorageClass for dynamic provisioning, set reclaim policy, encrypt at rest, size for growth, use snapshots for backups, test volume failover, monitor capacity, label PVCs)

- [ ] **Step 5: Validate all files exist and have content**

Run: `wc -l skills/kubernetes-manifests/workloads.md skills/kubernetes-manifests/networking.md skills/kubernetes-manifests/configuration.md skills/kubernetes-manifests/storage.md`
Expected: each file between 100-250 lines

- [ ] **Step 6: Commit**

```bash
git add skills/kubernetes-manifests/workloads.md skills/kubernetes-manifests/networking.md skills/kubernetes-manifests/configuration.md skills/kubernetes-manifests/storage.md
git commit -m "feat: add kubernetes-manifests reference files — workloads, networking, configuration, storage"
```

---

### Task 3: Create `kubernetes-manifests` reference files (batch 2: helm-charts, gitops)

**Files:**
- Create: `skills/kubernetes-manifests/helm-charts.md`
- Create: `skills/kubernetes-manifests/gitops.md`

- [ ] **Step 1: Create `helm-charts.md`**

Comprehensive Helm reference:
- **Chart structure**: Chart.yaml (metadata, versioning, dependencies), values.yaml (sensible defaults), templates/, charts/, tests/
- **Chart.yaml example**: apiVersion v2, name, description, type: application, version, appVersion, dependencies
- **values.yaml**: nested config with replicaCount, image (repository, tag, pullPolicy), resources, probes, serviceAccount, ingress, persistence
- **Template helpers** (`_helpers.tpl`): name, fullname, labels, selectorLabels, serviceAccountName
- **deployment.yaml template**: using helpers, range for env vars, toYaml for resources
- **service.yaml template**: configurable type and port
- **Helm hooks**: pre-install (db migration), post-install (test), hook-weight ordering, hook-delete-policy
- **Production overrides** (`values-prod.yaml`): 5+ replicas, increased resources, 100Gi storage
- **Testing**: `helm lint`, `helm template`, `helm test` (in-cluster), `ct lint-and-install`, `helm unittest`
- **Common commands**: install, upgrade, rollback (with `--atomic`), package, diff
- Best practices (8 items: pin chart versions, use `--atomic` for upgrades, template before apply, keep values minimal, use subcharts sparingly, schema validation for values, hook cleanup, semantic versioning)

- [ ] **Step 2: Create `gitops.md`**

GitOps reference covering both ArgoCD and Flux:
- **Core principles**: declarative, versioned/immutable, pulled automatically, continuously reconciled
- **ArgoCD**: Application resource (source, destination, syncPolicy with automated/prune/selfHeal), ApplicationSet (cluster generator), AppProject (RBAC for sources/destinations)
- **Flux**: GitRepository, Kustomization (sourceRef, prune, healthChecks), HelmRepository + HelmRelease, ImagePolicy + ImageUpdateAutomation
- **Secret management**: Sealed Secrets (kubeseal CLI, SealedSecret resource), SOPS with Age (encrypted fields, Flux decryption)
- **Repository strategies**: mono-repo (apps/infra/clusters hierarchy), multi-repo (per-app repos + fleet repo)
- **ArgoCD vs Flux comparison table**: UI/UX, architecture, multi-tenancy, image automation, learning curve
- Best practices (10 items: separate code/manifest repos, protected branches, secret encryption, auto-sync with pruning, notifications, progressive delivery, semantic versioning, DRY via overlays, monitor reconciliation, test before merge)

- [ ] **Step 3: Validate files**

Run: `wc -l skills/kubernetes-manifests/helm-charts.md skills/kubernetes-manifests/gitops.md`
Expected: each file between 150-300 lines

- [ ] **Step 4: Commit**

```bash
git add skills/kubernetes-manifests/helm-charts.md skills/kubernetes-manifests/gitops.md
git commit -m "feat: add kubernetes-manifests reference files — helm-charts, gitops"
```

---

### Task 4: Create `kubernetes-manifests` reference files (batch 3: service-mesh, custom-operators)

**Files:**
- Create: `skills/kubernetes-manifests/service-mesh.md`
- Create: `skills/kubernetes-manifests/custom-operators.md`

- [ ] **Step 1: Create `service-mesh.md`**

Service mesh reference covering Istio and Linkerd:
- **Istio installation**: profiles (minimal, default, demo, production), namespace injection label
- **VirtualService**: header-based routing, weighted traffic splits (canary), timeout/retry
- **DestinationRule**: connection pool settings, outlier detection, load balancing
- **Gateway**: ingress HTTPS with TLS, HTTP→HTTPS redirect
- **mTLS**: PeerAuthentication (permissive → strict), namespace and mesh-wide policies
- **Traffic mirroring**: mirror percentage config for shadow traffic testing
- **Circuit breakers**: connection limits, consecutive error thresholds
- **Fault injection**: controlled delay and abort for resilience testing
- **AuthorizationPolicy**: zero-trust, restrict by service account and HTTP method/path
- **Observability**: Kiali (topology), Jaeger (tracing)
- **Linkerd**: installation, proxy injection, ServiceProfile for per-route metrics/retries
- **Istio vs Linkerd comparison table**: proxy, resource footprint, feature depth, multi-cluster, learning curve
- Best practices (8 items: start permissive mTLS then strict, circuit breakers, timeouts/retries, traffic mirroring for validation, distributed tracing, consistent versions, gradual rollout, monitor proxy resource usage)

- [ ] **Step 2: Create `custom-operators.md`**

Custom operator reference:
- **CRD definition**: CustomResourceDefinition YAML with schema validation (e.g., Database CRD with engine options, storage, replicas)
- **Custom Resource instance**: example creating a Database resource
- **Operator SDK project structure**: api/v1/ (types), controllers/ (reconciler), config/ (CRDs, RBAC, manager), Dockerfile, Makefile
- **API types** (Go): Spec struct with kubebuilder markers (+kubebuilder:validation), Status struct with conditions
- **Reconciler pattern** (Go): Fetch CR → Check finalizer → Create/Update dependents (StatefulSet, Service, PVC) → Update status
- **RBAC for operators**: ServiceAccount, ClusterRole with CRD permissions + dependent resource permissions, ClusterRoleBinding
- **Deployment**: operator Deployment with leader election, resource limits
- Best practices (7 items: idempotent reconciliation, use status conditions, handle finalizers for cleanup, leader election for HA, use owner references for garbage collection, test with envtest, version CRD schemas carefully)

- [ ] **Step 3: Validate files**

Run: `wc -l skills/kubernetes-manifests/service-mesh.md skills/kubernetes-manifests/custom-operators.md`
Expected: each file between 150-300 lines

- [ ] **Step 4: Commit**

```bash
git add skills/kubernetes-manifests/service-mesh.md skills/kubernetes-manifests/custom-operators.md
git commit -m "feat: add kubernetes-manifests reference files — service-mesh, custom-operators"
```

---

### Task 5: Create `kubernetes-manifests` reference files (batch 4: cost-optimization, multi-cluster)

**Files:**
- Create: `skills/kubernetes-manifests/cost-optimization.md`
- Create: `skills/kubernetes-manifests/multi-cluster.md`

- [ ] **Step 1: Create `cost-optimization.md`**

Cost optimization reference:
- **Resource right-sizing**: analyze with `kubectl top pods`, set requests to average + 10-20% buffer, limits at 2-4x CPU / 1.5-2x memory
- **VPA**: VerticalPodAutoscaler resource with updateMode (Off for recommendations, Auto for automatic), resource policy min/max
- **HPA tuning**: fine-tuned scaling policies with stabilizationWindowSeconds, custom metrics (requests_per_second), behavior for scale up/down
- **Spot/preemptible instances**: node affinity + tolerations for spot nodes, PodDisruptionBudget for graceful handling
- **Resource quotas**: ResourceQuota per namespace (requests, limits, object counts)
- **LimitRange**: default requests/limits, min/max per container
- **Cluster autoscaler**: configuration for scale-down thresholds, utilization targets
- **Scheduled scaling**: CronJob to scale down non-prod during off-hours (kubectl scale command)
- **Cost monitoring**: Kubecost labels, Prometheus metrics (kube_pod_container_resource_requests), cost-center labels pattern
- **PriorityClass**: workload tiering (critical, high, default, low)
- Best practices (8 items: set requests on all containers, use priority classes, review unused resources regularly, label for cost tracking, right-size before scaling, use spot for fault-tolerant workloads, namespace quotas, scheduled scaling for non-prod)

- [ ] **Step 2: Create `multi-cluster.md`**

Multi-cluster reference:
- **Cluster API**: Cluster resource, AWSMachineTemplate, KubeadmControlPlane, MachineDeployment for declarative cluster lifecycle
- **Cross-cluster networking**: Submariner (Broker + SubmarinerConfig), ServiceExport/ServiceImport, Cilium ClusterMesh (ClusterMesh enable + global service annotations)
- **Cross-cluster DNS**: ExternalDNS with Route53, CoreDNS federation (forward plugin for cross-cluster queries)
- **Workload distribution**: KubeFed FederatedDeployment with placement/overrides, ArgoCD ApplicationSet with cluster generator
- **Disaster recovery**: Velero Schedule (backup), Velero Restore (cross-cluster), active-passive failover with weighted DNS (ExternalDNS annotations)
- **Centralized management**: Rancher, kubeconfig consolidation (`kubectl config get-contexts`, `kubectl config use-context`)
- Best practices (8 items: Cluster API for lifecycle, service mesh for cross-cluster security, centralized observability, test failover regularly, consistent namespaces across clusters, document topology, RBAC patterns per cluster, monitor cluster health centrally)

- [ ] **Step 3: Validate files**

Run: `wc -l skills/kubernetes-manifests/cost-optimization.md skills/kubernetes-manifests/multi-cluster.md`
Expected: each file between 150-250 lines

- [ ] **Step 4: Commit**

```bash
git add skills/kubernetes-manifests/cost-optimization.md skills/kubernetes-manifests/multi-cluster.md
git commit -m "feat: add kubernetes-manifests reference files — cost-optimization, multi-cluster"
```

---

### Task 6: Create `kubernetes-debugging/SKILL.md`

**Files:**
- Create: `skills/kubernetes-debugging/SKILL.md`

- [ ] **Step 1: Create the SKILL.md file**

Write the debugging skill with:
- Frontmatter (`name: kubernetes-debugging`, `description` with trigger conditions: pod failures, CrashLoopBackOff, service connectivity, resource issues, RBAC problems)
- Overview: Read-only inspection and troubleshooting of running Kubernetes clusters. No write operations without explicit user confirmation.
- When to Use: pod not starting (Pending), pod crashing (CrashLoopBackOff), image pull failures, service unreachable, DNS resolution issues, high resource usage, PVC problems, RBAC permission errors. NOT for: writing new manifests (use `kubernetes-manifests`), validating manifests before deploy (use `kubernetes-testing`), cloud-level cluster issues (use `infrastructure-discovery`).
- The Workflow (ASCII flowchart from spec): Identify symptoms → Inspect resources → Check events/conditions → Diagnose root cause → Recommend fix
- Decision Trees (4 trees from spec):
  - Pod stuck in Pending (insufficient resources, no nodes, unschedulable, waiting for volume)
  - CrashLoopBackOff (app error, exit 137/OOMKilled, exit 1/startup failure, exit 126-127/command not found)
  - ImagePullBackOff (unauthorized, not found, timeout)
  - Service not reachable (no endpoints/selector mismatch, NetworkPolicy blocking, Ingress/LB/DNS issues)
- Essential kubectl Commands section:
  - Pod inspection: `kubectl get pods -n <ns> -o wide`, `kubectl describe pod <name> -n <ns>`, `kubectl logs <pod> -n <ns> [--previous] [-c container]`
  - Resource usage: `kubectl top pods -n <ns>`, `kubectl top nodes`
  - Events: `kubectl get events -n <ns> --sort-by='.lastTimestamp'`
  - Service/networking: `kubectl get endpoints <svc> -n <ns>`, `kubectl get svc -n <ns>`, `kubectl get networkpolicy -n <ns>`
  - RBAC: `kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>`
  - Nodes: `kubectl describe node <name>`, `kubectl get nodes -o wide`
- Exit Code Reference table (6 rows from spec: 0, 1, 126, 127, 137, 143)
- Advanced Debugging section:
  - Ephemeral debug containers: `kubectl debug -it <pod> --image=busybox --target=<container>`
  - Node debugging: `kubectl debug node/<name> -it --image=busybox`
  - Network debugging pod YAML (temporary pod with curl, nslookup, netcat)
  - Database client debug pod YAML
- Read-Only Constraint section: list of allowed read-only commands, `kubectl debug` requires user confirmation, any write operation requires handoff
- Common Rationalizations table (subset relevant to debugging):
  - "I know what the cluster state is" → Run the commands. Assumptions kill uptime.
  - "I'll just restart the pod to fix it" → Restarting masks the root cause. Diagnose first.
  - "The logs should be enough" → Logs + events + describe + resource usage. Cross-reference everything.
  - "I can delete this stuck pod" → Never delete without user confirmation. Investigate why it's stuck.
  - "RBAC is probably fine" → Verify with `kubectl auth can-i`. Permission issues are silent.
- Red Flags: running write commands without confirmation, diagnosing without checking events, restarting pods as first action, ignoring exit codes, not checking resource limits when pod crashes
- Verification checklist (4 items from spec)
- See Also: `kubernetes-manifests`, `kubernetes-testing`, `infrastructure-discovery`

- [ ] **Step 2: Validate the file**

Run: `head -5 skills/kubernetes-debugging/SKILL.md`
Expected: YAML frontmatter with `name: kubernetes-debugging`

Run: `wc -l skills/kubernetes-debugging/SKILL.md`
Expected: between 250-400 lines

- [ ] **Step 3: Commit**

```bash
git add skills/kubernetes-debugging/SKILL.md
git commit -m "feat: add kubernetes-debugging skill — diagnostic workflow, decision trees, read-only constraint"
```

---

### Task 7: Create `kubernetes-testing/SKILL.md`

**Files:**
- Create: `skills/kubernetes-testing/SKILL.md`

- [ ] **Step 1: Create the SKILL.md file**

Write the testing skill with:
- Frontmatter (`name: kubernetes-testing`, `description` with trigger conditions: validating manifests, schema checks, security scanning, policy compliance, Helm chart testing)
- Overview: Validate Kubernetes manifests and Helm charts before deployment. Catches misconfigurations, security violations, and policy non-compliance before they reach a cluster.
- When to Use: after writing new manifests, before deploying to any environment, validating Helm charts, checking for deprecated APIs, security scanning manifests, policy compliance checks. NOT for: writing manifests (use `kubernetes-manifests`), debugging running workloads (use `kubernetes-debugging`), testing Terraform (use `infrastructure-testing`).
- Testing Pyramid (ASCII art from spec, 5 layers)
- Layer-by-layer detail:
  - **Layer 1 — Static Checks (always, non-negotiable)**: `kubectl --dry-run=client -o yaml`, `helm lint`, `helm template`, YAML syntax. Show exact commands with expected output.
  - **Layer 2 — Schema Validation (always for new manifests)**: `kubeconform -strict -kubernetes-version 1.29`, `kubeval --strict`, deprecated API detection. Show example output.
  - **Layer 3 — Security Scanning (always for new code)**: `kubesec scan deployment.yaml`, `trivy config .`, `trivy image <image>`. Show example output with pass/fail criteria.
  - **Layer 4 — Policy-as-Code (when compliance requires)**: `conftest test <file> -p <policy-dir>`, `kyverno apply <policy> --resource <manifest>`. Show example Rego policy (require labels) and Kyverno policy (deny latest tag).
  - **Layer 5 — Integration (handed off to user)**: `kubectl apply --dry-run=server -f <file>`, `helm install --dry-run --debug`, `ct lint-and-install`. Handoff template for server-side validation.
- Helm-Specific Testing section: lint, template, unittest, test (in-cluster, handoff), ct
- Deprecated API Detection section: common migrations (extensions/v1beta1 → networking.k8s.io/v1 for Ingress, etc.), how to check with `kubectl convert` or `kubent`
- Common Rationalizations table:
  - "Helm lint passed, so the chart is correct" → Lint checks structure, not semantics. Run template + kubeconform too.
  - "dry-run=client is enough" → Client-side doesn't check server-side admission. Use both when cluster available.
  - "Security scanning is overkill for internal manifests" → Internal is where lateral movement starts. Scan everything.
  - "We don't need policy checks for dev" → Dev bad habits become prod incidents. Enforce everywhere.
  - "The schema hasn't changed" → APIs get deprecated every release. Always validate against target version.
- Red Flags: skipping validation before apply, only running lint without schema validation, ignoring security scan results, not checking deprecated APIs, applying without dry-run
- Verification checklist (6 items from spec)
- See Also: `kubernetes-manifests`, `kubernetes-debugging`, `infrastructure-testing`

- [ ] **Step 2: Validate the file**

Run: `head -5 skills/kubernetes-testing/SKILL.md`
Expected: YAML frontmatter with `name: kubernetes-testing`

Run: `wc -l skills/kubernetes-testing/SKILL.md`
Expected: between 250-400 lines

- [ ] **Step 3: Commit**

```bash
git add skills/kubernetes-testing/SKILL.md
git commit -m "feat: add kubernetes-testing skill — testing pyramid, validation layers, policy checks"
```

---

### Task 8: Update README.md and CLAUDE.md

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update README.md — skill count and tables**

Update "All 22 Skills" to "All 25 Skills" in the heading.

Add to the **Build** table (after `infrastructure-discovery`):

```markdown
| [kubernetes-manifests](skills/kubernetes-manifests/SKILL.md) | Write declarative Kubernetes YAML and Helm charts with security hardening and mandatory apply handoff | Creating or modifying Kubernetes manifests, Services, RBAC, Helm charts |
```

Add to the **Verify** table (after `infrastructure-testing`):

```markdown
| [kubernetes-testing](skills/kubernetes-testing/SKILL.md) | Validate Kubernetes manifests with schema checks, security scanning, and policy-as-code | After writing new Kubernetes manifests or Helm charts |
| [kubernetes-debugging](skills/kubernetes-debugging/SKILL.md) | Read-only cluster inspection with diagnostic decision trees for common failure modes | Pod failures, service connectivity issues, resource problems |
```

Update the **Project Structure** section to add the three new directories under `skills/`:

```
│   ├── kubernetes-manifests/          #   Build
│   ├── kubernetes-debugging/          #   Verify
│   ├── kubernetes-testing/            #   Verify
```

Update skill count from 22 to 25 in the project structure comment.

- [ ] **Step 2: Update CLAUDE.md — project structure and skills by phase**

In the **Skills by Phase** section, add:
- **Build:** `kubernetes-manifests` (after `infrastructure-as-code`)
- **Verify:** `kubernetes-debugging`, `kubernetes-testing` (after `infrastructure-testing`)

In the **Project Structure** section, add the three new directories.

- [ ] **Step 3: Validate changes**

Run: `grep -c "kubernetes" README.md`
Expected: at least 6 matches (3 skill entries + 3 project structure entries)

Run: `grep "kubernetes" CLAUDE.md`
Expected: shows kubernetes-manifests, kubernetes-debugging, kubernetes-testing

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: register kubernetes skills trilogy in README and CLAUDE.md"
```

---

## Self-Review Notes

**Spec coverage check:**
- Skill 1 (kubernetes-manifests): Task 1 (SKILL.md) + Tasks 2-5 (10 reference files) ✓
- Skill 2 (kubernetes-debugging): Task 6 ✓
- Skill 3 (kubernetes-testing): Task 7 ✓
- Cross-references: each SKILL.md includes See Also section ✓
- README/CLAUDE.md registration: Task 8 ✓
- Shared rationalizations/red flags/verification: each skill includes its own subset ✓
- Handoff pattern: Tasks 1, 6, 7 all specify handoff rules ✓
- File structure matches spec exactly ✓

**Placeholder scan:** No TBD/TODO found. All tasks have specific content requirements.

**Type consistency:** Skill names (`kubernetes-manifests`, `kubernetes-debugging`, `kubernetes-testing`) used consistently across all tasks and cross-references.
