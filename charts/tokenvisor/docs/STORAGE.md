# Storage

> **Recommended path:** use `storage audit-s3 --apply` only when audit object storage is wanted. If that command uses external S3, run `storage seaweedfs --apply` before `storage model-pvcs --apply` when SeaweedFS-backed RWX model claims are also wanted. The bundled audit path already installs SeaweedFS and CSI.
>
> See [PREREQS_HELPER.md](PREREQS_HELPER.md) for all helper options. The manual steps below are for customization beyond the helper defaults.

TokenVisor chart expects storage to already exist. It references storage classes and model PVC settings.

The helper covers external audit S3 configuration, bundled SeaweedFS S3 + CSI installation, independent SeaweedFS + CSI installation for RWX model storage, and model PV/PVC creation as a separate operation. It does not install OpenEBS. Use the manual sections below for storage backend decisions and customization.

## What Is Mandatory

- A ReadWriteMany (RWX) model volume mounted at `/hf_repo`
- PVC name must be `nfs-model-storage-pvc`
- At minimum, PVC must exist in `tokenvisor` namespace

If `validation.lookupExistingResources=true`, `validation.failOnMissingModelPVC=true`, and `validation.failOnMissingStorageClass=true` (all default), Helm install fails fast when required PVCs or referenced storage classes are missing. For client-side `helm template` renders, set `validation.lookupExistingResources=false` because plain `helm template` cannot see existing cluster PVCs or storage classes.

## StorageClass Overrides (single place)

If your cluster does not use `openebs-three-replica`, create one override file and install with it.

```bash
export RWO_SC='<your-rwo-storage-class>'
cat > values.storage.yaml <<YAML
clickhouse:
  storageClassName: ${RWO_SC}
cnpg:
  storageClassName: ${RWO_SC}
victoriametrics:
  storageClassName: ${RWO_SC}
victoria-logs-single:
  server:
    persistentVolume:
      storageClassName: ${RWO_SC}
skypilot:
  pvc:
    storageClassName: ${RWO_SC}
YAML
```

Then install with:

```bash
helm upgrade --install tokenvisor . \
  --namespace tokenvisor \
  --create-namespace \
  -f values.yaml \
  -f values.storage.yaml
```

## RWX Model Storage Options

### Option A: Let chart create RWX PVC (dynamic provisioning)

Use this only if your RWX StorageClass supports dynamic provisioning.

```bash
export RWX_SC='<your-rwx-storage-class>'
cat > values.model-pvc.yaml <<YAML
storage:
  modelPvc:
    create: true
    name: nfs-model-storage-pvc
    storageClassName: ${RWX_SC}
    accessModes:
      - ReadWriteMany
    size: 20Gi
YAML
```

### Option B: Use pre-created RWX PVC

```bash
cat > values.model-pvc.yaml <<'YAML'
emu:
  modelStorage:
    existingClaim: nfs-model-storage-pvc
storage:
  modelPvc:
    create: false
YAML
```

Then create PVC manually (example in next section).

## Shared RWX Across Multiple Namespaces

If `skypilot` also needs the same underlying model data, create one PV+PVC pair per namespace.

- PVC name stays `nfs-model-storage-pvc` in each namespace
- Each PVC binds to its namespace-specific PV
- PVs can point to the same backend path (for example `/shared_hf_repo`)

Default-safe example (`tokenvisor` + `skypilot`), copy-paste ready:

```bash
cat > seaweedfs-model-storage.yaml <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: seaweedfs-tokenvisor-pv
spec:
  accessModes: [ReadWriteMany]
  capacity:
    storage: 20Gi
  csi:
    driver: seaweedfs-csi-driver
    volumeHandle: seaweedfs-tokenvisor-pv-id
    volumeAttributes:
      collection: default
      path: /shared_hf_repo
      concurrentReaders: "128"
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-model-storage-pvc
  namespace: tokenvisor
spec:
  storageClassName: ""
  volumeName: seaweedfs-tokenvisor-pv
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 20Gi
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: seaweedfs-skypilot-pv
spec:
  accessModes: [ReadWriteMany]
  capacity:
    storage: 20Gi
  csi:
    driver: seaweedfs-csi-driver
    volumeHandle: seaweedfs-skypilot-pv-id
    volumeAttributes:
      collection: default
      path: /shared_hf_repo
      concurrentReaders: "128"
  persistentVolumeReclaimPolicy: Retain
  volumeMode: Filesystem
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-model-storage-pvc
  namespace: skypilot
spec:
  storageClassName: ""
  volumeName: seaweedfs-skypilot-pv
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 20Gi
YAML

kubectl apply -f seaweedfs-model-storage.yaml
```

These static PVs intentionally omit the CSI `replication` attribute. Writes therefore use the SeaweedFS filer or master default instead of overriding the cluster's data-copy policy. See [CSI replication behavior](SEAWEEDFS.md#csi-replication-behavior).

## SeaweedFS Reference

SeaweedFS is only an example RWX backend. Operators can use any RWX-capable storage system.

For a full SeaweedFS install example, see `docs/SEAWEEDFS.md`.
