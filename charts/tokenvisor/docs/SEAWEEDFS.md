# SeaweedFS: Bundled Audit S3 and Optional RWX Model Storage

TokenVisor requires an S3-compatible object store when inference audit media capture is enabled. Use an external S3 service, or let the prerequisite helper install a bundled SeaweedFS instance.

Audit object storage and RWX model storage are independent choices. The bundled audit path installs SeaweedFS and its CSI driver together. When audit storage is external, install SeaweedFS separately only if it is also wanted for RWX model storage. Creating the model PV/PVCs remains a separate explicit step.

## Recommended: prerequisite helper

Create the normal TokenVisor secrets first. The audit command patches only the two audit S3 keys into the existing `emu-secret`; it refuses to create an incomplete replacement secret.

```bash
cd charts/tokenvisor
./bin/tokenvisor-prereqs secrets init --interactive
./bin/tokenvisor-prereqs secrets apply
./bin/tokenvisor-prereqs storage audit-s3 --apply
```

The command first asks whether to use external S3-compatible storage. It configures storage only. Audit capture defaults to `opt_out`; set `EMU_AUDIT_RECORD_MODE=off` until the S3 storage is ready if storage and TokenVisor are deployed separately.

### External S3

Choose `y` for external storage and provide the endpoint, bucket, region, object-key prefix, and credentials. The helper does not install SeaweedFS or the CSI driver in this case. If SeaweedFS should independently provide RWX model storage, install it afterward:

```bash
./bin/tokenvisor-prereqs storage seaweedfs --apply
./bin/tokenvisor-prereqs storage model-pvcs --apply
```

The external bucket must already exist. Runtime credentials need object-level `PutObject`, `GetObject`, and `DeleteObject` access for the configured prefix; TokenVisor does not require `HeadBucket` or `CreateBucket`. The separate heavy orphan-reconciliation operation also requires bucket-level `ListBucket`, preferably restricted to that prefix.

Create the bucket with storage-administrator credentials before running the helper. For example, with the AWS CLI against an S3-compatible endpoint:

```bash
export S3_ENDPOINT="https://s3.example.com"
export S3_REGION="us-east-1"
export S3_BUCKET="tokenvisor-audit"

AWS_PROFILE=storage-admin aws \
  --endpoint-url "${S3_ENDPOINT}" \
  --region "${S3_REGION}" \
  s3 mb "s3://${S3_BUCKET}"
```

The provider's console or native tooling can be used instead. When the helper prompts for the endpoint, region, and audit bucket, enter the same values used to create the bucket. Supply restricted TokenVisor runtime credentials rather than the storage-administrator credentials used for this one-time operation.

It writes these ignored local files:

- `.local/audit-s3-values.yaml`: the non-secret EMU audit storage configuration.
- `.local/audit-s3-secret.yaml`: a JSON merge patch containing the two S3 credentials for `emu-secret`.

With `--apply`, the helper reuses the rendered configuration and merge-patches the two credential keys after confirming `emu-secret` exists; it does not replace the other secret keys or repeat the storage questionnaire. After creating the Studio values file described in `README.md`, build the consolidated TokenVisor values file:

```bash
./bin/tokenvisor-prereqs values build \
  .local/audit-s3-values.yaml \
  .local/studio-values.yaml
```

Then include the generated file in every TokenVisor Helm install or upgrade:

```bash
helm upgrade --install tokenvisor . \
  --namespace tokenvisor \
  -f .local/deployed-values.yaml
```

Set `EMU_AUDIT_RECORD_MODE` in the deployment values when overriding the default `opt_out` policy; see the administrator audit-record guide for `on`, `opt_in`, and `opt_out` behavior.

### Bundled SeaweedFS

Choose `n` for external storage. The helper prompts for:

- a StorageClass plus master and filer metadata sizes;
- the number of volume-server pods;
- the number of copies for stored data (`1`, `2`, or `3`);
- the number of data directories attached to each volume-server pod;
- whether volume-server data uses PVCs or node-local `hostPath`;
- a volume-data StorageClass and per-directory PVC size, or one host-path prefix per directory and the selected node names; and
- the audit bucket name.

