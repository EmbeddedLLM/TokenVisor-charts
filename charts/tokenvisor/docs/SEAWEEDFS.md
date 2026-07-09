# SeaweedFS Setup (RWX Example)

SeaweedFS is an example RWX backend for TokenVisor model storage.

TokenVisor does not require SeaweedFS specifically. Any RWX-capable backend is valid.

## 1) Install SeaweedFS

If this example uses `storageClass: local-path`, install `local-path` first:

```bash
cd charts/tokenvisor
./bin/tokenvisor-prereqs storage local-path --apply
```

For clusters using `volume.dataDirs[].type: hostPath`, choose the node that owns the host path and label it. A hostPath volume is local to that node; without a selector, Kubernetes can reschedule the SeaweedFS volume pod onto a different node that does not have the same data.

```bash
kubectl label node <seaweedfs-volume-node> tokenvisor.io/seaweedfs-volume=true
```

The chart uses `hostPath.type: DirectoryOrCreate`, so kubelet can create the host path. Create it yourself first only if you need to verify a mounted disk or set ownership/permissions:

```bash
sudo mkdir -p /data/seaweedfs_vol1
```

```bash
cat > seaweedfs-values.yaml <<'YAML'
global:
  seaweedfs:
    monitoring:
      enabled: true
    enableReplication: false

master:
  enabled: true
  replicas: 1
  data:
    type: persistentVolumeClaim
    size: 5Gi
    storageClass: local-path
  logs:
    type: persistentVolumeClaim
    size: 5Gi
    storageClass: local-path

volume:
  enabled: true
  replicas: 1
  nodeSelector: |
    tokenvisor.io/seaweedfs-volume: "true"
  dataDirs:
    - name: data1
      type: hostPath
      hostPathPrefix: /data/seaweedfs_vol1
      maxVolumes: 0

filer:
  enabled: true
  replicas: 1
  data:
    type: persistentVolumeClaim
    size: 25Gi
    storageClass: local-path
  logs:
    type: persistentVolumeClaim
    size: 25Gi
    storageClass: local-path
  s3:
    enabled: false
YAML

helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm
helm repo update
helm install seaweedfs seaweedfs/seaweedfs \
  --namespace seaweedfs \
  --create-namespace \
  -f seaweedfs-values.yaml \
  --version 4.29.0
```

Notes:

- The `local-path` StorageClass is used here for SeaweedFS master/filer PVCs. It must exist before `helm install seaweedfs ...`.
- This example is intentionally non-replicated: `global.seaweedfs.enableReplication=false` and `volume.replicas=1`.
- The volume server example uses `hostPath`, so it is intentionally pinned to nodes matching `volume.nodeSelector`.
- If you do not want hostPath pinning, use a PVC-backed `volume.dataDirs` entry with an appropriate StorageClass instead of `hostPath`.

### Two volume servers with SeaweedFS replication

For a two-node hostPath setup with one extra copy, label both intended storage nodes:

```bash
kubectl label node <seaweedfs-volume-node-a> tokenvisor.io/seaweedfs-volume=true
kubectl label node <seaweedfs-volume-node-b> tokenvisor.io/seaweedfs-volume=true
```

The chart can create the host path on both nodes. Create it yourself first only if you need to verify a mounted disk or set ownership/permissions:

```bash
sudo mkdir -p /data/seaweedfs_vol1
```

Use these overrides in `seaweedfs-values.yaml`:

```yaml
global:
  seaweedfs:
    monitoring:
      enabled: true
    enableReplication: true
    replicationPlacement: "001"

volume:
  enabled: true
  replicas: 2
  dataCenter: dc1
  rack: rack1
  nodeSelector: |
    tokenvisor.io/seaweedfs-volume: "true"
  dataDirs:
    - name: data1
      type: hostPath
      hostPathPrefix: /data/seaweedfs_vol1
      maxVolumes: 0
```

SeaweedFS replication strings are `XYZ`: replicas in other data centers, replicas in other racks in the same data center, and replicas on other volume servers in the same rack. `001` means one additional copy on another volume server in the same rack, for two total copies. With exactly two eligible volume server pods in `dc1/rack1`, replicated volumes need both pods available for placement. This is replication, not striping.

## 2) Install SeaweedFS CSI Driver

```bash
helm repo add seaweedfs-csi-driver https://seaweedfs.github.io/seaweedfs-csi-driver/helm
helm repo update
helm install seaweedfs-csi-driver seaweedfs-csi-driver/seaweedfs-csi-driver \
  --namespace seaweedfs \
  --set seaweedfsFiler=seaweedfs-filer.seaweedfs.svc:8888 \
  --set mountService.enabled=true \
  --set node.updateStrategy.type=OnDelete \
  --version 0.2.22
```

Note: When upgrading the SeaweedFS CSI Driver on a single-node cluster, default anti-affinity rules will cause the new `seaweedfs-csi-driver-controller` pod to get stuck in `Pending`. To complete the upgrade, manually delete the old pod.

## 3) Create model PV/PVCs

Create a PV+PVC pair per namespace that needs RWX model data (`tokenvisor`, `skypilot`).

Use the copy-paste manifest in `docs/STORAGE.md` under "Shared RWX Across Multiple Namespaces".

Minimum requirement for TokenVisor chart validation:

- PVC name: `nfs-model-storage-pvc`
- Namespace: `tokenvisor`

For TokenVisor chart wiring (`values.model-pvc.yaml`) and install commands, use:

- `docs/STORAGE.md`
- `README.md`

## References

- SeaweedFS Helm chart values: <https://github.com/seaweedfs/seaweedfs/blob/master/k8s/charts/seaweedfs/values.yaml>
- SeaweedFS replication docs: <https://github-wiki-see.page/m/seaweedfs/seaweedfs/wiki/Replication>
