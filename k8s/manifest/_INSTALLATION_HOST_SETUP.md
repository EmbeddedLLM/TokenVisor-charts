# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Kubernetes Node Environment

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

## OS Environment

- Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-90-generic x86_64)
- AMD ROCm 7.1.1
- AMDGPU 30.20.1
- Nvidia driver 580 server open
- Nvidia CUDA Toolkit 13.1
- NVMe-TCP kernel module

## Kubernetes Distro

- RKE2 v1.32.7+rke2r1

## Sysctl Config

- fs.inotify.max_user_watches = 2097152
- fs.inotify.max_user_instances = 8192
- fs.inotify.max_queued_events = 65536
- fs.file-max = 10000000
- fs.nr_open = 2097152
- vm.swappiness = 0
- vm.overcommit_memory = 1

# ~~~~~~~~~~~~~~~~~~~~~~~

# Configuration Guide

# ~~~~~~~~~~~~~~~~~~~~~~~

## Install NVMe-TCP Module

```bash
sudo apt install -y linux-modules-extra-$(uname -r)
sudo modprobe nvme-tcp
echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
```

## Create Sysctl Config

```bash
sudo tee /etc/sysctl.d/99-sysctl.conf > /dev/null <<EOF
# Max inotify / FD
fs.inotify.max_user_watches = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_queued_events = 65536
fs.file-max = 10000000
fs.nr_open = 2097152
# Memory policy
vm.swappiness = 0
vm.overcommit_memory = 1
EOF

sudo sysctl --system
```
