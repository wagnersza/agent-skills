# Storage

Production-ready patterns for Kubernetes storage resources.

## StorageClass

Cloud-specific storage classes with encryption and volume expansion.

```yaml
# AWS EBS gp3 with encryption and provisioned IOPS
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3-encrypted
provisioner: ebs.csi.aws.com
parameters: { type: gp3, encrypted: "true", iops: "3000", throughput: "125" }
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
---
# GCE PD with regional replication
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gce-pd-regional
provisioner: pd.csi.storage.gke.io
parameters: { type: pd-ssd, replication-type: regional-pd }
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
---
# Azure Premium SSD
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-premium
provisioner: disk.csi.azure.com
parameters: { skuName: Premium_LRS, cachingmode: ReadOnly }
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
---
# NFS via CSI driver
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs-server.storage.svc.cluster.local
  share: /exports/data
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions: [nfsvers=4.1, hard]
```

## PersistentVolume (Static Provisioning)

Pre-provisioned local volume with node affinity.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-node1
  labels: { type: local }
spec:
  capacity: { storage: 100Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: local-storage
  local: { path: /mnt/data }
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - { key: kubernetes.io/hostname, operator: In, values: [worker-node-1] }
```

## PersistentVolumeClaim

```yaml
# Dynamic provisioning — standard ReadWriteOnce
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  labels: { app: api-server }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-encrypted
  resources: { requests: { storage: 20Gi } }
---
# ReadWriteMany — shared storage (requires NFS or similar CSI)
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared-uploads
  labels: { app: media-service }
spec:
  accessModes: [ReadWriteMany]
  storageClassName: nfs-csi
  resources: { requests: { storage: 50Gi } }
---
# Block volume — raw device for databases managing their own filesystem
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: raw-block-pvc
spec:
  accessModes: [ReadWriteOnce]
  volumeMode: Block
  storageClassName: gp3-encrypted
  resources: { requests: { storage: 100Gi } }
```

## StatefulSet Volumes

Per-replica storage via `volumeClaimTemplates` — each replica gets its own PVC (e.g., `data-elasticsearch-0`).

```yaml
# Add to StatefulSet spec (see workloads.md for full StatefulSet pattern)
volumeClaimTemplates:
  - metadata: { name: data }
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: gp3-encrypted
      resources: { requests: { storage: 100Gi } }
```

## Volume Snapshots

Point-in-time backup of a PersistentVolumeClaim.

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: ebs-snapshot-class
driver: ebs.csi.aws.com
deletionPolicy: Retain
---
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-data-snapshot
  labels: { app: postgres }
spec:
  volumeSnapshotClassName: ebs-snapshot-class
  source: { persistentVolumeClaimName: data-postgres-0 }
```

## Volume Expansion

Enable `allowVolumeExpansion: true` in StorageClass, then increase the PVC request.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-postgres-0
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: gp3-encrypted
  resources:
    requests:
      storage: 100Gi    # increased from 50Gi — expansion happens online
```

## Ephemeral Volumes

```yaml
# Memory-backed — counts against container memory limit
volumes:
  - name: cache
    emptyDir: { medium: Memory, sizeLimit: 256Mi }

# Disk-backed — cleaned up when pod is deleted
volumes:
  - name: tmp
    emptyDir: { sizeLimit: 1Gi }

# Projected — combine secrets, configs, and pod metadata
volumes:
  - name: pod-info
    projected:
      sources:
        - secret:
            name: api-server-secrets
            items: [{ key: db-password, path: secrets/db-password, mode: 0400 }]
        - configMap:
            name: api-server-config
            items: [{ key: db-host, path: config/db-host }]
        - downwardAPI:
            items:
              - { path: labels, fieldRef: { fieldPath: metadata.labels } }
              - { path: cpu-limit, resourceFieldRef: { containerName: api-server, resource: limits.cpu } }
```

## CSI Examples

### AWS EBS CSI with KMS Encryption

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-kms-encrypted
provisioner: ebs.csi.aws.com
parameters: { type: gp3, encrypted: "true", kmsKeyId: "arn:aws:kms:us-east-1:123456789:key/abcd-1234" }
reclaimPolicy: Retain
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer
```

### Secrets Store CSI Driver

Mount cloud secrets as volumes without creating Kubernetes Secrets.

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "myplatform/production/api-server"
        objectType: "secretsmanager"
---
# Usage in pod spec
volumes:
  - name: secrets
    csi: { driver: secrets-store.csi.k8s.io, readOnly: true, volumeAttributes: { secretProviderClass: aws-secrets } }
```

## Best Practices

1. **Use `WaitForFirstConsumer`** binding mode to provision volumes in the same zone as the pod.
2. **Set `reclaimPolicy: Retain`** for production data to prevent accidental deletion.
3. **Enable `allowVolumeExpansion`** on StorageClasses to resize volumes without recreation.
4. **Use encryption at rest** — enable KMS encryption in cloud StorageClass parameters.
5. **Set `sizeLimit` on emptyDir** to prevent pods from consuming all node disk space.
6. **Take regular VolumeSnapshots** before destructive operations like upgrades or migrations.
7. **Use `ReadWriteOnce` by default** — only use `ReadWriteMany` when multiple pods need shared access.
8. **Separate data and logs** — use different volumes to manage lifecycle independently.
