# TokenVisor Helm Chart

This chart deploys TokenVisor and the default data/observability stack.

The chart does **not** install Kubernetes distro components, CNI, or storage providers. Use the prerequisite helper for the standard install path, and use the referenced docs when your cluster needs customization.

```bash
cd charts/tokenvisor
./bin/tokenvisor-prereqs --help
```

## What Gets Installed

Enabled by default:

- EMU API, Starling worker + beat, Studio UI
- ClickHouse (CRs), CNPG/Postgres (CRs), Dragonfly (CR)
- VictoriaMetrics (CRs), VictoriaLogs (subchart)

Optional:

- Grafana (CRs + datasources)
- VMAlert (alerts/rules)
- Fluent Bit (log shipping)

## Recommended Install Flow

Run from the chart root:

```bash
cd charts/tokenvisor
ls README.md Chart.yaml values.yaml
```

### 1. Bootstrap Kubernetes/CNI

Use one cluster guide:

- `docs/RKE2.md`
- `docs/K3D.md`

For production/RKE2 nodes, also review `docs/HOST_SETUP.md`, especially when using OpenEBS or enabling `fluentbit.enabled=true`.

#### Node labels (control-plane nodes)

In `deployment.mode=ha` the platform components (emu, studio, starling, ClickHouse, VictoriaMetrics, etc.) are pinned one-per-node via a `node-role.kubernetes.io/control-plane: "true"` nodeSelector and tolerate the matching `NoSchedule` taint. `deployment.mode=ha` requires at least `global.minNodesRequired` (default 3) such nodes.

RKE2 server nodes already carry this label with value `"true"`, so no action is needed there. On distributions that don't set it (for example kubeadm sets the label with an empty value), add the explicit `"true"` value the chart matches on:

```bash
kubectl label node <CONTROL_PLANE_NODE> node-role.kubernetes.io/control-plane=true --overwrite
```

Per-service overrides (`<svc>.nodeSelector` / `.tolerations` / `.affinity`) are available if you want a different placement.

### 2. Check Cilium

After cluster bootstrap, verify Cilium:

```bash
kubectl -n kube-system get pods | grep cilium
kubectl get gatewayclass cilium
```

If `GatewayClass/cilium` is missing, continue with the helper in step 3. The platform phase applies the Gateway API CRDs and creates the Cilium `GatewayClass` when Cilium pods are present.

### 3. Run Platform Prerequisites

This is the recommended standard bootstrap path. Use `docs/PREREQS_HELPER.md` for all helper options.

```bash
# Required platform CRDs/operators.
./bin/tokenvisor-prereqs platform --apply

# If enabling grafana.enabled or fluentbit.enabled, use this instead.
# Apply docs/HOST_SETUP.md first when enabling fluentbit.enabled on production/RKE2 nodes.
./bin/tokenvisor-prereqs platform --include-grafana --include-fluent --apply

# Optional GPU operator path, only if SkyPilot will run GPU workloads.
./bin/tokenvisor-prereqs gpu nvidia --apply
# and/or:
./bin/tokenvisor-prereqs gpu amd --apply
```

### 4. Create Application Secrets

```bash
./bin/tokenvisor-prereqs secrets init --interactive
# Review .local/tokenvisor-secrets.yaml if needed.
./bin/tokenvisor-prereqs secrets apply
```

### 5. Configure Storage

Use Kubernetes quantities with an explicit unit for every storage size, such as `5Gi`, `100Gi`, or `1Ti`. A bare value such as `30` means 30 bytes, not 30 GiB.

```bash
# Only when audit media storage is wanted: choose external S3 or bundled SeaweedFS.
./bin/tokenvisor-prereqs storage audit-s3 --apply

# If audit S3 is external but SeaweedFS should provide RWX model storage.
# No need to rerun this if bundled SeaweedFS is selected in `audit-s3`
./bin/tokenvisor-prereqs storage seaweedfs --apply

# Optional after SeaweedFS installation path: create RWX model claims.
./bin/tokenvisor-prereqs storage model-pvcs --apply
```

