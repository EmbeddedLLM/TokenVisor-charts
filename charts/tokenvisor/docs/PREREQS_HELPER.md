# Prerequisite Helper

`bin/tokenvisor-prereqs` is the recommended way to bootstrap the standard TokenVisor chart prerequisites. Use the manual docs when you need customization, when your cluster already has equivalent infrastructure, or for prerequisite areas the helper intentionally leaves as operator decisions.

The helper covers:

- platform CRDs/operators required by the chart
- optional Grafana and Fluent operators
- conditional NVIDIA/AMD GPU operators for SkyPilot workloads
- local app secrets and GHCR pull secrets
- upstream SkyPilot API server
- local-path installation for RKE2/dev clusters
- SeaweedFS CSI model PV/PVC manifests after SeaweedFS is installed
- readiness checks before installing TokenVisor

The helper intentionally does not install Kubernetes/CNI, OpenEBS, or SeaweedFS.

Run commands from the chart root:

```bash
cd charts/tokenvisor
./bin/tokenvisor-prereqs --help
```

Commands that change the cluster require `--apply`. When `--apply` is omitted, the helper only reviews what it would do or renders the local manifest/value file. Use `--yes` with `--apply` for non-interactive automation.

## Failure and rerun behavior

The helper is forward-only. If a step fails, earlier successful steps remain in the cluster. Fix the cause and rerun the same command.

The helper is intended to be safe to rerun on an already bootstrapped or partially bootstrapped cluster. It skips known existing resources where needed, and most apply/install actions use `kubectl apply` or `helm upgrade --install`.

It is not a rollback or drift-management tool. Immutable Kubernetes field changes, changed Helm values, or manually modified operator installs may still require operator review.

## Recommended bootstrap flow

Use this sequence from the chart root after the Kubernetes cluster and CNI are ready:

```bash
cd charts/tokenvisor

# Platform CRDs/operators.
./bin/tokenvisor-prereqs platform --apply
# If enabling grafana.enabled or fluentbit.enabled, use this apply command instead.
# Apply docs/HOST_SETUP.md first when enabling fluentbit.enabled on production/RKE2 nodes.
./bin/tokenvisor-prereqs platform --include-grafana --include-fluent --apply

# Optional GPU operator path, only if SkyPilot will run GPU workloads.
./bin/tokenvisor-prereqs gpu nvidia --apply
# or:
./bin/tokenvisor-prereqs gpu amd --apply

# Storage backend remains an operator decision.
# If using local-path-backed storage on RKE2/dev clusters, install it before
# installing SeaweedFS or any other chart that references storageClass: local-path.
./bin/tokenvisor-prereqs storage local-path --apply

# Install SeaweedFS from docs/SEAWEEDFS.md, or use another RWX backend.

# If using SeaweedFS CSI static PVs for model storage:
./bin/tokenvisor-prereqs storage model-pvcs --apply

# App secrets.
./bin/tokenvisor-prereqs secrets init --interactive
# view/edit the secrets in .local/tokenvisor-secrets.yaml
./bin/tokenvisor-prereqs secrets apply

# Private GHCR pull secrets.
export GHCR_USERNAME='<github-username>'
export GHCR_TOKEN='<github-pat-with-read-packages>'
./bin/tokenvisor-prereqs secrets ghcr --apply

# SkyPilot API server.
./bin/tokenvisor-prereqs skypilot --apply

helm dependency update .
./bin/tokenvisor-prereqs check
```

`helm dependency update .` downloads chart dependencies into the local ignored `charts/` directory.

When `check` passes, install the TokenVisor Helm release using the README install command and your local values files.

## Platform bootstrap

```bash
./bin/tokenvisor-prereqs platform --apply
```

Include optional operators:

```bash
./bin/tokenvisor-prereqs platform --include-grafana --apply
./bin/tokenvisor-prereqs platform --include-fluent --apply
```

Before using `--include-fluent` on production/RKE2 nodes, apply the host inotify sysctl settings from `docs/HOST_SETUP.md` on every node.

For non-interactive use:

```bash
./bin/tokenvisor-prereqs platform --apply --yes
```

The platform phase:

- creates the `tokenvisor` and `skypilot` namespaces
- applies Gateway API CRDs
- creates `GatewayClass/cilium` only if Cilium pods are detected and the class is missing
- applies `ServiceMonitor` and `PodMonitor` CRDs
- installs the required VictoriaMetrics, Dragonfly, ClickHouse, and CNPG operators
- patches the Dragonfly operator metrics binding to `0.0.0.0:8080`
- optionally installs the Grafana Operator when `--include-grafana` is passed
- optionally installs the Fluent Operator when `--include-fluent` is passed

The generated operator values are written under `.local/`.

## Storage

This helper does not install OpenEBS. OpenEBS/Mayastor requires host preparation, node labels, disk choices, and DiskPool manifests. Follow the storage docs for that path.

For RKE2/dev clusters that need `local-path`:

```bash
./bin/tokenvisor-prereqs storage local-path --apply
```

This skips if `StorageClass/local-path` already exists. Otherwise, it installs Rancher local-path-provisioner `v0.0.34`. It does not mark `local-path` as the default StorageClass.

