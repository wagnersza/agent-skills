---
name: kubernetes-testing
description: Validates Kubernetes manifests and Helm charts before deployment using a five-layer testing pyramid. Use when validating new manifests, running schema checks against target cluster versions, security scanning manifests, checking policy compliance with OPA or Kyverno, testing Helm charts, or detecting deprecated APIs before upgrades.
---

# Kubernetes Testing

## Overview

Validate Kubernetes manifests and Helm charts before deployment. Catches misconfigurations, security violations, and policy non-compliance before they reach a cluster. The testing pyramid starts with zero-cost static checks at the base and builds up to server-side integration at the top. More tests at the bottom, fewer at the top.

## When to Use

- After writing new Kubernetes manifests
- Before deploying to any environment
- Validating Helm charts before release
- Checking for deprecated APIs before cluster upgrades
- Security scanning manifests for misconfigurations
- Policy compliance checks (SOC2, HIPAA, PCI)

**When NOT to use:**
- Writing Kubernetes manifests (use `kubernetes-manifests`)
- Debugging running workloads (use `kubernetes-debugging`)
- Testing Terraform code (use `infrastructure-testing`)

## The Testing Pyramid

```
          /\
         /  \         Layer 5: Integration (dry-run=server, handed off to user)
        /    \
       /------\
      /        \      Layer 4: Policy-as-Code (OPA/Gatekeeper, Kyverno)
     /          \
    /            \    Layer 3: Security Scanning (kubesec, trivy)
   /--------------\
  /                \
 /  Layer 2:        \  Schema Validation (kubeconform, kubeval)
/  Schema            \
/--------------------\
/                      \
/  Layer 1: Static      \  Lint + dry-run=client (ALWAYS, non-negotiable)
/  Checks                \
/------------------------\
```

| Layer | Gate | Tools | Cost |
|---|---|---|---|
| 1. Static | Always, non-negotiable | `kubectl --dry-run=client`, `helm lint`, `helm template` | Zero -- no cluster access needed |
| 2. Schema | Always for new manifests | `kubeconform`, `kubeval` | Zero -- static analysis only |
| 3. Security | Always for new code | `kubesec`, `trivy config` | Zero -- static analysis only |
| 4. Policy | When compliance requires | `conftest`, `kyverno apply` | Zero -- static analysis only |
| 5. Integration | Handed off to user | `kubectl --dry-run=server`, `helm install --dry-run` | Requires cluster access |

## Layer 1: Static Checks (Always)

Run these on every manifest change. No exceptions.

```bash
# Validate YAML syntax and basic Kubernetes structure
kubectl apply --dry-run=client -o yaml -f deployment.yaml

# Validate all manifests in a directory
kubectl apply --dry-run=client -o yaml -f manifests/

# Helm chart linting -- checks structure, values, templates
helm lint ./my-chart

# Helm template rendering -- catches template errors
helm template my-release ./my-chart --values values.yaml

# Render with specific values for different environments
helm template my-release ./my-chart --values values-prod.yaml
```

| Tool | What It Catches |
|---|---|
| `kubectl --dry-run=client` | Invalid YAML, unknown fields, missing required fields |
| `helm lint` | Chart structure issues, missing metadata, template syntax |
| `helm template` | Template rendering errors, invalid value references, nil pointer dereferences |

## Layer 2: Schema Validation (Always for New Manifests)

Validate manifests against the Kubernetes OpenAPI schema for a specific version.

```bash
# kubeconform -- strict mode, target cluster version
kubeconform -strict -kubernetes-version 1.29.0 deployment.yaml

# Validate all YAML in a directory
kubeconform -strict -kubernetes-version 1.29.0 -summary manifests/

# kubeval -- alternative, strict mode
kubeval --strict deployment.yaml

# kubeval with specific Kubernetes version
kubeval --strict --kubernetes-version 1.29.0 deployment.yaml
```

### Tool Check for Schema Validator

