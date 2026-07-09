# SkyPilot API Server Setup

> **Recommended path:** `./bin/tokenvisor-prereqs skypilot --sc '<your-storage-class>' --apply`
>
> See [PREREQS_HELPER.md](PREREQS_HELPER.md) for all helper options. The manual steps below are for customization beyond the helper defaults.

SkyPilot runs the model provisioner used by TokenVisor.

The helper default storage class is `openebs-three-replica`. Use `--sc` when your cluster uses `local-path`, another OpenEBS class, or any other available storage class.

Use the manual upstream chart flow below when you need to customize values beyond the helper flags.

EMU connects via `SKYPILOT_API_SERVER_ENDPOINT` (defaults to `http://skypilot-api-service.skypilot.svc.cluster.local`), so the install below must use release name `skypilot` and namespace `skypilot` to keep the default wiring.

## Prerequisites

- Namespace `skypilot` created (see `README.md` step 4).

If using the prerequisite helper, these are covered by the recommended flow in `README.md`.

## 1) Prepare values

```bash
cat > skypilot-values.yaml <<'YAML'
apiService:
  image: ghcr.io/embeddedllm/skypilot:v0.12.0
  config: |
    serve:
      controller:
        resources:
          cloud: kubernetes
          cpus: 4+
          disk_size: 50
        high_availability: true
    kubernetes:
      ports: podip
      high_availability:
        storage_class_name: openebs-three-replica
  resources:
    requests:
      cpu: "4"
      memory: "8Gi"
  serveServerLog: false

storage:
  storageClassName: openebs-three-replica

ingress:
  enabled: false

ingress-nginx:
  enabled: false
YAML
```

Adjust `storage.storageClassName` and `apiService.config.kubernetes.high_availability.storage_class_name` to match a storage class available in your cluster.

## 2) Install

```bash
helm repo add skypilot https://helm.skypilot.co
helm repo update
helm upgrade --install skypilot skypilot/skypilot \
  --namespace skypilot \
  -f skypilot-values.yaml \
  --version 0.12.0
```

## 3) Verify

```bash
kubectl -n skypilot get pods
kubectl -n skypilot get svc skypilot-api-service
```

The service must be reachable from the `tokenvisor` namespace at `skypilot-api-service.skypilot.svc.cluster.local` (port 80). EMU's healthcheck (`/v1/meters/.../healthcheck`) reports the API server status under "Model Provisioner Service".