Skip `storage audit-s3` and keep audit mode `off` when audit media storage is not wanted. See [External S3](docs/SEAWEEDFS.md#external-s3) for a bucket creation example and required permissions. See [Bundled SeaweedFS](docs/SEAWEEDFS.md#bundled-seaweedfs) for topology, durability, existing deployments, and hostPath/PVC choices. For other model-storage backends, see `docs/STORAGE.md`.

### 6. Finish Prerequisites

```bash
# Private GHCR pull secrets.
export GHCR_USERNAME='<github-username>'
export GHCR_TOKEN='<github-pat-with-read-packages>'
./bin/tokenvisor-prereqs secrets ghcr --apply

# SkyPilot API server.
# Default storage class is openebs-three-replica.
./bin/tokenvisor-prereqs skypilot --sc '<your-storage-class>' --apply
# If the default storage class is correct:
# ./bin/tokenvisor-prereqs skypilot --apply
```

### 7. Customize TokenVisor Values

At minimum, set Studio public URL values. `HOST` is host or `host:port` with no scheme. `ORIGIN` includes scheme.

Create the Studio values file:

```bash
cat > .local/studio-values.yaml <<'YAML'
studio:
  config:
    HOST: "studio.example.com"
    ORIGIN: "https://studio.example.com"
    USE_SECURE_COOKIES: "true"
YAML
```

After all source values files are ready, build `.local/deployed-values.yaml` once. The command requires [Mike Farah `yq` v4](https://github.com/mikefarah/yq#install) and merges the files in argument order, with later values taking precedence.

HA/default:

```bash
# Include .local/audit-s3-values.yaml only when storage audit-s3 was configured.
./bin/tokenvisor-prereqs values build \
  .local/audit-s3-values.yaml \
  .local/studio-values.yaml
```

Single-node:

```bash
# Include .local/audit-s3-values.yaml only when storage audit-s3 was configured.
./bin/tokenvisor-prereqs values build --mode single-node \
  .local/audit-s3-values.yaml \
  .local/studio-values.yaml
```

`.local/deployed-values.yaml` is the final output values for actual install/upgrade. To change the deployment, edit or regenerate the relevant source values file and repeat this merge.

See [Build TokenVisor Values](docs/PREREQS_HELPER.md#build-tokenvisor-values) for the equivalent manual merge.

### 8. Install TokenVisor

Download the chart dependency and run the final readiness check:

```bash
helm dependency update .

# HA/default:
./bin/tokenvisor-prereqs check

# Single-node, instead of the preceding check command:
# TOKENVISOR_MODE=single-node ./bin/tokenvisor-prereqs check
```

`helm dependency update .` downloads chart dependencies into the local ignored `charts/` directory. This repo does not commit generated dependency archives or `Chart.lock`.

The check requires the final values file to exist. When it succeeds, it prints this install/upgrade command:

```bash
helm upgrade --install tokenvisor . \
  --namespace tokenvisor \
  --create-namespace \
  -f .local/deployed-values.yaml
```

For direct HTTP NodePort access, set the reachable address and disable secure cookies in `.local/studio-values.yaml` before building the final values. If the address is known only after the first install, update that source file, repeat `values build`, and run the same Helm upgrade command. See [Studio Public URL](docs/CUSTOMIZATION.md#studio-public-url-required).

## Post-Install Checks

Initial startup of ClickHouse, CNPG, VictoriaMetrics, EMU, Starling, and Studio can take time.

```bash
kubectl -n tokenvisor get pods
kubectl -n tokenvisor get gateway cilium-gateway
kubectl -n tokenvisor describe gateway cilium-gateway
kubectl -n tokenvisor get httproute
```

For debugging, see `docs/TROUBLESHOOTING.md`.

For broader customization, see:

- `docs/CUSTOMIZATION.md`
- `docs/SINGLE_NODE.md`
- `docs/STORAGE.md`
- `docs/GPU.md`
- `docs/SKYPILOT.md`
- `docs/NETWORK.md`

## Reference Docs

- `docs/PREREQS_HELPER.md`
- `docs/RKE2.md`
- `docs/K3D.md`
- `docs/HOST_SETUP.md`
- `docs/STORAGE.md`
- `docs/SEAWEEDFS.md`
- `docs/SECRETS.md`
- `docs/OPERATORS.md`
- `docs/GPU.md`
- `docs/SKYPILOT.md`
- `docs/CUSTOMIZATION.md`
- `docs/SINGLE_NODE.md`
- `docs/NETWORK.md`
- `docs/TROUBLESHOOTING.md`
