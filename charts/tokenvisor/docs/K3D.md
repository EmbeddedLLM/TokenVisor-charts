# k3d Quick Start

This guide creates a k3d cluster with Cilium + Gateway API.

## Create cluster

HA/default topology (3 nodes):

```bash
k3d cluster create tokenvisor \
  --servers 1 --agents 2 \
  --k3s-arg "--flannel-backend=none@server:*" \
  --k3s-arg "--disable-network-policy@server:*" \
  --k3s-arg "--disable=traefik@server:*"
```

Single-node topology (for `values.single-node.yaml` installs):

```bash
k3d cluster create tokenvisor \
  --servers 1 --agents 0 \
  --k3s-arg "--flannel-backend=none@server:*" \
  --k3s-arg "--disable-network-policy@server:*" \
  --k3s-arg "--disable=traefik@server:*"
```

## Install Gateway API CRDs

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.0/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
```

## Install Cilium

```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm upgrade --install cilium cilium/cilium -n kube-system \
  --set kubeProxyReplacement=true \
  --set gatewayAPI.enabled=true \
  --set gatewayAPI.hostNetwork.enabled=true
```

## Verify Cilium

```bash
kubectl -n kube-system get pods | grep cilium
kubectl get gatewayclass cilium
```

## Next

Continue with operator install + secrets, then Helm install the chart.
