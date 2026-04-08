---
name: kubernetes-debugging
description: Inspects and troubleshoots running Kubernetes clusters using read-only commands. Use when pods fail to start (Pending), pods crash (CrashLoopBackOff), image pull errors occur, services are unreachable, DNS resolution fails, resource usage is high, PersistentVolumeClaims are stuck, or RBAC permission errors appear. Never runs write operations without explicit user confirmation.
---

# Kubernetes Debugging

## Overview

Read-only inspection and troubleshooting of running Kubernetes clusters. The agent inspects resources, reads logs, checks events, and diagnoses root causes. No write operations without explicit user confirmation. Every fix is presented as a recommended command or manifest change — never executed directly.

## When to Use

- Pod not starting (stuck in Pending)
- Pod crashing repeatedly (CrashLoopBackOff)
- Image pull failures (ImagePullBackOff, ErrImagePull)
- Service unreachable (no response, connection refused, timeout)
- DNS resolution issues inside the cluster
- High resource usage (CPU throttling, memory pressure)
- PersistentVolumeClaim problems (Pending PVC, mount failures)
- RBAC permission errors (Forbidden responses)

**When NOT to use:**
- Writing new Kubernetes manifests (use `kubernetes-manifests`)
- Validating manifests before deploy (use `kubernetes-testing`)
- Cloud-level cluster issues — node provisioning, control plane, networking at the cloud layer (use `infrastructure-discovery`)

## The Workflow

```
Symptom: Something is wrong in the cluster
        |
        v
  1. Identify symptoms
     |-- Pod not starting? (Pending, Init, ContainerCreating)
     |-- Pod crashing? (CrashLoopBackOff, Error, OOMKilled)
     |-- Service unreachable? (no endpoints, timeout, refused)
     +-- Performance? (high CPU, memory pressure, throttling)
        |
        v
  2. Inspect resources (read-only)
     |-- kubectl get pods -n <ns> -o wide
     |-- kubectl describe pod <name> -n <ns>
     |-- kubectl logs <pod> -n <ns> [--previous] [-c container]
     +-- kubectl top pods -n <ns>
        |
        v
  3. Check events and conditions
     |-- kubectl get events -n <ns> --sort-by='.lastTimestamp'
     |-- Pod conditions (Ready, Initialized, ContainersReady)
     +-- Node conditions (MemoryPressure, DiskPressure, PIDPressure)
        |
        v
  4. Diagnose root cause
     |-- Match symptoms to decision trees below
     |-- Cross-reference logs, events, and describe output
     +-- Check RBAC if permission-related
        |
        v
  5. Recommend fix
     |-- State the root cause with evidence
     |-- Provide manifest change via kubernetes-manifests skill
     +-- Or provide handoff command for user to execute
```

## Decision Trees

### Pod Stuck in Pending

```
Pod status: Pending
    |
    +-- Events show "Insufficient cpu" or "Insufficient memory"
    |   -> Node capacity exhausted. Scale node pool or reduce requests.
    |
    +-- Events show "0/N nodes are available" with taint message
    |   -> Taint/toleration mismatch. Check pod tolerations and node taints.
    |
    +-- Events show "Unschedulable"
    |   -> Node is cordoned. Run: kubectl get nodes (look for SchedulingDisabled)
    |
    +-- Events show "waiting for volume" or PVC Pending
        -> PVC not bound. Check PVC status, StorageClass, and provisioner.
```

### CrashLoopBackOff

```
Pod status: CrashLoopBackOff
    |
    +-- Logs show application error
    |   -> Application bug. Read logs, identify the error, fix the code.
    |
    +-- Exit code 137 (OOMKilled)
    |   -> Container exceeded memory limit. Increase resources.limits.memory.
    |
    +-- Exit code 1 (general error)
    |   -> Startup failure. Check environment variables, config maps, secrets.
    |
    +-- Exit code 126 or 127 (command/file not found)
        -> Wrong entrypoint or image. Verify the container image and command.
```

