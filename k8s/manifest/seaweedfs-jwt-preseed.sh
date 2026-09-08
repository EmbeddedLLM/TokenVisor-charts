#!/usr/bin/env bash
set -euo pipefail

umask 077
kubectl create namespace seaweedfs --dry-run=client -o yaml | kubectl apply -f -
if kubectl -n seaweedfs get configmap seaweedfs-security-config >/dev/null 2>&1; then
  printf '%s\n' 'seaweedfs-security-config already exists; refusing to replace its JWT keys' >&2
  exit 1
fi

security_file=$(mktemp)
trap 'rm -f "$security_file"' EXIT
filer_write_key=$(openssl rand -hex 32)
filer_read_key=$(openssl rand -hex 32)
while [ "$filer_read_key" = "$filer_write_key" ]; do
  filer_read_key=$(openssl rand -hex 32)
done
cat >"$security_file" <<EOF
[jwt.filer_signing]
key = "$filer_write_key"
[jwt.filer_signing.read]
key = "$filer_read_key"
EOF

kubectl -n seaweedfs create configmap seaweedfs-security-config \
  --from-file=security.toml="$security_file" \
  --dry-run=client -o yaml | \
  kubectl label --local -f - \
  app.kubernetes.io/managed-by=Helm \
  app.kubernetes.io/name=seaweedfs \
  app.kubernetes.io/instance=seaweedfs \
  -o yaml | \
  kubectl annotate --local -f - \
  meta.helm.sh/release-name=seaweedfs \
  meta.helm.sh/release-namespace=seaweedfs \
  -o yaml | \
  kubectl create -f -

printf '%s\n' 'Pre-seeded seaweedfs/seaweedfs-security-config with Filer JWT keys.'