Use Kubernetes quantities with an explicit unit for every storage size, such as `5Gi`, `100Gi`, or `1Ti`. A bare value such as `30` means 30 bytes, not 30 GiB.

The volume-server count and data-copy count are independent. SeaweedFS calls the underlying setting a replication placement: the helper maps one copy to `000`, two copies to `001`, and three copies to `002`. It requires at least as many volume servers as copies. The generated required pod anti-affinity places each volume-server pod on a distinct Kubernetes node. One copy and one volume server are the simple single-node default.

### Volume servers, data directories, and replication

A volume server is a storage process with its own data directories. Adding volume-server pods adds independent storage and placement targets; it does not itself duplicate data. With placement `000`, each SeaweedFS logical volume has one location, so different volume servers normally hold different logical volumes and different data. With `001`, each logical volume has its original copy plus one copy on another server in the same rack; `002` keeps two additional copies.

Each configured `dataDir` is attached to every volume-server pod. In PVC mode, the chart therefore creates one PVC per data directory per volume-server pod. Approximate capacity is:

```text
raw capacity = volume servers × data directories per server × capacity per directory
unique-data capacity = raw capacity ÷ data copies
```

For example, three volume servers with one 10 Gi data directory each provide approximately 30 Gi raw capacity. Placement `000` provides approximately 30 Gi of unique-data capacity; placement `001` stores two copies and provides approximately 15 Gi. Filesystem, index, free-space, compaction, and logical-volume allocation overhead reduce the actual capacity. If the selected StorageClass already replicates PVC data, SeaweedFS replication is an additional layer and multiplies physical backend consumption.

For hostPath storage, each prefix must refer to a distinct backing filesystem on every selected node for the capacity formula to hold. Multiple directories on the same filesystem do not add capacity, even though SeaweedFS sees multiple data directories.

A 10 Gi data directory does not impose a 10 Gi S3 object limit. The filer represents file content as one or more chunks, and chunks can be distributed across logical volumes on multiple volume servers. Losing a volume-server disk under `000` loses the only copy of its chunks; any S3 object using one of those chunks can no longer be reconstructed completely.

