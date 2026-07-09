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

### 4. Prepare Storage

Install or verify your storage backend:

- For OpenEBS/custom storage decisions, see `docs/STORAGE.md`.
- For SeaweedFS RWX model storage, install SeaweedFS first with `docs/SEAWEEDFS.md`, then create model PV/PVCs with the helper.
- For RKE2 clusters that need `local-path`, install it before installing any chart that uses `storageClass: local-path`:

```bash
./bin/tokenvisor-prereqs storage local-path --apply
```

If using SeaweedFS, follow `docs/SEAWEEDFS.md` after the backing StorageClass exists. Then create the model PV/PVCs:

```bash
# If using SeaweedFS CSI for model storage.
./bin/tokenvisor-prereqs storage model-pvcs --apply
```

### 5. Finish Prerequisites

```bash
# App secrets and private GHCR pull secrets.
./bin/tokenvisor-prereqs secrets init --interactive
# Review .local/tokenvisor-secrets.yaml if needed.
./bin/tokenvisor-prereqs secrets apply

export GHCR_USERNAME='<github-username>'
export GHCR_TOKEN='<github-pat-with-read-packages>'
./bin/tokenvisor-prereqs secrets ghcr --apply

# SkyPilot API server.
# Default storage class is openebs-three-replica.
./bin/tokenvisor-prereqs skypilot --sc '<your-storage-class>' --apply
# If the default storage class is correct:
# ./bin/tokenvisor-prereqs skypilot --apply

# Chart dependency and final readiness check.
helm dependency update .
./bin/tokenvisor-prereqs check
# if you intend to install single-node version, use this readiness check
TOKENVISOR_MODE=single-node ./bin/tokenvisor-prereqs check
```

`helm dependency update .` downloads chart dependencies into the local ignored `charts/` directory. This repo does not commit generated dependency archives or `Chart.lock`.

### 6. Customize TokenVisor Values

At minimum, set Studio public URL values. `HOST` is host or `host:port` with no scheme. `ORIGIN` includes scheme.

```bash
cat > values.studio-access.yaml <<'YAML'
studio:
  config:
    HOST: "studio.example.com"
    ORIGIN: "https://studio.example.com"
    USE_SECURE_COOKIES: "true"
YAML
```

For single-node installs, also use `values.single-node.yaml`.

For broader customization, see:

- `docs/CUSTOMIZATION.md`
- `docs/SINGLE_NODE.md`
- `docs/STORAGE.md`
- `docs/GPU.md`
- `docs/SKYPILOT.md`
- `docs/NETWORK.md`

### 7. Install TokenVisor

HA/default:

```bash
helm upgrade --install tokenvisor . \
  --namespace tokenvisor \
  --create-namespace \
  -f values.yaml \
  -f values.studio-access.yaml
```

Single-node:

```bash
helm upgrade --install tokenvisor . \
  --namespace tokenvisor \
  --create-namespace \
  -f values.yaml \
  -f values.single-node.yaml \
  -f values.studio-access.yaml
```

If you access Studio by direct HTTP NodePort, finalize values after install:

```bash
STUDIO_ADDR="10.42.100.13:38023" # replace with your reachable ip:port
helm upgrade --install tokenvisor . \
  --namespace tokenvisor \
  --reuse-values \
  --set-string studio.config.HOST="${STUDIO_ADDR}" \
  --set-string studio.config.ORIGIN="http://${STUDIO_ADDR}" \
  --set-string studio.config.USE_SECURE_COOKIES="false"
```

## Post-Install Checks

Initial startup of ClickHouse, CNPG, VictoriaMetrics, EMU, Starling, and Studio can take time.

```bash
kubectl -n tokenvisor get pods
kubectl -n tokenvisor get gateway cilium-gateway
kubectl -n tokenvisor describe gateway cilium-gateway
kubectl -n tokenvisor get httproute
```

For debugging, see `docs/TROUBLESHOOTING.md`.

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
