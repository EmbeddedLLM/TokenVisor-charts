# Troubleshooting

## Studio login page error (`JSON.parse: unexpected character at line 1 column 1 of the JSON data`)

This is usually caused by a mismatch between Studio public URL settings and the URL/protocol users actually use.

Check:

- `studio.config.HOST` must be host or `host:port` (no scheme)
- `studio.config.ORIGIN` must include scheme (`http://` or `https://`)
- `studio.config.USE_SECURE_COOKIES` must match protocol (`"true"` for HTTPS, `"false"` for HTTP)

Quick inspect current values:

```bash
kubectl -n tokenvisor get configmap studio-config -o yaml | sed -n '/^data:/,$p'
```

Fix the source values for an HTTPS domain:

```yaml
studio:
  config:
    HOST: "studio.example.com"
    ORIGIN: "https://studio.example.com"
    USE_SECURE_COOKIES: "true"
```

Or for direct HTTP NodePort:

```yaml
studio:
  config:
    HOST: "10.42.100.13:38023"
    ORIGIN: "http://10.42.100.13:38023"
    USE_SECURE_COOKIES: "false"
```

Apply the appropriate values to `.local/studio-values.yaml`, repeat the `values build` command for the deployment mode, and run the normal Helm upgrade command from the [recommended install flow](../README.md#8-install-tokenvisor).

## Pods stuck in Pending

- Ensure the RWX model PVC exists (`nfs-model-storage-pvc` by default).
- Ensure referenced storage classes exist. Defaults use `openebs-three-replica` for stateful components.
- If you want to disable the fail-fast check, set `validation.failOnMissingModelPVC: false`.
- For client-side `helm template` renders, set `validation.lookupExistingResources: false`; plain `helm template` cannot see existing cluster PVCs or Secrets.

## ImagePullBackOff

- Create a GHCR image pull secret in the **tokenvisor** namespace.
- Confirm `global.imagePullSecrets` names.

## CRDs missing

- If you see errors about missing kinds, install the operators/CRDs.
- Confirm with `kubectl api-resources` for each CRD group.

## Mode mismatch / topology issues

- Use `values.single-node.yaml` only for fresh single-node installs.
- Mode switching after install is not supported; reinstall for topology changes.

## Gateway not routing

- Check Gateway and HTTPRoute status: `kubectl get gateway,httproute -n tokenvisor`.
- Ensure Cilium is installed and Gateway API CRDs are present.
- Check `GatewayClass` exists: `kubectl get gatewayclass`.
- If `cilium-gateway` shows `PROGRAMMED=Unknown` and `Waiting for controller`, `GatewayClass/cilium` is likely missing.
- Fix by either:
  - setting `network.gateway.createGatewayClass: true` and re-running Helm, or
  - creating `GatewayClass/cilium` manually.

## Gateway not routing with NetBird (`src_valid_mark=1`)

- In some environments, NetBird sets `net.ipv4.conf.all.src_valid_mark=1` on nodes.
- This can break Cilium Gateway routing for L2-announced service IPs.
- Upstream references:
  - Cilium: `https://github.com/cilium/cilium/issues/41991`
  - NetBird: `https://github.com/netbirdio/netbird/issues/4575`

Check current state:

```bash
sysctl net.ipv4.conf.all.src_valid_mark
kubectl -n tokenvisor get gateway cilium-gateway
kubectl -n tokenvisor describe gateway cilium-gateway
```

If `src_valid_mark=1` and gateway traffic fails while pods are otherwise healthy, test on the affected node:

```bash
sudo sysctl -w net.ipv4.conf.all.src_valid_mark=0
```

If traffic recovers, treat this as a host-networking conflict (NetBird/Cilium interaction), not a TokenVisor chart issue.

## EMU cannot connect to DB/ClickHouse

- Verify `emu-secret` contains `EMU_DB_PATH` and `EMU_SERVICE_KEY`.
- Verify `clickhouse-secret` and `pg-emu-user-secret` are correct.
