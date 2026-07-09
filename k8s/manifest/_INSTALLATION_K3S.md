# INSTALL K3S

## System Preparation

```bash
sudo apt update && sudo apt upgrade -y
```

## Install K3S

### Setup K3S Master nodes

```bash
# First Master Node
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='--flannel-backend=none --egress-selector-mode=disabled --disable=traefik --disable-network-policy --disable-kube-proxy' sh -s - --cluster-init --tls-san 172.16.30.221

# Retrieve NODE TOKEN
sudo cat /var/lib/rancher/k3s/server/node-token

# Second & Third Master Node

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --flannel-backend=none --disable=traefik --egress-selector-mode=disabled  --disable-network-policy --disable-kube-proxy --server https://172.16.30.221:6443 --token K10fb9788efb63f75e21c162ed65d114b551de0738d147afcf3a5e7a5fe32deb4d4::server:a9e43321243cee9f92d25702566a7fca --tls-san 172.16.30.21' sh -s -
```