```
Is kubeconform or kubeval installed?
  +-- kubeconform available -> Use kubeconform (actively maintained, faster)
  +-- kubeval available -> Use kubeval
  +-- both available -> Use kubeconform
  +-- neither -> Ask user:
                "No schema validator found. Recommended for catching
                 invalid fields and deprecated APIs. Options:
                 - Install kubeconform: brew install kubeconform
                 - Install kubeval: brew install kubeval
                 - Skip this run only
                 - Skip for this session"
```

## Deprecated API Detection

Common migrations across Kubernetes versions:

| Deprecated API | Replacement | Removed In |
|---|---|---|
| `extensions/v1beta1` Ingress | `networking.k8s.io/v1` | 1.22 |
| `rbac.authorization.k8s.io/v1beta1` | `rbac.authorization.k8s.io/v1` | 1.22 |
| `policy/v1beta1` PodSecurityPolicy | Removed (use Pod Security Admission) | 1.25 |
| `autoscaling/v2beta1` HPA | `autoscaling/v2` | 1.26 |
| `flowcontrol.apiserver.k8s.io/v1beta2` | `flowcontrol.apiserver.k8s.io/v1` | 1.29 |

```bash
# kubent -- detect deprecated APIs in manifests and running clusters
kubent -f deployment.yaml

# Scan all manifests in a directory
kubent -f manifests/

# Scan a Helm chart (render first, then check)
helm template my-release ./my-chart | kubent -f -
```

## Layer 3: Security Scanning (Always for New Code)

Scan manifests for security misconfigurations before deployment.

```bash
# kubesec -- Kubernetes-specific security scoring
kubesec scan deployment.yaml

# kubesec with multiple files
kubesec scan deployment.yaml service.yaml

# trivy config -- scan manifests for misconfigurations
trivy config .

# trivy image -- scan container images for vulnerabilities
trivy image my-app:latest
```

### Pass/Fail Criteria

| Finding | Severity | Action |
|---|---|---|
| Container running as root | CRITICAL | Set `runAsNonRoot: true` in securityContext |
| No resource limits | HIGH | Add `resources.limits` for CPU and memory |
| Privileged container | CRITICAL | Remove `privileged: true` unless absolutely required |
| No readOnlyRootFilesystem | MEDIUM | Set `readOnlyRootFilesystem: true` in securityContext |
| Image with `latest` tag | HIGH | Pin to a specific digest or semver tag |
| Missing network policy | MEDIUM | Add NetworkPolicy to restrict pod traffic |

### Tool Check for Security Scanner

```
Is kubesec or trivy installed?
  +-- kubesec available -> Use kubesec for manifests
  +-- trivy available -> Use trivy config for manifests, trivy image for images
  +-- both available -> Use both (they catch different issues)
  +-- neither -> Ask user:
                "No security scanner found. Recommended for catching
                 misconfigurations (privileged containers, missing limits,
                 root execution). Options:
                 - Install kubesec: brew install kubesec
                 - Install trivy: brew install trivy
                 - Skip this run only
                 - Skip for this session"
```

## Layer 4: Policy-as-Code (When Compliance Requires)

Enforce organizational policies against manifests using OPA/conftest or Kyverno.

### OPA/Conftest -- Rego Policy

```bash
# Run policies against manifests
conftest test deployment.yaml -p policy/

# Test all manifests in a directory
conftest test manifests/ -p policy/
```

Example policy -- require labels:

```rego
# policy/labels.rego
package kubernetes

deny[msg] {
  input.kind == "Deployment"
  not input.metadata.labels["app.kubernetes.io/name"]
  msg := sprintf("Deployment '%s' must have app.kubernetes.io/name label", [input.metadata.name])
}

deny[msg] {
  input.kind == "Deployment"
  not input.metadata.labels["app.kubernetes.io/version"]
  msg := sprintf("Deployment '%s' must have app.kubernetes.io/version label", [input.metadata.name])
}
```

### Kyverno -- Policy

```bash
# Apply a Kyverno policy against a manifest
kyverno apply policy/deny-latest-tag.yaml --resource deployment.yaml
```

Example policy -- deny latest tag:

