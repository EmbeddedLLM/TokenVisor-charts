# RKE2 Cluster Setup (Alternative to K3D)

This guide provides a production-oriented cluster bootstrap path for TokenVisor using **RKE2 + Cilium + Gateway API**.

Use this as an alternative to `docs/K3D.md`.

## Scope

This guide covers base Kubernetes cluster setup only. After finishing this guide, continue with:

1. Apply node-level prerequisites from `docs/HOST_SETUP.md`
2. `docs/OPERATORS.md`
3. `docs/STORAGE.md`
4. `docs/SECRETS.md`
5. Install the chart from `README.md`

## 1) Install RKE2

On the first server/control-plane node:

```bash
sudo apt update && sudo apt upgrade -y
curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION="v1.32.7+rke2r1" sh -
```

## 2) Configure RKE2 Server

Create `/etc/rancher/rke2/config.yaml`:

```bash
sudo mkdir -p /etc/rancher/rke2
sudo nano /etc/rancher/rke2/config.yaml
```

Example:

```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "<API_IP_OR_DNS>"
cni:
  - multus
  - cilium
disable:
  - rke2-ingress-nginx
disable-kube-proxy: true
embedded-registry: true
supervisor-metrics: true
```

## 3) Enable Cilium Gateway API via RKE2 HelmChartConfig

Create `/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml`:

```bash
sudo mkdir -p /var/lib/rancher/rke2/server/manifests
sudo nano /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml
```

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    kubeProxyReplacement: true
    k8sServiceHost: "localhost"
    k8sServicePort: "6443"
    localRedirectPolicy: true
    gatewayAPI:
      enabled: true
    cni:
      exclusive: false
    hubble:
      enabled: true
      relay:
        enabled: true
      ui:
        enabled: true
```

Optional CoreDNS tuning (only if validated for your RKE2 version):

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-coredns
  namespace: kube-system
spec:
  valuesContent: |-
    nodelocal:
      enabled: true
      use_cilium_lrp: true
```

## 4) Start RKE2

```bash
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
```

Set CLI environment:

```bash
export PATH="$PATH:/var/lib/rancher/rke2/bin"
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
```

## 5) Verify Cluster + Gateway API

```bash
kubectl get nodes
kubectl -n kube-system get pods
```

Install Gateway API CRDs explicitly:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
```

Verify Cilium and GatewayClass:

```bash
kubectl -n kube-system get pods | grep cilium
kubectl get gatewayclass cilium
```

## 6) Optional: GPU Operator Setup For SkyPilot

If SkyPilot will run GPU workloads, install the vendor GPU runtime/operator path before deploying workloads.

### NVIDIA nodes

Create `/var/lib/rancher/rke2/server/manifests/rke2-gpu-operator-config.yaml`:

```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: gpu-operator
  namespace: kube-system
spec:
  chart: gpu-operator
  createNamespace: true
  repo: https://helm.ngc.nvidia.com/nvidia
  set:
    global.clusterCIDR: 10.42.0.0/16
    global.clusterCIDRv4: 10.42.0.0/16
    global.clusterDNS: 10.43.0.10
    global.clusterDomain: cluster.local
    global.rke2DataDir: /var/lib/rancher/rke2
    global.serviceCIDR: 10.43.0.0/16
    global.systemDefaultIngressClass: ingress-nginx
  targetNamespace: gpu-operator
  valuesContent: |-
    toolkit:
      env:
      - name: CONTAINERD_SOCKET
        value: /run/k3s/containerd/containerd.sock
    driver:
      enabled: false
    migManager:
      enabled: false
```

Note: If you disable driver install in GPU Operator, make sure NVIDIA drivers are already installed on nodes.

### AMD nodes

Install AMD GPU Operator for Kubernetes, then verify resources:

```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,AMD_GPU:.status.allocatable.amd\\.com/gpu
```

## 7) Add Additional RKE2 Nodes

On a new server or agent node:

1. Install RKE2 (`curl -sfL https://get.rke2.io | sudo sh -`).
2. Create `/etc/rancher/rke2/config.yaml` with:

```yaml
server: https://<EXISTING_SERVER_OR_LB>:9345
token: <NODE_TOKEN_FROM_EXISTING_SERVER>
```

3. Start node service:

- Server node: `sudo systemctl enable --now rke2-server.service`
- Agent node: `sudo systemctl enable --now rke2-agent.service`

Get token from existing server:

```bash
sudo cat /var/lib/rancher/rke2/server/node-token
```

## 8) Storage Notes (OpenEBS / local-path)

RKE2 still needs a storage provisioner for dynamic PVCs.

### Production path: OpenEBS / Mayastor

If you use replicated OpenEBS storage (`openebs-three-replica`), ensure worker/storage nodes are prepared (HugePages, NVMe-TCP, node labels, DiskPools). Then follow `docs/STORAGE.md` for chart values.

### Dev path: local-path-provisioner

Install local-path-provisioner:

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.34/deploy/local-path-storage.yaml
```

Verify storage classes:

```bash
kubectl get storageclass
```

If `local-path` is not the default class in your cluster, set chart values explicitly.

## 9) Continue TokenVisor Install

After cluster setup is done:

1. Install operators and CRDs from `docs/OPERATORS.md`
2. Prepare storage from `docs/STORAGE.md`
3. Create app secrets from `docs/SECRETS.md`
4. Install chart from `README.md`
5. Configure web access, gateway exposure, TLS from `docs/NETWORK.md`
