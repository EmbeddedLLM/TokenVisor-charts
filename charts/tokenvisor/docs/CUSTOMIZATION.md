# Customization

Below are the most common values you may want to change.

## Deployment mode

HA is default. For single-node mode, use the provided override file:

```bash
helm upgrade --install tokenvisor . \
  -n tokenvisor \
  -f values.yaml \
  -f values.single-node.yaml
```

Mode conversion after install is not supported (no HA->single or single->HA in place).

## Images / tags

```yaml
emu:
  image: ghcr.io/embeddedllm/tokenvisor-emu:<tag>
starling:
  image: ghcr.io/embeddedllm/tokenvisor-emu:<tag>
  worker:
    replicas: 1
  beat:
    replicas: 1
studio:
  image: ghcr.io/embeddedllm/tokenvisor-studio:<tag>
clickhouse:
  images:
    keeper: clickhouse/clickhouse-keeper:<tag>
    server: clickhouse/clickhouse-server:<tag>
cnpg:
  image: ghcr.io/cloudnative-pg/postgresql:<tag>
victoriametrics:
  images:
    vmagent:
      repository: victoriametrics/vmagent
      tag: <tag>
    vmauth:
      repository: victoriametrics/vmauth
      tag: <tag>
    clusterVersion: <cluster-version>
fluentbit:
  image: ghcr.io/fluent/fluent-operator/fluent-bit:<tag>
```

## Resource tuning

```yaml
studio:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

dragonfly:
  resources:
    requests:
      cpu: 500m
      memory: 500Mi
    limits:
      cpu: 2000m
      memory: 4Gi

clickhouse:
  keeper:
    resources:
      requests:
        cpu: 350m
        memory: 256Mi
      limits:
        cpu: "2"
        memory: 4Gi
  server:
    resources: {}

victoriametrics:
  vmagentAgg:
    resources: {}
  vmagent:
    resources: {}
  vmclusterShortterm:
    vmstorage:
      resources: {}
    vminsert:
      resources: {}
  vmcluster:
    vmstorage:
      resources: {}
    vmselect:
      resources: {}
    vminsert:
      resources: {}
  vmauth:
    resources: {}

fluentbit:
  resources: {}
vmalert:
  vmAlert:
    resources: {}
  vmAlertLog:
    resources: {}
  alertmanager:
    resources: {}
```

## Storage sizes

Use Kubernetes quantities with an explicit unit for every storage size, such as `5Gi`, `100Gi`, or `1Ti`. A bare value such as `30` means 30 bytes, not 30 GiB.

```yaml
clickhouse:
  # legacy shared defaults (applies to both keeper/server if component values are empty)
  storageClassName: openebs-three-replica
  storageSize: 10Gi
  keeper:
    storageClassName: openebs-three-replica
    storageSize: 10Gi
  server:
    storageClassName: openebs-three-replica
    storageSize: 10Gi
cnpg:
  storageSize: 10Gi
victoriametrics:
  vmagentAgg:
    storageSize: 2Gi
  vmclusterShortterm:
    vmstorage:
      storageSize: 5Gi
  vmcluster:
    vmstorage:
      storageSize: 10Gi
    vmselect:
      storageSize: 1Gi
victoria-logs-single:
  server:
    persistentVolume:
      size: 10Gi
storage:
  modelPvc:
    size: 20Gi
skypilot:
  pvc:
    storageClassName: openebs-three-replica
    size: 10Gi
```

SkyPilot PVC access mode defaults to `ReadWriteOnce`.

## VictoriaMetrics multi-retention

The chart deploys two VictoriaMetrics clusters with independent retention and scaling:

- **shortterm** (`vmclusterShortterm`): handles system telemetry metrics. Short retention (default `90d`). No vmselect nodes (queries go through the main cluster).
- **main** (`vmcluster`): handles the rest of the metrics such as usages. Long retention (default `100y`). Has vmselect nodes that query both clusters via the auto-generated `storageNode` list.

```yaml
victoriametrics:
  vmclusterShortterm:
    retentionPeriod: "90d"
    vmstorage:
      replicaCount: 2
      storageSize: 5Gi
      resources: {}
    vminsert:
      replicaCount: 2
      resources: {}
  vmcluster:
    retentionPeriod: "100y"
    replicationFactor: 2
    vmstorage:
      replicaCount: 2
      storageSize: 10Gi
      resources: {}
    vmselect:
      replicaCount: 2
      storageSize: 1Gi
      resources: {}
    vminsert:
      replicaCount: 2
      resources: {}
```

The `storageNode` list for the main cluster's vmselect is auto-generated from both clusters' `vmstorage.replicaCount` values. Do not edit it manually.

## Studio Public URL (required)

Studio login/session behavior depends on these values:

- `studio.config.HOST`: host or `host:port` (no scheme)
- `studio.config.ORIGIN`: full URL with scheme
- `studio.config.USE_SECURE_COOKIES`: `"true"` for HTTPS, `"false"` for HTTP

Defaults in `values.yaml` are placeholders and must be updated for your environment.

### HTTPS domain (recommended)

```yaml
studio:
  config:
    HOST: "studio.example.com"
    ORIGIN: "https://studio.example.com"
    USE_SECURE_COOKIES: "true"
```

If you want TLS terminated inside the cluster at the Cilium Gateway (rather than at an external load balancer), enable the HTTPS listener and point it to your TLS secret. See `docs/NETWORK.md` for the full setup including cert-manager integration.