These behaviors are defined in the upstream [SeaweedFS architecture](https://github.com/seaweedfs/seaweedfs/wiki/SeaweedFS_Architecture.pdf), [blob-store and filer documentation](https://github.com/seaweedfs/seaweedfs#blob-store-architecture), [rack-aware replication documentation](https://github.com/seaweedfs/seaweedfs#rack-aware-and-data-center-aware-replication), and [Helm chart 4.39 values](https://github.com/seaweedfs/seaweedfs/blob/4.39/k8s/charts/seaweedfs/values.yaml).

For `hostPath`, the helper lists Ready nodes without cordons or hard scheduling taints and asks for an exact comma-separated selection by number. It records those node names as required node affinity in `.local/seaweedfs-values.yaml`, but it does not create, format, or mount host disks. Mount each intended backing filesystem at the entered prefix on every selected node. The chart appends `/object_store/` and may create that child directory, but it cannot create or mount the backing filesystem. Node-local data also does not follow a pod to another node; keep the selected nodes and their disks stable and plan recovery explicitly. Replacing or renaming a selected node requires deliberate storage recovery and regeneration of the SeaweedFS values.

For PVC-backed volume data, the selected StorageClass must already exist. If it is `local-path`, the helper installs the existing local-path provisioner when needed. Other StorageClasses remain an operator responsibility.

The data-directory count and StorageClass become StatefulSet volume-claim templates and are fresh-install topology choices; Kubernetes does not allow changing them in place. The chart has a separate resize hook for increasing an existing PVC's requested size.

Replication also needs an operational repair process. SeaweedFS does not automatically replace a missing logical-volume replica; the affected volume becomes read-only until an operator runs `volume.fix.replication`. Changing the helper's default placement affects new volume allocation only. Changing existing volumes requires `volume.configure.replication` followed by `volume.fix.replication`. See the upstream [replication operations documentation](https://github.com/seaweedfs/seaweedfs/wiki/Replication).

The bundled path installs these pinned upstream charts with `helm upgrade --install`:

- `seaweedfs/seaweedfs` `4.39.0`, with the authenticated filer S3 gateway enabled and the audit bucket created by the chart hook;
- `seaweedfs-csi-driver/seaweedfs-csi-driver` `0.2.30`.

It writes `.local/seaweedfs-values.yaml`, `.local/seaweedfs-csi-values.yaml`, and the helper-owned `.local/seaweedfs-s3-config-secret.yaml` in addition to the audit configuration files. The generated SeaweedFS values include the complete topology and hostPath node placement, so a later `storage audit-s3 --apply` reuses them without repeating the questionnaire. The two generated Secret files have mode `0600`.

The helper creates a small ConfigMap ownership marker before its first bundled install and upgrades only a release bearing that marker. A manually installed SeaweedFS or CSI release is never overwritten automatically. If `.local/seaweedfs-values.yaml` already exists, the helper warns and defaults to preserving it. Edit that file and apply Helm manually for an existing topology; explicitly replace it only when generating a new topology.

### Chart version and upgrades

The bundled prerequisite pins `seaweedfs/seaweedfs` chart `4.39.0`. This is a fresh-install pin, not a blanket in-place upgrade recommendation for an existing SeaweedFS cluster.

The `4.16.0` chart used replication and monitoring values directly under `global`; `4.39.0` nests them under `global.seaweedfs`. The helper renders the `4.39.0` layout. Applying old values to the new chart can silently leave master and filer replication at `000`.

Before upgrading an existing `4.16.0` release, take a backup or storage snapshot of master and filer data, save `helm get values <release> -n <namespace>`, run a reviewed `helm upgrade --dry-run --debug`, and perform the actual upgrade with `--wait`. Upgrade the SeaweedFS chart separately from the CSI driver, then verify authenticated S3 bucket access.

## Optional: SeaweedFS RWX model storage

TokenVisor requires RWX model storage when its model PVC is enabled. SeaweedFS is one supported RWX backend; it is not required if another RWX-capable storage system is already available.

If the bundled audit path installed SeaweedFS, create model claims only if TokenVisor and/or SkyPilot will use it for model data:

```bash
./bin/tokenvisor-prereqs storage model-pvcs --apply
```

This creates static RWX PV/PVC pairs for the `tokenvisor` and `skypilot` namespaces. The PVs omit a CSI replication override, so new writes inherit the SeaweedFS filer or master default. The command neither creates nor alters the audit bucket. See [STORAGE.md](STORAGE.md) for model claim details and other RWX backends.

When audit S3 is external, first install SeaweedFS without its S3 gateway:

```bash
./bin/tokenvisor-prereqs storage seaweedfs --apply
./bin/tokenvisor-prereqs storage model-pvcs --apply
```

The standalone `storage seaweedfs` command uses the same topology prompts and installs the same master, filer, volume servers, and CSI driver as the bundled audit path. It does not enable the SeaweedFS S3 gateway, create an audit bucket, or modify TokenVisor audit configuration.

### CSI replication behavior

SeaweedFS CSI replication is a write-time override, not a volume-server setting. When a static PV includes `spec.csi.volumeAttributes.replication`, or a StorageClass includes a `replication` parameter, the CSI driver passes that value explicitly to `weed mount`. Writes through that mount use the explicit value instead of the filer or master default. It does not reconfigure volume-server pods or change existing data.

When neither the PV nor the StorageClass specifies replication, the CSI driver omits the mount argument and lets the filer choose. The filer applies a matching path-specific rule when one exists, then falls back to its configured default and ultimately the master default. The helper-managed SeaweedFS values set the selected data-copy placement as both the filer and master default.

The default `seaweedfs-storage` StorageClass does not specify replication, so dynamically provisioned volumes inherit the cluster default. Dynamic provisioning is not equivalent to the model PVs generated by this helper, however: each dynamically provisioned PVC normally gets its own SeaweedFS path and collection. The static model PVs deliberately point the TokenVisor and SkyPilot claims at the same `/shared_hf_repo` path across two namespaces.

This behavior is present in the pinned CSI driver `v1.4.24` and remains unchanged in `v1.4.26`. See the upstream [`v1.4.24` mount argument construction](https://github.com/seaweedfs/seaweedfs-csi-driver/blob/v1.4.24/pkg/driver/mounter.go), [`v1.4.24` dynamic-volume handling](https://github.com/seaweedfs/seaweedfs-csi-driver/blob/v1.4.24/pkg/driver/controllerserver.go), and [`v1.4.26` mount implementation](https://github.com/seaweedfs/seaweedfs-csi-driver/blob/v1.4.26/pkg/driver/mounter.go).

## Advanced reference examples

The prerequisite helper configures any positive number of identically sized PVC data directories per pod. Heterogeneous directory sizes or StorageClasses, custom rack/data-center placement, and custom filer metadata stores remain operator-managed Helm overrides.

### Multiple hostPath data directories

Every selected volume node must have the same mounted paths:

```yaml
volume:
  replicas: 2
  affinity: |
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchFields:
              - key: metadata.name
                operator: In
                values:
                  - seaweedfs-volume-node-1
          - matchFields:
              - key: metadata.name
                operator: In
                values:
                  - seaweedfs-volume-node-2
  dataDirs:
    - name: data1
      type: hostPath
      hostPathPrefix: /mnt/seaweedfs-a
      maxVolumes: 0
    - name: data2
      type: hostPath
      hostPathPrefix: /mnt/seaweedfs-b
      maxVolumes: 0
```

### SeaweedFS replication over non-replicated PVC storage

Use this only when the volume-server pods are placed on distinct physical nodes:

```yaml
global:
  seaweedfs:
    enableReplication: true
    replicationPlacement: "001"
volume:
  replicas: 2
  dataDirs:
    - name: data1
      type: persistentVolumeClaim
      size: 100Gi
      storageClass: <non-replicated-storage-class>
      maxVolumes: 0
```

`002` similarly requires three distinct volume-server nodes. For replicated underlying volume PVCs, choose SeaweedFS copies deliberately because redundancy multiplies storage use.

## Existing manual SeaweedFS deployments

The helper intentionally does not adopt a release it did not create. To add S3 to an existing SeaweedFS deployment, make an operator-reviewed Helm values override and run your normal `helm upgrade` command. The essential values for the current upstream chart are:

```yaml
filer:
  s3:
    enabled: true
    enableAuth: true
    createBuckets:
      - name: tokenvisor-audit
        anonymousRead: false

s3:
  credentials:
    admin:
      accessKey: <audit-access-key>
      secretKey: <audit-secret-key>
```

The in-cluster endpoint is `http://<release>-s3.<namespace>.svc.cluster.local:8333`. Apply the same endpoint, bucket, credentials, region, and prefix to `emu-secret` and an EMU values override as shown in the external-S3 section. Do not enable both the standalone top-level `s3.enabled` gateway and `filer.s3.enabled` unless that topology is intentional.

## Operational notes

- The generated bundled configuration is single-replica by default. It is suitable for a simple deployment, not a production durability topology by itself.
- For a replicated SeaweedFS deployment, choose volume count, rack/data-center labels, replication placement, filer metadata backend, and backup strategy explicitly before adoption.
- SeaweedFS chart metrics are enabled in the bundled values. The TokenVisor platform prerequisite installs the `ServiceMonitor` CRD needed for chart-created monitors.
- The CSI driver uses `node.updateStrategy.type=OnDelete`. Upgrade its node pods deliberately, particularly on a single-node cluster with mounted CSI volumes.
