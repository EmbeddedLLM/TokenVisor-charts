# Operator Installation

> **Recommended path:** `./bin/tokenvisor-prereqs platform --apply`
>
> See [PREREQS_HELPER.md](PREREQS_HELPER.md) for all helper options. The manual steps below are for customization beyond the helper defaults.

This chart requires operators to be installed **before** Helm install. The commands below are self-contained and do not rely on repo files.

## ServiceMonitor/PodMonitor CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.87.1/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.87.1/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml
# https://github.com/VictoriaMetrics/helm-charts/issues/2838
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.87.1/example/prometheus-operator-crd/monitoring.coreos.com_scrapeconfigs.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.87.1/example/prometheus-operator-crd/monitoring.coreos.com_alertmanagerconfigs.yaml

```

## Victoria Metrics Operator

```bash
cat <<'YAML' > vm-operator-values.yaml
replicaCount: 1
crds:
  cleanup:
    enabled: true
serviceMonitor:
  enabled: true
  extraLabels:
    scrape-by: vmagent
resources:
  limits:
    cpu: 500m
    memory: 500Mi
  requests:
    cpu: 100m
    memory: 150Mi
YAML

helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update
kubectl create ns vm-operator-system
# this first cmd is needed
helm install vmoperator vm/victoria-metrics-operator -f vm-operator-values.yaml -n vm-operator-system --set serviceMonitor.enabled=false --version 0.62.1
helm upgrade vmoperator vm/victoria-metrics-operator -f vm-operator-values.yaml -n vm-operator-system --version 0.62.1
```

## Dragonfly Operator

```bash
cat <<'YAML' > dragonfly-operator-values.yaml
replicaCount: 1
manager:
  resources:
    requests:
      cpu: 100m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 2000Mi
serviceMonitor:
  enabled: true
  labels:
    scrape-by: vmagent
grafanaDashboard:
  enabled: true
  folder: dragonfly
  annotations:
    name: dragonfly_folder
  labels:
    name: dragonfly_dashboard
YAML

kubectl create ns dragonfly-operator-system
helm upgrade -f dragonfly-operator-values.yaml -n dragonfly-operator-system --install dragonfly-operator \
  oci://ghcr.io/dragonflydb/dragonfly-operator/helm/dragonfly-operator --version v1.1.10

kubectl patch deployment dragonfly-operator -n dragonfly-operator-system --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/1/args/1",
    "value": "--metrics-bind-address=0.0.0.0:8080"
  }
]'
```

## ClickHouse Operator (Altinity)

```bash
cat <<'YAML' > clickhouse-operator-values.yaml
configs:
  files:
    config.yaml:
      watch:
        namespaces:
          - tokenvisor
serviceMonitor:
  enabled: true
  additionalLabels:
    scrape-by: vmagent
dashboards:
  enabled: true
  additionalLabels:
    grafana_dashboard: "clickhouse"
  annotations: {}
  grafana_folder: clickhouse
YAML

kubectl create ns clickhouse-operator-system
helm repo add clickhouse-operator https://docs.altinity.com/clickhouse-operator/
helm install clickhouse-operator clickhouse-operator/altinity-clickhouse-operator \
  -n clickhouse-operator-system -f clickhouse-operator-values.yaml --version 0.27.0
```

## CloudNativePG (CNPG)

```bash
cat <<'YAML' > cnpg-operator-values.yaml
replicaCount: 1
config:
  data:
    INHERITED_LABELS: app.kubernetes.io/*
monitoring:
  podMonitorEnabled: true
  podMonitorAdditionalLabels:
    scrape-by: vmagent
  grafanaDashboard:
    create: true
YAML

helm repo add cnpg https://cloudnative-pg.github.io/charts
kubectl create ns cnpg-operator-system
helm upgrade --install cnpg -n cnpg-operator-system cnpg/cloudnative-pg -f cnpg-operator-values.yaml --version 0.27.1
```

## Grafana Operator (optional)

```bash
cat <<'YAML' > grafana-operator-values.yaml
serviceMonitor:
  enabled: true
  additionalLabels:
    scrape-by: vmagent
dashboard:
  enabled: true
YAML

kubectl create ns grafana-operator-system
helm upgrade -i grafana-operator oci://ghcr.io/grafana/helm-charts/grafana-operator \
  --version v5.17.0 -f grafana-operator-values.yaml -n grafana-operator-system
```

## Fluent Operator (optional)

Install this only if `fluentbit.enabled=true`.

Before enabling Fluent Bit on production/RKE2 nodes, raise inotify limits on every node:

```bash
sudo tee /etc/sysctl.d/99-tokenvisor-inotify.conf >/dev/null <<'EOF'
fs.inotify.max_user_watches = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_queued_events = 65536
EOF
sudo sysctl --system
```

```bash
cat <<'YAML' > fluent-operator-values.yaml
containerRuntime: containerd
Kubernetes: false
YAML

helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-operator fluent/fluent-operator \
  -f fluent-operator-values.yaml -n fluent-operator-system --create-namespace
```

## GPU Operators For SkyPilot (conditional)

Install this only if SkyPilot will launch GPU workloads. For the full GPU setup flow, see `docs/GPU.md`.

### NVIDIA path (GPU Operator)

Install via Helm:

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
helm install nvidia-gpu-operator \
  --namespace nvidia-gpu-operator nvidia/gpu-operator \
  --set driver.enabled=false \
  --set toolkit.enabled=false \
  --set migManager.enabled=false \
  --create-namespace
```

### AMD path

Install cert-manager first:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.2 \
  --set crds.enabled=true
```

Create and apply AMD metrics exporter config:

```bash
cat <<'YAML' > amd-metrics-exporter-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: amd-metrics-exporter-config
  namespace: amd-gpu-operator
data:
  config.json: |
    {
      "GPUConfig": {
        "Fields": [
          "GPU_PACKAGE_POWER",
          "GPU_JUNCTION_TEMPERATURE",
          "GPU_MEMORY_TEMPERATURE",
          "GPU_GFX_ACTIVITY",
          "GPU_UMC_ACTIVITY",
          "PCIE_SPEED",
          "PCIE_MAX_SPEED",
          "PCIE_BANDWIDTH",
          "GPU_ENERGY_CONSUMED",
          "GPU_CLOCK",
          "GPU_TOTAL_VRAM",
          "GPU_FREE_VRAM",
          "GPU_USED_VRAM"
        ],
        "Labels": [
          "GPU_UUID",
          "SERIAL_NUMBER",
          "GPU_ID",
          "POD",
          "CARD_SERIES",
          "CARD_MODEL",
          "CARD_VENDOR",
          "DRIVER_VERSION",
          "VBIOS_VERSION",
          "HOSTNAME"
        ]
      }
    }
YAML

kubectl create ns amd-gpu-operator
kubectl apply -f amd-metrics-exporter-config.yaml -n amd-gpu-operator
```

Install AMD GPU Operator:

```bash
helm repo add rocm https://rocm.github.io/gpu-operator
helm repo update
helm install amd-gpu-operator \
  --namespace amd-gpu-operator rocm/gpu-operator-charts \
  --set deviceConfig.spec.testRunner.enable=true \
  --set deviceConfig.spec.metricsExporter.config.name=amd-metrics-exporter-config
```
