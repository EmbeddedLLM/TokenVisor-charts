{{- define "tokenvisor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "tokenvisor.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- printf "%s" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "tokenvisor.namespace" -}}
{{- default .Release.Namespace .Values.global.namespace -}}
{{- end -}}

{{- define "tokenvisor.vlServerServiceName" -}}
{{- $vlValues := index .Values "victoria-logs-single" -}}
{{- $name := default "" $vlValues.fullnameOverride -}}
{{- if not $name -}}
{{- fail "victoria-logs-single.fullnameOverride must be set for deterministic VictoriaLogs host rendering" -}}
{{- end -}}
{{- printf "%s-server" $name -}}
{{- end -}}

{{- define "tokenvisor.vlServerHostsJson" -}}
{{- $vlValues := index .Values "victoria-logs-single" -}}
{{- $ns := include "tokenvisor.namespace" . -}}
{{- $svc := include "tokenvisor.vlServerServiceName" . -}}
{{- $replicas := int $vlValues.server.replicaCount -}}
{{- if lt $replicas 1 -}}
{{- fail "victoria-logs-single.server.replicaCount must be >= 1" -}}
{{- end -}}
{{- $hosts := list -}}
{{- if eq $replicas 1 -}}
{{- $hosts = append $hosts (printf "%s.%s.svc" $svc $ns) -}}
{{- else -}}
{{- range $i := until $replicas -}}
{{- $hosts = append $hosts (printf "%s-%d.%s.%s.svc" $svc $i $svc $ns) -}}
{{- end -}}
{{- end -}}
{{- toJson $hosts -}}
{{- end -}}

{{- define "tokenvisor.vmagentAggHostsJson" -}}
{{- $ns := include "tokenvisor.namespace" . -}}
{{- $serviceName := .Values.emu.otelCollector.dynamicTargets.victoriaMetrics.serviceName -}}
{{- if not $serviceName -}}
{{- fail "emu.otelCollector.dynamicTargets.victoriaMetrics.serviceName must be set when dynamic OTEL targets are enabled" -}}
{{- end -}}
{{- $replicas := int .Values.victoriametrics.vmagentAgg.replicaCount -}}
{{- if lt $replicas 1 -}}
{{- fail "victoriametrics.vmagentAgg.replicaCount must be >= 1" -}}
{{- end -}}
{{- $hosts := list -}}
{{- if eq $replicas 1 -}}
{{- $hosts = append $hosts (printf "%s.%s.svc" $serviceName $ns) -}}
{{- else -}}
{{- $podPrefix := default "vmagent-vmagent-agg" .Values.victoriametrics.vmagentAgg.podPrefix -}}
{{- range $i := until $replicas -}}
{{- $hosts = append $hosts (printf "%s-%d.%s.%s.svc" $podPrefix $i $serviceName $ns) -}}
{{- end -}}
{{- end -}}
{{- toJson $hosts -}}
{{- end -}}

{{- define "tokenvisor.vmselectStorageNode" -}}
{{- $ns := include "tokenvisor.namespace" . -}}
{{- $mainReplicas := int .Values.victoriametrics.vmcluster.vmstorage.replicaCount -}}
{{- $shortReplicas := int .Values.victoriametrics.vmclusterShortterm.vmstorage.replicaCount -}}
{{- $nodes := list -}}
{{- range $i := until $mainReplicas -}}
{{- $nodes = append $nodes (printf "vmstorage-victoria-cluster-%d.vmstorage-victoria-cluster.%s.svc.cluster.local:8401" $i $ns) -}}
{{- end -}}
{{- range $i := until $shortReplicas -}}
{{- $nodes = append $nodes (printf "vmstorage-victoria-cluster-shortterm-%d.vmstorage-victoria-cluster-shortterm.%s.svc.cluster.local:8401" $i $ns) -}}
{{- end -}}
{{- join "," $nodes -}}
{{- end -}}