This helper also does not install SeaweedFS yet. SeaweedFS topology has real choices such as hostPath vs. PVC-backed volume servers, node placement, and backing storage class. Follow `docs/SEAWEEDFS.md` first.

After SeaweedFS CSI is installed, create the static model PV/PVC manifests:

```bash
./bin/tokenvisor-prereqs storage model-pvcs --apply
```

Defaults:

- shared SeaweedFS path: `/shared_hf_repo`
- Kubernetes PV/PVC binding size: `20Gi`

Customize them only if needed:

```bash
./bin/tokenvisor-prereqs storage model-pvcs \
  --path /custom_hf_repo \
  --size 100Gi \
  --apply
```

The generated manifest is written to `.local/seaweedfs-model-storage.yaml`. For SeaweedFS CSI static PVs, `--size` is Kubernetes PV/PVC binding metadata; it is not a hard SeaweedFS quota.

Check storage readiness:

```bash
./bin/tokenvisor-prereqs storage check
```

## GPU operators

GPU setup is conditional. Use this only if SkyPilot will run GPU workloads.

Check whether GPU operator/runtime pods already exist:

```bash
./bin/tokenvisor-prereqs gpu check
```

Install the NVIDIA GPU Operator path:

```bash
./bin/tokenvisor-prereqs gpu nvidia --apply
```

The NVIDIA command checks for NVIDIA GPU Operator/runtime pods across all namespaces first. If pods such as `gpu-operator`, `nvidia-gpu-operator`, `gpu-feature-discovery`, `nvidia-device-plugin-daemonset`, `nvidia-container-toolkit-daemonset`, or `nvidia-dcgm-exporter` already exist, it prints them and skips installation.

By default, the helper installs the NVIDIA chart as Helm release `gpu-operator` in namespace `gpu-operator` with:

- `driver.enabled=false`
- `toolkit.enabled=false`
- `migManager.enabled=false`

Override the namespace if needed:

```bash
./bin/tokenvisor-prereqs gpu nvidia --namespace nvidia-gpu-operator --apply
```

Install the AMD GPU Operator path:

```bash
./bin/tokenvisor-prereqs gpu amd --apply
```

The AMD command installs cert-manager, writes `.local/amd-metrics-exporter-config.yaml`, applies it, and installs the ROCm GPU Operator chart in namespace `amd-gpu-operator`.

After either vendor path, follow `docs/GPU.md` for node/runtime notes.

## Check readiness

```bash
./bin/tokenvisor-prereqs check
```

For single-node installs:

```bash
TOKENVISOR_MODE=single-node ./bin/tokenvisor-prereqs check
```

The check validates local tools, namespaces, Gateway API, required operator CRDs, model PVC, required secrets and keys, the TokenVisor GHCR pull secret, SkyPilot service, and the VictoriaLogs chart dependency. It also reports optional prerequisites such as `local-path`, SeaweedFS CSI, Grafana, Fluent Bit, and GPU operator/runtime pods without failing when they are absent.

## SkyPilot

```bash
./bin/tokenvisor-prereqs skypilot --apply
```

Defaults:

- Helm release: `skypilot`
- namespace: `skypilot`
- chart version: `0.12.0`
- image: `ghcr.io/embeddedllm/skypilot:v0.12.0`
- storage class: `openebs-three-replica`

Customize common settings:

```bash
./bin/tokenvisor-prereqs skypilot \
  --sc '<your-storage-class>' \
  --image '<your-skypilot-image>' \
  --apply
```

The generated upstream chart values are written to `.local/skypilot-values.yaml`. Use `docs/SKYPILOT.md` for deeper customization.

## Create namespaces

```bash
./bin/tokenvisor-prereqs create-namespaces --apply
```

## Prepare secrets

Create a local editable secrets file from the template:

```bash
./bin/tokenvisor-prereqs secrets init
```

Or use the interactive generator. It creates secure defaults for required internal secrets, Grafana admin password, and `EMU_DB_PATH`. Internal secret/password prompts are hidden following standard password-entry practice. Provider API key prompts are visible for paste verification; press Enter to leave them empty.

```bash
./bin/tokenvisor-prereqs secrets init --interactive
```

Edit .local/tokenvisor-secrets.yaml

Apply after replacing all `CHANGE_ME_` values:

```bash
./bin/tokenvisor-prereqs secrets apply
```

The helper refuses to apply the file while `CHANGE_ME_` placeholders remain. It creates namespaces referenced by the manifest before applying the secrets.

## Create GHCR pull secrets

```bash
export GHCR_USERNAME='<github-username>'
export GHCR_TOKEN='<github-pat-with-read-packages>'
./bin/tokenvisor-prereqs secrets ghcr --apply
```

This creates or updates `registry-secret` in the `tokenvisor` namespace.

## Namespace overrides

Defaults are `tokenvisor` and `skypilot`. Override if needed:

```bash
TOKENVISOR_NAMESPACE=tokenvisor-prod \
SKYPILOT_NAMESPACE=skypilot-prod \
./bin/tokenvisor-prereqs check
```

If you use non-default namespaces, keep chart values and external service endpoints consistent.
