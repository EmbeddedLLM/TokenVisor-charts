#!/usr/bin/env bash
set -euo pipefail

umask 077
read_key_file=$(mktemp)
trap 'rm -f "$read_key_file"' EXIT

kubectl -n seaweedfs get configmap seaweedfs-security-config \
  -o 'jsonpath={.data.security\.toml}' | \
  awk '
    /^[[:space:]]*\[jwt\.filer_signing\.read\][[:space:]]*$/ { section = 1; next }
    /^[[:space:]]*\[/ { section = 0 }
    section && /^[[:space:]]*key[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*"/, "")
      sub(/"[[:space:]]*$/, "")
      printf "%s", $0
      exit
    }
  ' >"$read_key_file"

if [ ! -s "$read_key_file" ]; then
  printf '%s\n' 'jwt.filer_signing.read.key is missing from seaweedfs-security-config' >&2
  exit 1
fi

kubectl create namespace oyster --dry-run=client -o yaml | kubectl apply -f -
kubectl -n oyster create secret generic seaweedfs-filer-read \
  --from-file=filer_read_key="$read_key_file" \
  --dry-run=client -o yaml | kubectl apply -f -

printf '%s\n' 'Applied oyster/seaweedfs-filer-read.'
