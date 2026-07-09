# RKE2 Installation Guide

## System Preparation

```bash
sudo apt update && sudo apt upgrade -y
```

## Install RKE2

```bash
sudo curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION="v1.32.7+rke2r1" sh -
```

## Configure RKE2

Create configuration directory:

```bash
sudo mkdir -p /etc/rancher/rke2
```

Edit the main configuration file:

```bash
sudo nano /etc/rancher/rke2/config.yaml
```

Add the following configuration:

```yaml
write-kubeconfig-mode: "0644"
tls-san:
  - "192.168.80.54" # HTTPS Endpoint for external k8s API
cni:
  - multus
  - cilium
disable:
  - rke2-ingress-nginx
disable-kube-proxy: true
embedded-registry: true
supervisor-metrics: true
```

## Configure Cilium

Create manifests directory:

```bash
sudo mkdir -p /var/lib/rancher/rke2/server/manifests
```

Create Cilium configuration:

```bash
sudo nano /var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml
```

Add the following Cilium configuration:

```yaml
---
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    # Enable L2 Announcement if required.
    # l2announcements:
    #   enabled: true
    # k8sClientRateLimit:
    #   qps: 50
    #   burst: 100
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

<!-- CoreDNS helm chart currently has problem installing -->

## Configure CoreDNS

Create CoreDNS configuration:

```bash
sudo nano /var/lib/rancher/rke2/server/manifests/rke2-coredns-config.yaml
```

Add the following CoreDNS configuration:

```yaml
---
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

## Configure NVIDIA GPU Operator

Create NVIDIA GPU Operator configuration:

```bash
sudo nano /var/lib/rancher/rke2/server/manifests/rke2-gpu-operator-config.yaml
```

Install nvidia drivers via APT and freeze hold the packages Sometimes it is neccessary to install nvidia-fabric-manager packages, or else GPU Operator will fail

Add the following NVIDIA GPU Operator configuration:

```yaml
---
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

## Start RKE2

```bash
sudo systemctl enable rke2-server.service
sudo systemctl start rke2-server.service
```