{{- define "tokenvisor.labels" -}}
app.kubernetes.io/name: {{ include "tokenvisor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | quote }}
{{- end -}}

{{- define "tokenvisor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tokenvisor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "tokenvisor.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.global.imagePullSecrets }}
  - name: {{ if kindIs "map" . }}{{ .name }}{{ else }}{{ . }}{{ end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
HA pod scheduling for control-plane-pinned components (first-party Deployments and
VictoriaMetrics operator components). Renders nodeSelector + tolerations + one-pod-per-node
podAntiAffinity ONLY when deployment.mode == ha. Each block falls back to a control-plane
default, overridable per component via .svc.nodeSelector / .tolerations / .affinity.
The anti-affinity labelSelector uses the caller-supplied .podLabels dict, since first-party
Deployments key on `app` while VM operator pods key on app.kubernetes.io/{name,instance}.
Usage: {{ include "tokenvisor.haScheduling" (dict "ctx" $ "svc" .Values.emu "podLabels" (dict "app" "emu")) | nindent 6 }}
*/}}
{{- define "tokenvisor.haScheduling" -}}
{{- $ctx := .ctx -}}
{{- $svc := .svc -}}
{{- $podLabels := .podLabels -}}
{{- if eq (default "ha" $ctx.Values.deployment.mode) "ha" -}}
{{- with $svc.nodeSelector }}
nodeSelector:
{{- toYaml . | nindent 2 }}
{{- else }}
nodeSelector:
  node-role.kubernetes.io/control-plane: "true"
{{- end }}
{{- with $svc.tolerations }}
tolerations:
{{- toYaml . | nindent 2 }}
{{- else }}
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
{{- end }}
{{- with $svc.affinity }}
affinity:
{{- toYaml . | nindent 2 }}
{{- else }}
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
{{- toYaml $podLabels | nindent 12 }}
        topologyKey: kubernetes.io/hostname
{{- end }}
{{- end -}}
{{- end -}}

{{/*
HA rollout strategy for first-party Deployments.
Renders surge-down RollingUpdate (maxSurge=0) ONLY when deployment.mode == ha, so the
hard anti-affinity above does not deadlock rollouts when replicas == eligible nodes.
Overridable per service via .strategy.
Usage: {{ include "tokenvisor.haStrategy" (dict "ctx" $ "svc" .Values.emu) | nindent 2 }}
*/}}
{{- define "tokenvisor.haStrategy" -}}
{{- $ctx := .ctx -}}
{{- $svc := .svc -}}
{{- if eq (default "ha" $ctx.Values.deployment.mode) "ha" -}}
{{- with $svc.strategy }}
strategy:
{{- toYaml . | nindent 2 }}
{{- else }}
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 0
    maxUnavailable: 1
{{- end }}
{{- end -}}
{{- end -}}

{{- define "tokenvisor.waitPostgresScript" -}}
set -e
HOST="{{ .Values.emu.initWaiter.postgres.host }}"
PORT="{{ .Values.emu.initWaiter.postgres.port }}"
INTERVAL="{{ .Values.emu.initWaiter.intervalSeconds }}"
ATTEMPTS={{ div (int .Values.emu.initWaiter.timeoutSeconds) (int .Values.emu.initWaiter.intervalSeconds) }}
echo "Waiting for Postgres at ${HOST}:${PORT}..."
i=0
while [ $i -lt $ATTEMPTS ]; do
  if pg_isready -h "${HOST}" -p "${PORT}" >/dev/null 2>&1; then
    echo "Postgres is ready."
    exit 0
  fi
  i=$((i+1))
  sleep "${INTERVAL}"
done
echo "Timed out waiting for Postgres."
exit 1
{{- end -}}

{{- define "tokenvisor.waitClickhouseVmScript" -}}
set -e
CH_HOST="{{ .Values.emu.initWaiter.clickhouse.host }}"
CH_PORT="{{ .Values.emu.initWaiter.clickhouse.port }}"
CH_USER="{{ .Values.emu.initWaiter.clickhouse.user }}"
CH_DB="{{ .Values.emu.initWaiter.clickhouse.database }}"
CH_CLUSTER_NAME="{{ .Values.emu.initWaiter.clickhouse.clusterName }}"
CH_CHECK_CLUSTER_COUNT="{{ ternary "true" "false" .Values.emu.initWaiter.clickhouse.checkClusterCount }}"
EXPECTED_CLUSTER_COUNT="{{ default .Values.clickhouse.clusterReplicas .Values.emu.initWaiter.clickhouse.expectedClusterNumber }}"
CH_REQUIRED_TABLES="{{ join " " .Values.emu.initWaiter.clickhouse.requiredTables }}"
VM_HOST="{{ .Values.emu.initWaiter.victoriametrics.host }}"
VM_PORT="{{ .Values.emu.initWaiter.victoriametrics.port }}"
INTERVAL="{{ .Values.emu.initWaiter.intervalSeconds }}"
ATTEMPTS={{ div (int .Values.emu.initWaiter.timeoutSeconds) (int .Values.emu.initWaiter.intervalSeconds) }}
EXPECTED_TABLE_COUNT={{ len .Values.emu.initWaiter.clickhouse.requiredTables }}

if [ "${CH_CHECK_CLUSTER_COUNT}" = "true" ]; then
  case "${EXPECTED_CLUSTER_COUNT}" in
    ''|*[!0-9]*)
      echo "Invalid EXPECTED_CLUSTER_COUNT: ${EXPECTED_CLUSTER_COUNT}"
      exit 1
      ;;
  esac
fi

echo "Waiting for ClickHouse cluster/schema + VictoriaMetrics..."
i=0
while [ $i -lt $ATTEMPTS ]; do
  vm_code=$(curl -s -o /dev/null -w "%{http_code}" "http://${VM_HOST}:${VM_PORT}/" || true)
  ch_ready=$(curl -sG "http://${CH_HOST}:${CH_PORT}/" \
    --data-urlencode "user=${CH_USER}" \
    --data-urlencode "password=${CH_PASSWORD}" \
    --data-urlencode "query=SELECT 1" || true)
  ch_ready=$(echo "${ch_ready}" | tr -d '\r\n')

  cluster_ready=1
  if [ "${CH_CHECK_CLUSTER_COUNT}" = "true" ]; then
    cluster_count=0
    cluster_count=$(curl -sG "http://${CH_HOST}:${CH_PORT}/" \
      --data-urlencode "user=${CH_USER}" \
      --data-urlencode "password=${CH_PASSWORD}" \
      --data-urlencode "query=SELECT count() FROM system.clusters WHERE cluster='${CH_CLUSTER_NAME}'" || true)
    cluster_count=$(echo "${cluster_count}" | tr -d '\r\n')
    case "${cluster_count}" in
      ''|*[!0-9]*)
        cluster_count=0
        ;;
    esac
    if [ "${cluster_count}" -ne "${EXPECTED_CLUSTER_COUNT}" ]; then
      cluster_ready=0
    fi
  fi

  tables_ready=1
  if [ "${EXPECTED_TABLE_COUNT}" -gt 0 ]; then
    for table in ${CH_REQUIRED_TABLES}; do
      exists=$(curl -sG "http://${CH_HOST}:${CH_PORT}/" \
        --data-urlencode "user=${CH_USER}" \
        --data-urlencode "password=${CH_PASSWORD}" \
        --data-urlencode "query=SELECT count() FROM system.tables WHERE database='${CH_DB}' AND name='${table}'" || true)
      exists=$(echo "${exists}" | tr -d '\r\n')
      if [ "${exists}" != "1" ]; then
        tables_ready=0
        break
      fi
    done
  fi

  if [ "${vm_code}" != "000" ] && [ "${ch_ready}" = "1" ] && [ "${cluster_ready}" -eq 1 ] && [ "${tables_ready}" -eq 1 ]; then
    echo "ClickHouse cluster/schema and VictoriaMetrics are ready."
    exit 0
  fi

  i=$((i+1))
  sleep "${INTERVAL}"
done
echo "Timed out waiting for ClickHouse cluster/schema or VictoriaMetrics."
exit 1
{{- end -}}