### Direct HTTP NodePort

```yaml
studio:
  config:
    HOST: "10.42.100.13:38023"
    ORIGIN: "http://10.42.100.13:38023"
    USE_SECURE_COOKIES: "false"
```

If the final endpoint is known only after install, update `.local/studio-values.yaml`, repeat the `values build` command for the deployment mode, and run the normal Helm upgrade command from the [recommended install flow](../README.md#8-install-tokenvisor). Keeping the source file current prevents a later values build from restoring a stale public URL.

## Studio theme + logos

The chart ships with a default Studio theme and default logos, so branding works out of the box.

To restyle the theme, override `studio.themeCss`:

```yaml
studio:
  themeCss: |
    :root {
      --primary: 192 67% 32%;
    }
```

To override default logos, put the overrides in their own values file. Override only the logos you want to change; the format is base64 of the SVG (`base64 -w 0 <ICON>.svg`):

```bash
cat > values.studio-logos.yaml <<'YAML'
studio:
  logosBinaryData:
    favicon.svg: "<base64>" # omit a key to keep its chart default
    icon-square.svg: "<base64>"
    icon-landscape.svg: "<base64>"
    icon-landscape-auth.svg: "<base64>"
YAML
```

Then add the file to your install/upgrade command, keeping any `-f` overlays you already use:

```bash
helm upgrade --install tokenvisor . \
  -n tokenvisor \
  -f values.yaml \
  ... \
  -f values.studio-logos.yaml
```

See `docs/Guides-for-Admins/logo.md` for the full white-labeling guide.

## Gateway routing

```yaml
network:
  gateway:
    port: 18080
  routes:
    emuPath: /api/v1
    studioPath: /
    grafana:
      path: /grafana
```

## Enable optional components

```yaml
grafana:
  enabled: true
vmalert:
  enabled: true
  tokenvisorWebhookUrl: "https://discord.com/api/webhooks/..."
  tokenvisorLogWebhookUrl: "https://discord.com/api/webhooks/..."
  enableLogRules: true
fluentbit:
  enabled: true
  # Defaults to fluent-operator-system to match the Fluent Operator install namespace.
  namespace: fluent-operator-system
```

When Grafana is enabled, the chart installs TokenVisor dashboards plus operator/VM/VLogs dashboards. When Fluent Bit is enabled, install Fluent Operator first and apply `docs/HOST_SETUP.md` sysctl settings on the nodes.

## Skypilot

```yaml
skypilot:
  enabled: false
```

To point EMU to the SkyPilot API server:

```yaml
emu:
  config:
    SKYPILOT_API_SERVER_ENDPOINT: "http://skypilot-api-service.skypilot.svc.cluster.local"
```

## Startup dependency waiters

EMU/Starling wait for ClickHouse schema + Postgres + VictoriaMetrics. Studio waits for EMU `/api/health`.

```yaml
emu:
  initWaiter:
    enabled: true
    timeoutSeconds: 600
    postgres:
      host: tokenvisor-pgbouncer.tokenvisor.svc.cluster.local
      port: 5432
    clickhouse:
      host: clickhouse-tokenvisor.tokenvisor.svc.cluster.local
      clusterName: tv-cluster
      checkClusterCount: true
      expectedClusterNumber: 3
      requiredTables:
        - llm_usage
        - embed_usage
        - rerank_usage
        - deployment_usage
        - emu_traces
    victoriametrics:
      host: vmauth-vmauth.tokenvisor.svc.cluster.local
      port: 8427

studio:
  initWaiter:
    enabled: true
    emuHealthUrl: "http://emu-api-server.tokenvisor.svc.cluster.local:5969/api/health"
```

If you manage ClickHouse schema yourself, either keep the required tables list in sync or disable the waiter.

## OTEL dynamic target rendering

By default (`emu.otelCollector.dynamicTargets.enabled=true`), VM/VL OTEL exporter endpoints are rendered from topology values (replica counts and service settings).

Safe changes:

- `victoriametrics.vmagentAgg.replicaCount`
- `victoria-logs-single.server.replicaCount`
- `emu.otelCollector.dynamicTargets.victoriaMetrics.*` and `emu.otelCollector.dynamicTargets.victoriaLogs.*` (keep service naming consistent)
- Non-topology OTEL settings in `emu.otelCollector.config` (receivers/processors/clickhouse/traces pipeline)

Avoid:

- Manual edits to `otlphttp/victoriametrics*` / `otlphttp/vl*` endpoint entries inside `emu.otelCollector.config` while dynamic targets are enabled.

If you disable dynamic target rendering, then you must manage VM/VL exporters and pipeline exporter lists manually in `emu.otelCollector.config`.

## Secrets wiring

If your secret names/keys differ:

```yaml
emu:
  secretRefs:
    clickhouseSecretName: clickhouse-secret
    clickhousePasswordKey: db_user_password
    vmuserSecretName: vmuser-secret
    vmuserPasswordKey: password

grafana:
  adminSecret:
    name: grafana-secret
    key: admin_password
  clickhouseSecret:
    name: clickhouse-secret
    key: db_readonly_user_password
```

## Image pull secret name

The `tokenvisor` namespace uses `registry-secret`. Override the name if needed:

```yaml
global:
  imagePullSecrets:
    - name: registry-secret
skypilot:
  imagePullSecrets:
    - name: registry-secret
```

See `docs/SECRETS.md` for how to create these secrets.