### ImagePullBackOff

```
Pod status: ImagePullBackOff or ErrImagePull
    |
    +-- Events show "unauthorized" or "denied"
    |   -> Missing or incorrect imagePullSecrets. Check secret exists and is
    |      referenced in the pod spec.
    |
    +-- Events show "not found" or "manifest unknown"
    |   -> Wrong image name or tag. Verify image exists in the registry.
    |
    +-- Events show "timeout" or "i/o timeout"
        -> Network issue or registry unreachable. Check DNS resolution and
           network policies.
```

### Service Not Reachable

```
Service returns timeout or connection refused
    |
    +-- kubectl get endpoints <svc> shows no endpoints
    |   -> Selector mismatch. Compare service selector with pod labels.
    |      Run: kubectl get svc <svc> -o yaml   (check spec.selector)
    |      Run: kubectl get pods --show-labels   (check pod labels)
    |
    +-- Endpoints exist but connection fails
    |   -> NetworkPolicy blocking traffic. Check NetworkPolicy rules.
    |      Run: kubectl get networkpolicy -n <ns>
    |
    +-- External traffic fails (works inside cluster)
        -> Ingress, LoadBalancer, or DNS misconfiguration. Check:
           kubectl get ingress -n <ns>
           kubectl describe svc <svc> -n <ns>  (check external IP/hostname)
```

## Essential kubectl Commands

### Pod Inspection

```bash
# List pods with node placement and IP
kubectl get pods -n <ns> -o wide

# Full pod details — events, conditions, volumes, containers
kubectl describe pod <name> -n <ns>

# Current logs
kubectl logs <pod> -n <ns>

# Previous container logs (after a crash)
kubectl logs <pod> -n <ns> --previous

# Logs for a specific container in a multi-container pod
kubectl logs <pod> -n <ns> -c <container>
```

### Resource Usage

```bash
# Pod CPU and memory consumption
kubectl top pods -n <ns>

# Node CPU and memory consumption
kubectl top nodes
```

### Events

```bash
# Namespace events sorted by time (most recent last)
kubectl get events -n <ns> --sort-by='.lastTimestamp'

# All cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'
```

### Service and Networking

```bash
# Endpoints backing a service (empty = selector mismatch)
kubectl get endpoints <svc> -n <ns>

# Service details — type, ports, selector
kubectl get svc -n <ns>

# Network policies in the namespace
kubectl get networkpolicy -n <ns>
```

### RBAC

```bash
# List all permissions for a service account
kubectl auth can-i --list --as=system:serviceaccount:<ns>:<sa>

# Check a specific permission
kubectl auth can-i get pods --as=system:serviceaccount:<ns>:<sa> -n <ns>
```

### Nodes

```bash
# Full node details — conditions, capacity, allocatable, taints
kubectl describe node <name>

# Node list with IPs and versions
kubectl get nodes -o wide
```

## Exit Code Reference

| Exit Code | Meaning | Common Cause |
|---|---|---|
| 0 | Success | Process exited normally |
| 1 | General error | Application error, unhandled exception, bad config |
| 126 | Command not found | Binary exists but is not executable |
| 127 | File not found | Binary does not exist in the container image |
| 137 | OOMKilled (SIGKILL) | Container exceeded memory limit, or killed by the kernel |
| 143 | SIGTERM | Graceful shutdown requested (preStop hook, rolling update) |

## Advanced Debugging

### Ephemeral Debug Containers

Attach a debug container to a running pod without restarting it. Requires Kubernetes 1.23+ and the EphemeralContainers feature.

```bash
# Attach a busybox shell to a running pod
kubectl debug -it <pod> --image=busybox --target=<container>

# Attach with network tools
kubectl debug -it <pod> --image=nicolaka/netshoot --target=<container>
```

**Requires user confirmation** — this modifies the pod spec.

