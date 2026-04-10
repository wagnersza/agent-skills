# Cost Optimization

Production-ready patterns for Kubernetes cost optimization and resource efficiency.

## Resource Right-Sizing

Analyze actual usage with `kubectl top pods --containers` and set requests to average + 10-20% buffer, limits at 2-4x CPU / 1.5-2x memory of requests.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-server
  labels: { app: api-server, cost-center: platform }
spec:
  containers:
    - name: api-server
      image: api-server:1.2.0
      resources:
        requests: { cpu: 250m, memory: 256Mi }   # observed avg + 20% buffer
        limits: { cpu: "1", memory: 512Mi }       # 4x/2x requests
```

## Vertical Pod Autoscaler (VPA)

Automatically right-size pods. Use `updateMode: "Off"` for recommendations only, `"Auto"` for automatic resizing.

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: api-server-vpa
spec:
  targetRef: { apiVersion: apps/v1, kind: Deployment, name: api-server }
  updatePolicy:
    updateMode: "Off"   # "Off" = recommendations only, "Auto" = automatic
  resourcePolicy:
    containerPolicies:
      - containerName: api-server
        minAllowed: { cpu: 100m, memory: 128Mi }
        maxAllowed: { cpu: "2", memory: 2Gi }
        controlledResources: [cpu, memory]
```

## HPA Tuning

Fine-tuned horizontal scaling with stabilization windows and custom metrics to prevent flapping.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-server-hpa
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: api-server }
  minReplicas: 2
  maxReplicas: 20
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
    - type: Pods
      pods:
        metric: { name: requests_per_second }
        target: { type: AverageValue, averageValue: "100" }
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - { type: Percent, value: 50, periodSeconds: 60 }
        - { type: Pods, value: 4, periodSeconds: 60 }
      selectPolicy: Max
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - { type: Percent, value: 10, periodSeconds: 120 }
      selectPolicy: Min
```

## Spot/Preemptible Instances

Schedule tolerant workloads on spot nodes with tolerations and affinity, backed by PodDisruptionBudget.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-worker
spec:
  replicas: 5
  selector: { matchLabels: { app: batch-worker } }
  template:
    metadata: { labels: { app: batch-worker } }
    spec:
      tolerations:
        - { key: cloud.google.com/gke-spot, operator: Equal, value: "true", effect: NoSchedule }
      nodeSelector: { node-lifecycle: spot }
      containers:
        - name: worker
          image: batch-worker:1.0.0
          resources:
            requests: { cpu: 500m, memory: 512Mi }
            limits: { cpu: "1", memory: 1Gi }
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: batch-worker-pdb
spec:
  minAvailable: 2
  selector: { matchLabels: { app: batch-worker } }
```

## Resource Quotas

Enforce per-namespace resource budgets to prevent runaway costs.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: team-budget, namespace: team-alpha }
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
    services.loadbalancers: "2"
```

## LimitRange

Set default requests/limits and enforce per-container min/max for containers that omit resource specs.

```yaml
apiVersion: v1
kind: LimitRange
metadata: { name: default-limits, namespace: team-alpha }
spec:
  limits:
    - type: Container
      default: { cpu: 500m, memory: 256Mi }
      defaultRequest: { cpu: 100m, memory: 128Mi }
      min: { cpu: 50m, memory: 64Mi }
      max: { cpu: "4", memory: 4Gi }
```

## Cluster Autoscaler

Configure scale-down thresholds, utilization targets, and node group balancing.

```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: cluster-autoscaler-config, namespace: kube-system }
data:
  scale-down-enabled: "true"
  scale-down-delay-after-add: "10m"
  scale-down-unneeded-time: "10m"
  scale-down-utilization-threshold: "0.5"
  balance-similar-node-groups: "true"
  expander: "least-waste"
```

## Scheduled Scaling

Scale down non-production workloads during off-hours and back up in the morning.

```yaml
# Scale down at 8 PM weekdays; create a matching scale-up CronJob at 7 AM
apiVersion: batch/v1
kind: CronJob
metadata: { name: scale-down-nonprod, namespace: platform-ops }
spec:
  schedule: "0 20 * * 1-5"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: scaler
          restartPolicy: OnFailure
          containers:
            - name: kubectl
              image: bitnami/kubectl:1.29
              command: ["/bin/sh", "-c"]
              args:
                - kubectl scale deploy --all --replicas=0 -n staging &&
                  kubectl scale deploy --all --replicas=0 -n dev
```

## Cost Monitoring Labels

Apply cost-center labels for Kubecost attribution and Prometheus metrics like `kube_pod_container_resource_requests`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  labels: { app: api-server, cost-center: platform, team: backend, environment: production }
spec:
  selector: { matchLabels: { app: api-server } }
  template:
    metadata:
      labels: { app: api-server, cost-center: platform, team: backend, environment: production }
      annotations: { kubecost.com/department: engineering, kubecost.com/project: api-platform }
```

## PriorityClass

Tier workloads so the scheduler evicts low-priority pods first during resource pressure.

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: critical }
value: 1000000
description: "System-critical workloads — never preempted"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: high }
value: 100000
description: "Revenue-generating production services"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: default }
value: 0
globalDefault: true
description: "Standard workloads — default tier"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: low }
value: -1000
preemptionPolicy: Never
description: "Batch jobs, dev workloads — preempted first"
```

## Best Practices

1. Always set resource requests and limits on every container — pods without requests are treated as BestEffort and evicted first.
2. Use VPA in `Off` mode first to collect recommendations before enabling `Auto` — avoid unexpected restarts in production.
3. Set HPA `scaleDown.stabilizationWindowSeconds` to at least 300s to prevent flapping during traffic spikes.
4. Run stateless, fault-tolerant workloads on spot instances and keep stateful services on on-demand nodes.
5. Apply `ResourceQuota` and `LimitRange` to every namespace — a single unbounded namespace can exhaust cluster resources.
6. Label all workloads with `cost-center`, `team`, and `environment` for accurate cost attribution and chargeback.
7. Schedule non-production environments to scale down during off-hours — this alone can cut dev/staging costs by 60%.
8. Define PriorityClasses and assign them to every Deployment — without priorities the scheduler cannot make intelligent eviction decisions.
