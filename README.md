<div style="text-align: center;">
  <img src="./charts/tokenvisor/files/logos/icon-landscape.svg" alt="TokenVisor Logo" style="width: 60%; max-width: 500px; height: auto;">
</div>

# TokenVisor Charts

Kubernetes install artifacts for [TokenVisor](https://github.com/EmbeddedLLM/TokenVisor), the token/usage management platform by [Embedded LLM](https://embeddedllm.com). Synced from the main TokenVisor repo so they can be downloaded and installed independently.

This repo has two ways to install TokenVisor — pick one:

## `charts/tokenvisor/` — Helm chart (recommended)

The Helm chart deploys TokenVisor and its default data/observability stack (EMU API, Studio UI, Starling worker, ClickHouse, Postgres, Dragonfly, VictoriaMetrics, and optional Grafana/VMAlert/Fluent Bit).

```bash
cd charts/tokenvisor
./bin/tokenvisor-prereqs --help
```

See `charts/tokenvisor/README.md` for the full install flow, and `charts/tokenvisor/docs/` for cluster bootstrap guides (RKE2, K3D), GPU setup, networking, storage, and customization.

## `k8s/manifest/` — raw manifests

Plain Kubernetes manifests for the same stack, for environments that don't use Helm or need to apply/customize resources individually.

See the `_INSTALLATION_*` guides in that directory for setup steps per distro (RKE2, K3s).

## Notes

- Neither install path provisions the underlying Kubernetes distro, CNI, or storage provider — bring your own cluster and follow the linked bootstrap docs first.
- Secrets in both `charts/tokenvisor` and `k8s/manifest` are placeholders (`CHANGE_ME_*` / empty) — replace them with real values before deploying.