### Node Debugging

Start a privileged pod on a node for host-level inspection:

```bash
kubectl debug node/<name> -it --image=busybox
```

**Requires user confirmation** — this creates a privileged pod on the node.

### Network Debugging Pod

Deploy a temporary pod for DNS and connectivity testing:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: debug-network
  namespace: <ns>
spec:
  containers:
  - name: debug
    image: nicolaka/netshoot
    command: ["sleep", "3600"]
  restartPolicy: Never
```

Then run connectivity checks:

```bash
# DNS resolution
kubectl exec debug-network -n <ns> -- nslookup <service>.<ns>.svc.cluster.local

# HTTP connectivity
kubectl exec debug-network -n <ns> -- curl -sv http://<service>:<port>/healthz

# TCP port check
kubectl exec debug-network -n <ns> -- nc -zv <service> <port>
```

**Requires user confirmation** — this creates a pod in the cluster.

### Database Client Debug Pod

Deploy a temporary pod with database clients for connection testing:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: debug-db
  namespace: <ns>
spec:
  containers:
  - name: debug
    image: postgres:16-alpine
    command: ["sleep", "3600"]
  restartPolicy: Never
```

Then test connectivity:

```bash
# PostgreSQL connection test
kubectl exec debug-db -n <ns> -- pg_isready -h <host> -p 5432 -U <user>

# MySQL connection test (use mysql:8 image instead)
kubectl exec debug-db -n <ns> -- mysqladmin ping -h <host> -u <user> -p
```

**Requires user confirmation** — this creates a pod in the cluster.

## Read-Only Constraint

### Allowed Commands (no confirmation needed)

These commands inspect state and produce no side effects:

- `kubectl get` — list and display resources
- `kubectl describe` — show detailed resource information
- `kubectl logs` — read container logs
- `kubectl top` — show resource usage metrics
- `kubectl auth can-i` — check RBAC permissions
- `kubectl api-resources` — list available resource types
- `kubectl explain` — show resource schema documentation

### Commands Requiring User Confirmation

- `kubectl debug` — creates ephemeral containers or debug pods
- `kubectl exec` — executes commands inside running containers
- `kubectl port-forward` — opens local port tunnels

### Never Execute Without Handoff

Any command that modifies cluster state requires a handoff:

- `kubectl apply`, `kubectl create`, `kubectl patch`
- `kubectl delete`, `kubectl drain`, `kubectl cordon`
- `kubectl scale`, `kubectl rollout restart`
- `kubectl edit`, `kubectl label`, `kubectl annotate`

Present these as a recommended action with the exact command, expected effect, and verification steps.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I know what the cluster state is" | Run the commands. Assumptions kill uptime. |
| "I'll just restart the pod to fix it" | Restarting masks the root cause. Diagnose first. |
| "The logs should be enough" | Logs + events + describe + resource usage. Cross-reference everything. |
| "I can delete this stuck pod" | Never delete without user confirmation. Investigate why it's stuck. |
| "RBAC is probably fine" | Verify with `kubectl auth can-i`. Permission issues are silent. |

## Red Flags

- Running write commands (`apply`, `delete`, `scale`) without user confirmation
- Diagnosing without checking events (`kubectl get events`)
- Restarting pods as the first action instead of investigating
- Ignoring exit codes in CrashLoopBackOff situations
- Not checking resource limits when a pod crashes (OOMKilled is common)

## Verification

After completing a debugging session:

- [ ] Only read-only commands executed (no cluster state modified)
- [ ] Root cause identified with evidence (logs, events, describe output)
- [ ] Fix recommended as manifest change or handoff command
- [ ] No write operations performed without explicit user confirmation

## See Also

- For writing Kubernetes manifests, use the `kubernetes-manifests` skill
- For validating manifests before deploy, use the `kubernetes-testing` skill
- For cloud-level cluster inspection, use the `infrastructure-discovery` skill
