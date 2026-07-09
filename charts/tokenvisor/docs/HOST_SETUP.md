# Host Setup

Use this checklist for production/RKE2 nodes before installing storage-heavy or log-collector features.

These settings are node-level prerequisites, not Helm chart settings. Apply them on every Kubernetes node that may run TokenVisor storage, database, or Fluent Bit workloads.

## Sysctl

Fluent Bit tails container logs and can need a large number of inotify watches on busy clusters. The same host profile also keeps file descriptor and memory behavior explicit.

```bash
sudo tee /etc/sysctl.d/99-tokenvisor.conf >/dev/null <<'EOF'
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

Verify:

```bash
sysctl fs.inotify.max_user_watches
sysctl fs.inotify.max_user_instances
sysctl fs.inotify.max_queued_events
sysctl fs.file-max
sysctl fs.nr_open
sysctl vm.swappiness
sysctl vm.overcommit_memory
```

## NVMe-TCP

OpenEBS/Mayastor replicated storage requires NVMe-TCP support on data nodes.

```bash
sudo apt install -y linux-modules-extra-$(uname -r)
sudo modprobe nvme-tcp
echo 'nvme-tcp' | sudo tee /etc/modules-load.d/nvme-tcp.conf
```

Verify:

```bash
lsmod | grep nvme_tcp
cat /sys/module/nvme_core/parameters/multipath
```

For OpenEBS HA, also ensure `nvme_core.multipath=Y` according to your node OS and bootloader configuration.
