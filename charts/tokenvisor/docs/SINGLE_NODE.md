# Single-Node Mode

This chart supports a non-HA single-node deployment mode for fresh installs.

## Important Limits

- Single-node mode is install-time only.
- HA -> single-node and single-node -> HA conversion is not supported.
- `clickhouse.shardsCount > 1` is not validated/tested in this mode.

## Preflight

Before running the install command below:

1. Cluster and Cilium/Gateway API are ready (`docs/K3D.md` or `docs/RKE2.md`).
2. Namespaces are created (`tokenvisor`, `skypilot`).
3. Operators, storage, and required secrets are already prepared (`README.md`, `docs/OPERATORS.md`, `docs/STORAGE.md`, `docs/SECRETS.md`).

## Install

```bash
helm upgrade --install tokenvisor . \
  -n tokenvisor \
  -f values.yaml \
  -f values.single-node.yaml
```

## What Changes In Single-Node Mode

- `deployment.mode=single-node`
- `global.minNodesRequired=1`
- ClickHouse runs standalone (`clickhouse.standalone=true`)
- ClickHouse keeper replicas are disabled (`clickhouse.keeperReplicas=0`)
- ClickHouse cluster replica count is `1`
- ClickHouse init job and EMU/Starling waiters disable cluster-count checks
- VictoriaMetrics/VictoriaLogs topology is reduced to single target replicas
- Dragonfly replica count is reduced to `1`

## Verify After Install

```bash
kubectl -n tokenvisor get pods
kubectl -n tokenvisor get job clickhouse-init-db
kubectl -n tokenvisor get clickhouseinstallation
```

Expected:

- No keeper pods/resources
- ClickHouse init job completes
- EMU/Starling/Studio pods become Ready
