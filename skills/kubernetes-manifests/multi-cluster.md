# Multi-Cluster

Production-ready patterns for Kubernetes multi-cluster management and federation.

## Cluster API

Declarative cluster lifecycle — provision and manage Kubernetes clusters as Kubernetes resources.

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata: { name: production-east, namespace: clusters }
spec:
  clusterNetwork:
    pods: { cidrBlocks: ["192.168.0.0/16"] }
    services: { cidrBlocks: ["10.96.0.0/12"] }
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: production-east-cp
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
    kind: AWSCluster
    name: production-east
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: AWSMachineTemplate
metadata: { name: production-east-cp, namespace: clusters }
spec:
  template:
    spec: { instanceType: m6i.xlarge, iamInstanceProfile: control-plane.cluster-api-provider-aws.sigs.k8s.io, sshKeyName: cluster-admin }
---
apiVersion: controlplane.cluster.x-k8s.io/v1beta1
kind: KubeadmControlPlane
metadata: { name: production-east-cp, namespace: clusters }
spec:
  replicas: 3
  version: v1.29.2
  machineTemplate:
    infrastructureRef: { apiVersion: infrastructure.cluster.x-k8s.io/v1beta2, kind: AWSMachineTemplate, name: production-east-cp }
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDeployment
metadata: { name: production-east-workers, namespace: clusters }
spec:
  clusterName: production-east
  replicas: 5
  selector: { matchLabels: { cluster.x-k8s.io/cluster-name: production-east } }
  template:
    spec:
      clusterName: production-east
      version: v1.29.2
      bootstrap: { configRef: { apiVersion: bootstrap.cluster.x-k8s.io/v1beta1, kind: KubeadmConfigTemplate, name: production-east-workers } }
      infrastructureRef: { apiVersion: infrastructure.cluster.x-k8s.io/v1beta2, kind: AWSMachineTemplate, name: production-east-workers }
```

## Cross-Cluster Networking with Submariner

Submariner connects pod and service networks across clusters with encrypted tunnels.

```yaml
apiVersion: submariner.io/v1alpha1
kind: Broker
metadata: { name: submariner-broker, namespace: submariner-k8s-broker }
spec: { globalnetEnabled: true, defaultGlobalnetClusterSize: 65536 }
---
apiVersion: submariner.io/v1alpha1
kind: SubmarinerConfig
metadata: { name: submariner, namespace: submariner-operator }
spec:
  IPSecNATTPort: 4500
  cableDriver: libreswan
  clusterID: cluster-east
  serviceCIDR: 10.96.0.0/12
  clusterCIDR: 192.168.0.0/16
---
apiVersion: multicluster.x-k8s.io/v1alpha1   # Export service across clusters
kind: ServiceExport
metadata: { name: api-server, namespace: production }
---
apiVersion: multicluster.x-k8s.io/v1alpha1   # Import remote cluster service
kind: ServiceImport
metadata: { name: api-server, namespace: production }
spec:
  type: ClusterSetIP
  ports: [{ name: http, port: 80, protocol: TCP }]
```

## Cross-Cluster Networking with Cilium ClusterMesh

Cilium ClusterMesh provides transparent cross-cluster service discovery via global service annotations.

```yaml
# Enable via Helm: helm upgrade cilium cilium/cilium \
#   --set cluster.name=east --set cluster.id=1 \
#   --set clustermesh.useAPIServer.enabled=true
apiVersion: v1
kind: Service
metadata:
  name: api-server
  namespace: production
  annotations: { service.cilium.io/global: "true", service.cilium.io/shared: "true" }
spec:
  type: ClusterIP
  selector: { app: api-server }
  ports: [{ name: http, port: 80, targetPort: 8080 }]
```

## Cross-Cluster DNS

ExternalDNS with Route53 for external resolution, CoreDNS forward plugin for internal cross-cluster queries.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: external-dns, namespace: kube-system }
spec:
  selector: { matchLabels: { app: external-dns } }
  template:
    metadata: { labels: { app: external-dns } }
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:v0.14.0
          args: [--source=service, --source=ingress, --provider=aws, --registry=txt, --txt-owner-id=cluster-east, --domain-filter=example.com]
---
# CoreDNS — forward cross-cluster queries to remote CoreDNS
apiVersion: v1
kind: ConfigMap
metadata: { name: coredns-custom, namespace: kube-system }
data:
  cluster-west.server: |
    cluster-west.local:53 { forward . 10.200.0.10; cache 30 }
```

