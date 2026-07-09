# GPU Setup (NVIDIA and AMD)

> **Recommended path:** `./bin/tokenvisor-prereqs gpu nvidia --apply` or `./bin/tokenvisor-prereqs gpu amd --apply`
>
> See [PREREQS_HELPER.md](PREREQS_HELPER.md) for all helper options. The manual steps below are for customization beyond the helper defaults.

Use this guide only if SkyPilot will run GPU workloads.

## Scope

This guide covers:

1. NVIDIA GPU Operator path
2. AMD GPU Operator path
3. Post-install verification

## NVIDIA Path (GPU Operator)

Install NVIDIA GPU Operator:

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

Notes:

1. If `driver.enabled=false`, NVIDIA drivers must already be installed on nodes.
2. Some environments also require `nvidia-fabric-manager`.

## AMD Path (GPU Operator)

AMD operator requires cert-manager first.

Install cert-manager:

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.2 \
  --set crds.enabled=true
```

Create metrics exporter config (equivalent to `k8s/manifest/amd-metrics-exporter-config.yaml`) and apply:

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

Optional for AMD vGPU environments:

```bash
helm upgrade --install amd-gpu-operator \
  --namespace amd-gpu-operator rocm/gpu-operator-charts \
  --set deviceConfig.spec.testRunner.enable=true \
  --set deviceConfig.spec.metricsExporter.config.name=amd-metrics-exporter-config \
  --set-json 'deviceConfig.spec.selector={"feature.node.kubernetes.io/amd-gpu":null,"feature.node.kubernetes.io/amd-vgpu":"true"}'
```

## Verify GPU Setup

NVIDIA resource check:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,NVIDIA_GPU:.status.allocatable.nvidia\\.com/gpu
```

AMD resource check:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,AMD_GPU:.status.allocatable.amd\\.com/gpu
```

Operator pod health:

```bash
kubectl get pods -n nvidia-gpu-operator
kubectl get pods -n amd-gpu-operator
```
