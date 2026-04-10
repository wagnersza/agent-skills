# Kubernetes Skills Trilogy — Design Spec

**Date:** 2026-04-08
**Author:** Wagner Souza + Claude
**Status:** Draft
**Inspiration:** [Jeffallan/claude-skills kubernetes-specialist](https://github.com/Jeffallan/claude-skills/tree/main/skills/kubernetes-specialist)

## Overview

Create three Kubernetes skills mirroring the existing infrastructure trilogy (`infrastructure-as-code`, `infrastructure-discovery`, `infrastructure-testing`). The new skills cover the full Kubernetes lifecycle: writing manifests, debugging clusters, and validating configurations.

### Why three skills, not one?

Kubernetes surface area is too broad for a single skill file. Splitting by concern keeps each SKILL.md focused and under ~400 lines, matches the existing infrastructure trilogy pattern, and lets agents pick the right skill for the task at hand.

## Skill 1: `kubernetes-manifests`

**Directory:** `skills/kubernetes-manifests/`
**Parallels:** `infrastructure-as-code`

### Purpose

Write declarative Kubernetes YAML and Helm charts. The agent writes and validates — the user applies. This skill **never runs** `kubectl apply`, `kubectl delete`, `helm install`, `helm upgrade`, or any state-mutating command.

### Workflow

```
Task: Create or modify Kubernetes resources
        │
        ▼
  1. Understand current state
     ├── Existing manifests? → Read them, understand structure
     ├── Cluster access? → Use kubernetes-debugging skill for inspection
     └── Greenfield? → Scaffold namespace, RBAC, base resources
        │
        ▼
  2. Write manifests
     ├── Follow existing project conventions (labels, naming)
     ├── Resource requests/limits on all containers
     ├── Liveness + readiness probes
     ├── Security context (non-root, read-only rootfs, drop ALL caps)
     ├── Dedicated ServiceAccount (never default)
     └── NetworkPolicy (default-deny + explicit allow)
        │
        ▼
  3. Validate locally (non-negotiable)
     ├── kubectl --dry-run=client -o yaml
     ├── kubeval / kubeconform (if available)
     └── helm lint / helm template (for charts)
        │
        ▼
  4. Handoff (NEVER run apply or delete)
     ┌──────────────────────────────────────────────┐
     │ Manifests ready for apply!                    │
     │                                               │
     │ Execute:  kubectl apply -f <path> -n <ns>     │
     │ Changes:  <summary of resources>              │
     │ Verify:   kubectl get pods -n <ns> -w         │
     │ Rollback: kubectl rollout undo deploy/<name>  │
     └──────────────────────────────────────────────┘
        │
        ▼
  5. After user applies → Verify with kubernetes-debugging skill
```

### Patterns (inline in SKILL.md)

These patterns stay inline in the main SKILL.md (~250 lines):

- **Deployment** with security context, probes, resource limits
- **ServiceAccount + RBAC** (least privilege Role + RoleBinding)
- **NetworkPolicy** (default-deny + explicit allow)
- **Secrets handling** (never in ConfigMaps, reference external secret managers)

### Reference Files (loaded on demand)

Each reference file covers one domain with production-ready YAML examples and best practices. Only loaded when the agent's task matches the topic.

| File | Content | Load When |
|------|---------|-----------|
| `workloads.md` | Deployment, StatefulSet, DaemonSet, Job, CronJob, init containers | Creating workload resources |
| `networking.md` | Services (ClusterIP, NodePort, LB, Headless), Ingress, DNS patterns, EndpointSlice | Configuring networking |
| `configuration.md` | ConfigMaps, Secrets, External Secrets Operator, Sealed Secrets, dynamic config updates | Managing configuration |
| `storage.md` | StorageClass, PV, PVC, StatefulSet volumes, snapshots, CSI drivers, ephemeral volumes | Setting up persistent storage |
| `helm-charts.md` | Chart structure, values, templates, helpers, hooks, testing, repositories, production overrides | Creating or modifying Helm charts |
| `gitops.md` | ArgoCD Applications/ApplicationSets, Flux GitRepository/Kustomization, sealed secrets, repo strategies | GitOps deployment patterns |
| `service-mesh.md` | Istio vs Linkerd, VirtualService, DestinationRule, mTLS, traffic mirroring, circuit breakers | Service mesh configuration |
| `custom-operators.md` | CRD definition, Operator SDK project structure, reconciler pattern, RBAC for operators | Building custom operators |
| `cost-optimization.md` | VPA, HPA tuning, spot/preemptible instances, resource quotas, LimitRanges, scheduled scaling, Kubecost | Right-sizing and cost reduction |
| `multi-cluster.md` | Cluster API, Submariner, cross-cluster DNS, Federation v2, ArgoCD ApplicationSets, Velero DR | Multi-cluster management |

### Constraints

**MUST DO:**
- Declarative YAML manifests (no imperative kubectl commands for resource creation)
- Resource requests and limits on all containers
- Liveness and readiness probes
- Secrets for sensitive data (never hardcode credentials)
- Least-privilege RBAC permissions
- NetworkPolicies for network segmentation
- Namespaces for logical isolation
- Consistent labels (`app`, `version`, `component`, `part-of`)
- Specific image tags (never `latest` in production)
- Security context: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop ALL capabilities`

**MUST NOT DO:**
- Run `kubectl apply`, `kubectl delete`, `kubectl patch`, `helm install/upgrade/uninstall`
- Deploy without resource limits
- Store secrets in ConfigMaps or plain env vars
- Use default ServiceAccount for application pods
- Allow unrestricted network access (no NetworkPolicy = allow-all)
- Run containers as root without justification
- Skip health checks
- Use `latest` tag for production images

### Handoff Rules

Same philosophy as `infrastructure-as-code`:

1. Always show the full manifest before the handoff summary
2. Always include verification commands (kubectl get, describe, logs)
3. Always include rollback steps
4. Never run apply, delete, or patch commands
5. If the manifest includes destructive changes (removing resources, scaling to 0), highlight them prominently

## Skill 2: `kubernetes-debugging`

**Directory:** `skills/kubernetes-debugging/`
**Parallels:** `infrastructure-discovery`

### Purpose

Troubleshoot and inspect running Kubernetes clusters using read-only operations. Diagnose pod failures, service connectivity issues, resource constraints, and RBAC problems. **No write operations without explicit user confirmation.**

### Workflow

```
Task: Debug a Kubernetes issue
        │
        ▼
  1. Identify symptoms
     ├── Pod not starting? → Check events, describe pod
     ├── Pod crashing? → Check logs, previous logs, exit codes
     ├── Service unreachable? → Check endpoints, NetworkPolicies
     └── Performance issue? → Check resource usage, limits
        │
        ▼
  2. Inspect resources (read-only)
     ├── kubectl get <resource> -n <ns> -o wide
     ├── kubectl describe <resource> <name> -n <ns>
     ├── kubectl logs <pod> -n <ns> [--previous]
     └── kubectl top pods/nodes
        │
        ▼
  3. Check events and conditions
     ├── kubectl get events -n <ns> --sort-by='.lastTimestamp'
     ├── kubectl get pods -n <ns> -o jsonpath for status conditions
     └── Node conditions: kubectl describe node <name>
        │
        ▼
  4. Diagnose root cause
     ├── Match symptoms to known failure modes (see decision trees)
     ├── Cross-reference events, logs, and resource state
     └── Check RBAC: kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>
        │
        ▼
  5. Recommend fix
     ├── Describe the root cause clearly
     ├── Provide the fix as a manifest change (use kubernetes-manifests skill)
     └── Or provide a handoff command if it's a one-liner (e.g., rollback)
```

### Decision Trees for Common Failures

**Pod stuck in Pending:**
```
Pending → kubectl describe pod → check Events
  ├── "Insufficient cpu/memory" → Node capacity issue → check kubectl top nodes
  ├── "no nodes available" → Taint/toleration mismatch or cluster autoscaler
  ├── "Unschedulable" → Node cordoned → kubectl get nodes
  └── "waiting for volume" → PVC not bound → check PVC and StorageClass
```

**CrashLoopBackOff:**
```
CrashLoopBackOff → kubectl logs <pod> --previous
  ├── Application error in logs → Fix application code/config
  ├── Exit code 137 → OOMKilled → Increase memory limits
  ├── Exit code 1 → App startup failure → Check env vars, config mounts
  └── Exit code 126/127 → Command not found → Check image and entrypoint
```

**ImagePullBackOff:**
```
ImagePullBackOff → kubectl describe pod → check Events
  ├── "unauthorized" → Missing/wrong imagePullSecrets
  ├── "not found" → Wrong image name or tag
  └── "timeout" → Network issue or registry down
```

**Service not reachable:**
```
Service unreachable → kubectl get endpoints <svc> -n <ns>
  ├── No endpoints → Selector doesn't match pod labels
  ├── Endpoints exist → Check NetworkPolicy blocking traffic
  └── External → Check Ingress, LoadBalancer status, DNS
```

### Exit Code Reference

| Code | Meaning | Common Cause |
|------|---------|-------------|
| 0 | Success | Normal termination |
| 1 | General error | Application error |
| 126 | Command not found | Wrong entrypoint |
| 127 | File not found | Missing binary in image |
| 137 | OOMKilled (SIGKILL) | Memory limit exceeded |
| 143 | SIGTERM | Graceful shutdown |

### Advanced Debugging

- **Ephemeral debug containers:** `kubectl debug -it <pod> --image=busybox --target=<container>`
- **Node debugging:** `kubectl debug node/<name> -it --image=busybox`
- **Network debugging pod:** Temporary pod with curl, nslookup, netcat for connectivity tests

### Read-Only Constraint

This skill only runs read-only commands by default:
- `kubectl get`, `describe`, `logs`, `top`, `auth can-i`, `get events`
- `kubectl debug` (creates ephemeral containers — confirm with user first)

Any write operation (`delete`, `patch`, `scale`, `rollout restart`) requires explicit user confirmation via handoff.

## Skill 3: `kubernetes-testing`

**Directory:** `skills/kubernetes-testing/`
**Parallels:** `infrastructure-testing`

### Purpose

Validate Kubernetes manifests and Helm charts before deployment. Catches misconfigurations, security violations, and policy non-compliance before they reach a cluster.

### Testing Pyramid

```
          ╱╲
         ╱  ╲         Layer 5: Integration (dry-run=server, handed off to user)
        ╱    ╲
       ╱──────╲
      ╱        ╲     Layer 4: Policy-as-Code (OPA/Gatekeeper, Kyverno)
     ╱          ╲
    ╱            ╲   Layer 3: Security Scanning (kubesec, trivy)
   ╱──────────────╲
  ╱                ╲
 ╱  Layer 2:        ╲ Schema Validation (kubeval, kubeconform)
╱  Schema            ╲
╱────────────────────╲
╱                      ╲
╱  Layer 1: Static      ╲ Lint + dry-run=client (ALWAYS, non-negotiable)
╱  Checks               ╲
╱────────────────────────╲
```

### Layers

**Layer 1 — Static Checks (always run):**
- `kubectl --dry-run=client -o yaml` — syntax validation
- `helm lint <chart>` — chart structure validation
- `helm template <chart>` — render templates, check output
- YAML syntax check (valid YAML, no tabs, correct indentation)

**Layer 2 — Schema Validation (always for new manifests):**
- `kubeconform -strict -kubernetes-version <ver>` — validate against K8s API schema
- `kubeval --strict` — alternative schema validator
- Check for deprecated API versions

**Layer 3 — Security Scanning (always for new code):**
- `kubesec scan <file>` — security risk scoring for manifests
- `trivy config .` — misconfiguration scanning
- `trivy image <image>` — container image vulnerability scanning
- Check: non-root, read-only rootfs, dropped capabilities, no privileged containers

**Layer 4 — Policy-as-Code (when compliance requires):**
- OPA/Gatekeeper: `conftest test <file> -p <policy-dir>`
- Kyverno: `kyverno apply <policy> --resource <manifest>`
- Common policies: enforce labels, deny `latest` tag, require resource limits, restrict host namespaces

**Layer 5 — Integration (handed off to user):**
- `kubectl apply --dry-run=server -f <file>` — server-side validation (requires cluster access)
- `helm install --dry-run --debug` — full Helm rendering with cluster validation
- `ct lint-and-install` — chart-testing tool for CI

### Helm-Specific Testing

- `helm lint` — structure and best practices
- `helm template` — render and inspect output
- `helm unittest` — unit tests for templates
- `helm test` — in-cluster test hooks (handed off to user)
- `ct lint-and-install` — CI tool for chart repos

### What This Skill Does NOT Do

- Does not apply manifests to clusters (use `kubernetes-manifests` handoff)
- Does not debug running workloads (use `kubernetes-debugging`)
- Does not write manifests from scratch (use `kubernetes-manifests`)

## Cross-Skill References

```
kubernetes-manifests ──writes──▶ kubernetes-testing ──validates──▶ user applies
                                                                        │
                                                                        ▼
                                                            kubernetes-debugging
                                                            (troubleshoot if issues)
```

- `kubernetes-manifests` → "For validation, use `kubernetes-testing`" / "For troubleshooting after apply, use `kubernetes-debugging`"
- `kubernetes-debugging` → "For manifest fixes, use `kubernetes-manifests`"
- `kubernetes-testing` → "For writing manifests, use `kubernetes-manifests`" / "For runtime issues, use `kubernetes-debugging`"

## Common Rationalizations (shared across all three skills)

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

## Red Flags (shared)

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

## Verification Checklists

### kubernetes-manifests
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

### kubernetes-debugging
- [ ] Only read-only commands executed
- [ ] Root cause identified with evidence (logs, events, describe output)
- [ ] Fix recommended as manifest change or handoff command
- [ ] No write operations without explicit user confirmation

### kubernetes-testing
- [ ] Layer 1 (static checks) passed
- [ ] Layer 2 (schema validation) passed for new manifests
- [ ] Layer 3 (security scan) passed for new code
- [ ] No critical/high vulnerabilities in images
- [ ] Deprecated API versions flagged
- [ ] Helm charts: lint + template + schema validation all pass

## File Structure

```
skills/
  kubernetes-manifests/
    SKILL.md                    # Core workflow, inline patterns, constraints, handoff
    workloads.md                # Deployment, StatefulSet, DaemonSet, Job, CronJob
    networking.md               # Services, Ingress, DNS, EndpointSlice
    configuration.md            # ConfigMaps, Secrets, External Secrets, Sealed Secrets
    storage.md                  # StorageClass, PV, PVC, CSI, snapshots
    helm-charts.md              # Chart structure, values, templates, hooks, testing
    gitops.md                   # ArgoCD, Flux, sealed secrets, repo strategies
    service-mesh.md             # Istio, Linkerd, traffic management, mTLS
    custom-operators.md         # CRD, Operator SDK, reconciler pattern
    cost-optimization.md        # VPA, HPA, spot instances, quotas, right-sizing
    multi-cluster.md            # Cluster API, cross-cluster networking, federation, DR
  kubernetes-debugging/
    SKILL.md                    # Diagnostic workflow, decision trees, exit codes, read-only constraint
  kubernetes-testing/
    SKILL.md                    # Testing pyramid, tool commands, Helm testing, verification
```

## Scope Boundaries

**In scope:**
- Kubernetes manifest authoring (YAML, Helm)
- Cluster debugging and inspection
- Pre-deployment validation and testing
- Security hardening patterns
- All workload types, networking, storage, configuration
- Advanced topics as reference files (service mesh, operators, multi-cluster, GitOps, cost optimization)

**Out of scope:**
- Terraform for cluster provisioning (use `infrastructure-as-code`)
- Cloud CLI for cluster inspection (use `infrastructure-discovery`)
- CI/CD pipeline configuration (use `ci-cd-and-automation`)
- Container image building (future `containers` skill)