## Workload Distribution with KubeFed

Federate deployments across clusters with placement and per-cluster overrides.

```yaml
apiVersion: types.kubefed.io/v1beta1
kind: FederatedDeployment
metadata: { name: api-server, namespace: production }
spec:
  template:
    metadata: { labels: { app: api-server } }
    spec:
      replicas: 3
      selector: { matchLabels: { app: api-server } }
      template:
        metadata: { labels: { app: api-server } }
        spec:
          containers:
            - name: api-server
              image: api-server:1.2.0
              resources: { requests: { cpu: 250m, memory: 256Mi } }
  placement: { clusters: [{ name: cluster-east }, { name: cluster-west }] }
  overrides:
    - clusterName: cluster-west
      clusterOverrides: [{ path: "/spec/replicas", value: 5 }]
```

## Workload Distribution with ArgoCD ApplicationSet

Cluster generator deploys the same application across all matching clusters registered in ArgoCD.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: api-server, namespace: argocd }
spec:
  generators:
    - clusters: { selector: { matchLabels: { environment: production } } }
  template:
    metadata: { name: "api-server-{{name}}" }
    spec:
      project: default
      source:
        repoURL: https://github.com/org/k8s-manifests.git
        targetRevision: main
        path: "apps/api-server/overlays/{{metadata.labels.region}}"
      destination: { server: "{{server}}", namespace: production }
      syncPolicy: { automated: { prune: true, selfHeal: true } }
```

## Disaster Recovery with Velero

Schedule backups and restore across clusters for DR failover with weighted DNS.

```yaml
apiVersion: velero.io/v1
kind: Schedule
metadata: { name: daily-backup, namespace: velero }
spec:
  schedule: "0 2 * * *"
  template:
    includedNamespaces: [production, platform]
    storageLocation: aws-s3-primary
    volumeSnapshotLocations: [aws-ebs-east]
    ttl: 720h    # 30-day retention
    labelSelector: { matchLabels: { backup: enabled } }
---
apiVersion: velero.io/v1
kind: Restore
metadata: { name: dr-restore-production, namespace: velero }
spec:
  backupName: daily-backup-20260408020000
  includedNamespaces: [production]
  restorePVs: true
  existingResourcePolicy: update
---
# Active-passive DNS failover with weighted records
apiVersion: v1
kind: Service
metadata:
  name: api-server
  namespace: production
  annotations:
    external-dns.alpha.kubernetes.io/hostname: api.example.com
    external-dns.alpha.kubernetes.io/aws-weight: "100"
    external-dns.alpha.kubernetes.io/set-identifier: east
spec:
  type: LoadBalancer
  selector: { app: api-server }
  ports: [{ name: https, port: 443, targetPort: 8080 }]
```

## Centralized Management

Consolidate kubeconfig contexts with `kubectl config get-contexts` and `kubectl config use-context`.

```bash
kubectl config get-contexts                              # list clusters
kubectl config use-context production-east               # switch context
kubectl --context=production-west get pods -n production  # target without switching
KUBECONFIG=~/.kube/config:~/new.yaml kubectl config view --flatten > ~/.kube/merged
```

## Best Practices

1. Use Cluster API for declarative cluster provisioning — treat cluster lifecycle the same as workload lifecycle with GitOps.
2. Assign unique `cluster.id` and non-overlapping pod/service CIDRs to every cluster before enabling cross-cluster networking.
3. Use ServiceExport/ServiceImport (KEP-1645) for cross-cluster service discovery — it is the emerging multi-cluster standard.
4. Configure ExternalDNS `txt-owner-id` per cluster to prevent DNS record conflicts when multiple clusters share a zone.
5. Schedule Velero backups with 30-day retention and test restores monthly — untested backups are not backups.
6. Use ArgoCD ApplicationSet cluster generators over manual Application-per-cluster — scales automatically.
7. Keep cluster credentials in a secrets manager and rotate regularly — stale kubeconfigs are an attack vector.
8. Deploy critical services to at least two clusters in different regions with weighted DNS for failover.
