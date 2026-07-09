# Secrets

> **Recommended path:** `./bin/tokenvisor-prereqs secrets init --interactive` then `./bin/tokenvisor-prereqs secrets apply`
>
> See [PREREQS_HELPER.md](PREREQS_HELPER.md) for all helper options. The manual steps below are for customization beyond the helper defaults.

Create required secrets before Helm install (default values expect pre-created secrets).

Run from chart root (`charts/tokenvisor`).

The interactive generator creates secure defaults for required internal secrets, Grafana admin password, and `EMU_DB_PATH`. Internal secret/password prompts are hidden following standard password-entry practice. Provider API key prompts are visible for paste verification; press Enter to leave them empty. The helper refuses to apply `.local/tokenvisor-secrets.yaml` while `CHANGE_ME_` placeholders remain.

For private GHCR images, also use `./bin/tokenvisor-prereqs secrets ghcr --apply` after exporting `GHCR_USERNAME` and `GHCR_TOKEN`.

## Create or update secrets

```bash
cp docs/SECRETS_TEMPLATE.yaml /tmp/tokenvisor-secrets.yaml
nano /tmp/tokenvisor-secrets.yaml
```

Re-run `kubectl apply -f /tmp/tokenvisor-secrets.yaml` whenever values change.

Before applying, ensure no `CHANGE_ME_` markers remain:

```bash
if rg -n "CHANGE_ME_" /tmp/tokenvisor-secrets.yaml; then
  echo "ERROR: replace all CHANGE_ME_ values before applying"
else
  kubectl apply -f /tmp/tokenvisor-secrets.yaml
fi
```

## GitHub Container Registry pull secret

The private TokenVisor images (emu, studio) are hosted on `ghcr.io` and pulled into the `tokenvisor` namespace, so create the `registry-secret` pull secret there:

```bash
kubectl create secret docker-registry registry-secret \
  --namespace tokenvisor \
  --docker-server=ghcr.io \
  --docker-username=<github-username> \
  --docker-password=<github-pat>
```

The GitHub PAT needs at least `read:packages` scope.

## Required secrets (default names)

- `clickhouse-secret`
  - `cluster_secret`
  - `db_user_password`
  - `db_readonly_user_password`
- `pg-emu-user-secret`
  - `username`
  - `password`
- `vmuser-secret`
  - `password`
- `emu-secret`
  - `EMU_DB_PATH`
  - `EMU_SERVICE_KEY`
- `studio-secret`
  - `STUDIO_AUTH_SECRET`

Optional:

- `grafana-secret`
  - `admin_password` (if Grafana enabled)

## Wiring notes

- `EMU_DB_PATH` password must match `pg-emu-user-secret.password`.
- In the template, both are set to `CHANGE_ME_EMUPG_PASSWORD`; keep them identical after editing.
- Studio reads `EMU_SERVICE_KEY` from `emu-secret`.
- EMU reads VictoriaMetrics password from `vmuser-secret.password`.
- OTEL reads ClickHouse password from `clickhouse-secret.db_user_password`.

If you change secret names or keys, update chart values accordingly.
