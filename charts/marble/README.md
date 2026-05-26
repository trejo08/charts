# Marble Helm Chart

Kubernetes Helm chart for [Marble](https://www.checkmarble.com) — open-source fraud detection and AML platform.

## Install

```bash
helm repo add trejo08 https://trejo08.github.io/charts
helm repo update
helm install marble trejo08/marble \
  --set marble.appUrl=https://marble.example.com \
  --set marble.postgres.connectionString="postgres://user:pass@host:5432/marble?sslmode=require" \
  --set marble.auth.jwtSigningKey="<rsa-pem>" \
  --set marble.firebase.apiKey="<key>" \
  --set marble.firebase.projectId="<project>" \
  --set marble.firebase.googleCloudProject="<project>" \
  --set marble.storage.ingestionBucketUrl="s3://marble-ingestion" \
  --set marble.storage.caseManagerBucketUrl="s3://marble-cases" \
  --set marble.storage.analyticsBucketUrl="s3://marble-analytics" \
  --set frontendConfig.sessionSecret="<random-32-chars>"
```

Or via OCI:

```bash
helm install marble oci://ghcr.io/trejo08/charts/marble
```

## Architecture

Marble runs 4 processes from the same backend binary:

| Process | Flag | Description |
|---------|------|-------------|
| API | `--server` | REST API for decisions and data ingestion |
| Worker | `--worker` | Async job queue (River/PostgreSQL) |
| Analytics | `--analytics` | DuckDB analytics proxy (optional) |
| Migrations | `--migrations` | Schema migrations (Helm hook) |

## Prerequisites

- **PostgreSQL 16** with the **PostGIS** extension enabled (`postgis/postgis:16-3.5-alpine`)
- **ECK Operator** — required only if `sanctions.enabled: true`
- **External Secrets Operator** — optional; if present, set `marble.externalSecret.enabled: true`

## Secret management

### Option A — External Secrets Operator (recommended)

```yaml
marble:
  externalSecret:
    enabled: true
    clusterSecretStore: aws-secrets-manager
    remoteSecretName: marble-prod
    refreshInterval: "1h"
```

The chart creates an `ExternalSecret` that extracts all keys from the remote secret into a
Kubernetes Secret named `<release-name>-secrets`. The API version (`v1` or `v1beta1`) is
detected automatically from the cluster.

### Option B — Pre-existing Kubernetes Secret

Create a Secret named exactly `<release-name>-secrets` before install, then set:

```yaml
marble:
  externalSecret:
    enabled: false
  existingSecret:
    enabled: true
```

## Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  frontend:
    hostname: marble.example.com
    tls:
      enabled: true
      secretName: marble-tls
  api:
    enabled: true
    hostname: api.marble.example.com
    tls:
      enabled: true
      secretName: marble-api-tls
```

## Analytics

```yaml
analytics:
  enabled: true

marble:
  storage:
    analyticsBucketUrl: "s3://marble-analytics"
```

## Sanctions screening

Self-hosted (requires ECK Operator):

```yaml
sanctions:
  enabled: true
```

Via OpenSanctions SaaS API (recommended — no Elasticsearch required):

```yaml
sanctions:
  enabled: true
  opensanctions:
    apiHost: "https://api.opensanctions.org"
    apiKey: "<your-api-key>"
```

## Values reference

See [values.yaml](values.yaml) for the full reference with inline documentation.

## Integration guide

See [docs/integration-guide.md](docs/integration-guide.md) for REST API integration patterns.

## Sources

- [Marble](https://github.com/checkmarble/marble)
- [Marble Backend](https://github.com/checkmarble/marble-backend)
- [Marble Documentation](https://docs.checkmarble.com)