```yaml
# policy/deny-latest-tag.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: deny-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
    - name: deny-latest-tag
      match:
        any:
          - resources:
              kinds:
                - Pod
                - Deployment
                - StatefulSet
                - DaemonSet
      validate:
        message: "Image tag 'latest' is not allowed. Use a specific version."
        pattern:
          spec:
            =(initContainers):
              - image: "!*:latest"
            containers:
              - image: "!*:latest"
```

### When to Use Policy-as-Code

- Organization requires compliance guardrails (SOC2, HIPAA, PCI)
- Team needs to enforce labels, resource limits, or image policies
- You want to catch policy violations before deployment, not after

Don't mandate this for individual projects without compliance requirements.

## Layer 5: Integration (Handed Off to User)

Server-side validation requires cluster access. Always hand off execution.

```bash
# Server-side dry-run -- validates against admission controllers
kubectl apply --dry-run=server -f deployment.yaml

# Helm dry-run with debug -- tests against live cluster
helm install my-release ./my-chart --dry-run --debug

# chart-testing (ct) -- lint and install Helm charts
ct lint-and-install --charts ./my-chart
```

### Handoff Template

```
Integration tests ready to run!

Execute:  kubectl apply --dry-run=server -f manifests/
Requires: Cluster access with appropriate RBAC permissions
Effect:   Validates against server-side admission controllers (no resources created)
```

For Helm chart testing that creates resources:

```
Helm integration test ready!

Execute:  ct lint-and-install --charts ./my-chart
Creates:  Namespace, all chart resources (in test namespace -- destroyed after)
Cleanup:  Automatic -- ct removes test namespace after completion
Requires: Cluster access with namespace creation permissions
```

## Helm-Specific Testing

| Stage | Command | What It Checks |
|---|---|---|
| Lint | `helm lint ./chart` | Chart structure, required metadata, template syntax |
| Template | `helm template release ./chart` | Template rendering, value substitution |
| Unit Test | `helm unittest ./chart` | Individual template assertions (requires helm-unittest plugin) |
| Schema | `kubeconform <(helm template r ./chart)` | Rendered manifests against K8s schema |
| Test (in-cluster) | `helm test release` | In-cluster test pods (handoff to user) |
| Chart Testing | `ct lint-and-install` | Full lifecycle lint, install, test, delete (handoff to user) |

```bash
# Full local Helm validation pipeline
helm lint ./my-chart \
  && helm template my-release ./my-chart --values values.yaml \
  | kubeconform -strict -kubernetes-version 1.29.0 -summary
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Helm lint passed, so the chart is correct" | Lint checks structure, not semantics. Run template + kubeconform too. |
| "dry-run=client is enough" | Client-side does not check server-side admission. Use both when cluster available. |
| "Security scanning is overkill for internal manifests" | Internal is where lateral movement starts. Scan everything. |
| "We don't need policy checks for dev" | Dev bad habits become prod incidents. Enforce everywhere. |
| "The schema hasn't changed" | APIs get deprecated every release. Always validate against target version. |

## Red Flags

- Skipping validation before `kubectl apply`
- Only running lint without schema validation
- Ignoring security scan results or suppressing findings without justification
- Not checking deprecated APIs before cluster upgrades
- Applying manifests without dry-run first
- Using `latest` tag without any image policy enforcement
- Missing resource limits on production workloads

## Verification

After testing Kubernetes manifests:

- [ ] Layer 1 (static checks) passed -- `kubectl --dry-run=client` or `helm lint` + `helm template`
- [ ] Layer 2 (schema validation) passed for new manifests -- `kubeconform` or `kubeval`
- [ ] Layer 3 (security scan) passed for new code -- `kubesec` or `trivy config`
- [ ] No critical/high vulnerabilities in images -- `trivy image`
- [ ] Deprecated API versions flagged and migrated -- `kubent`
- [ ] Helm charts: lint + template + schema validation all pass

## See Also

- For writing Kubernetes manifests, use the `kubernetes-manifests` skill
- For debugging running workloads, use the `kubernetes-debugging` skill
- For testing Terraform code, use the `infrastructure-testing` skill
