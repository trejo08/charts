# Marble Helm Chart

Kubernetes Helm chart for [Marble](https://www.checkmarble.com) — open-source fraud detection and AML platform.

## Install

```bash
helm repo add trejo08 https://trejo08.github.io/charts
helm repo update
helm install marble trejo08/marble \
  --set marble.appUrl=https://marble.example.com \
  --set marble.postgres.connectionString="postgres://user:pass@host:5432/marble?sslmode=require" \
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
helm install marble oci://ghcr.io/trejo08/charts/marble --version 0.1.5
```

## Architecture

Marble runs 4 processes from the same backend binary:

| Process | Flag | Description |
|---------|------|-------------|
| API | `--server` | REST API for decisions and data ingestion |
| Worker | `--worker` | Async job queue (River/PostgreSQL) |
| Analytics | `--analytics` | DuckDB analytics proxy (optional) |
| Migrations | `--migrations` | Schema migrations (pre-install/upgrade Helm hook) |

## Prerequisites

- **PostgreSQL 16** with the **PostGIS** extension enabled (`postgis/postgis:16-3.5-alpine`)
- **ECK Operator** — required only if `sanctions.enabled: true`
- **External Secrets Operator (ESO)** — optional; enables automatic secret sync from AWS Secrets Manager, Vault, etc.

---

## Secret management

This is the most critical part of the installation. Read carefully before deploying.

### Overview

The chart manages two distinct Kubernetes Secrets:

| Secret | Name | Purpose |
|--------|------|---------|
| Main secret | `<release>-secrets` | All app env vars (DB connection, Firebase keys, session secret, etc.) |
| JWT secret | `<release>-secrets-jwt` | RSA private key PEM file, mounted as `/secrets/jwt.pem` |

The JWT secret is kept separate because the PEM is a multi-line file — it cannot be stored inline
in a JSON-based secret without breaking the JSON encoding. The solution is to store the PEM
**base64-encoded** in the remote secret store and let ESO decode it back to the original PEM
when writing the Kubernetes Secret.

---

### Option A — External Secrets Operator (recommended)

#### Step 1 — Prepare the remote secret

Create a secret in your provider (AWS Secrets Manager, Vault, etc.) with the following structure.

> **Important:** Do NOT include `AUTHENTICATION_JWT_SIGNING_KEY` as a plain text multi-line value.
> The JSON encoding of the remote secret will break with literal newlines inside a string value.
> Instead, store the PEM base64-encoded under a separate key (default: `JWT_SIGNING_KEY_B64`).

**Required keys:**

| Key | Value |
|-----|-------|
| `PG_CONNECTION_STRING` | `postgres://user:pass@host:5432/marble?sslmode=require` |
| `SESSION_SECRET` | Secure random string (min 32 chars) |
| `FIREBASE_API_KEY` | Firebase project API key |
| `FIREBASE_PROJECT_ID` | Firebase / GCP project ID |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID |
| `INGESTION_BUCKET_URL` | `s3://marble-ingestion` |
| `CASE_MANAGER_BUCKET_URL` | `s3://marble-cases` |
| `ANALYTICS_BUCKET_URL` | `s3://marble-analytics` |
| `JWT_SIGNING_KEY_B64` | RSA 4096 private key PEM, **base64-encoded** (see below) |

**How to generate and encode the JWT signing key:**

```bash
# Generate RSA 4096 private key
openssl genrsa -out jwt.pem 4096

# Base64-encode it (single line, no line breaks)
base64 -w 0 jwt.pem   # Linux
base64 -i jwt.pem     # macOS

# Store the output as JWT_SIGNING_KEY_B64 in your remote secret
```

> **Why base64?**
> The RSA PEM contains literal newline characters. When stored as a JSON string value in AWS
> Secrets Manager or Vault, those newlines corrupt the JSON document. Storing it base64-encoded
> produces a single-line string that is safe to embed in JSON. ESO decodes it back to the original
> PEM when writing the Kubernetes Secret, so the mounted file `/secrets/jwt.pem` contains the
> proper PEM that Marble expects.

**AWS Secrets Manager example:**

```bash
aws secretsmanager create-secret \
  --name marble-prod \
  --region us-east-1 \
  --secret-string '{
    "PG_CONNECTION_STRING": "postgres://...",
    "SESSION_SECRET": "...",
    "FIREBASE_API_KEY": "...",
    "FIREBASE_PROJECT_ID": "...",
    "GOOGLE_CLOUD_PROJECT": "...",
    "INGESTION_BUCKET_URL": "s3://marble-ingestion",
    "CASE_MANAGER_BUCKET_URL": "s3://marble-cases",
    "ANALYTICS_BUCKET_URL": "s3://marble-analytics",
    "JWT_SIGNING_KEY_B64": "<output of base64 command above>"
  }'
```

#### Step 2 — Configure the chart

```yaml
marble:
  externalSecret:
    enabled: true
    clusterSecretStore: aws-secrets-manager   # ClusterSecretStore name in your cluster
    remoteSecretName: marble-prod             # Key/path in the remote secret store
    refreshInterval: "1h"
    jwtSigningKeyProperty: "JWT_SIGNING_KEY_B64"  # Key name holding the base64 PEM (default)
```

The chart creates two `ExternalSecret` resources:

1. **`<release>-secrets`** — extracts all keys from the remote secret via `dataFrom.extract`.
   Used as `envFrom` in api, worker, analytics, and migrations pods.

2. **`<release>-secrets-jwt`** — extracts only `JWT_SIGNING_KEY_B64` with `decodingStrategy: Base64`,
   writing the decoded PEM as `jwt.pem`. Mounted as a volume at `/secrets/jwt.pem`.
   `AUTHENTICATION_JWT_SIGNING_KEY_FILE=/secrets/jwt.pem` is injected automatically.

The `apiVersion` of both ExternalSecrets is auto-detected from the cluster:
- `external-secrets.io/v1` — ESO ≥ 0.17.0 / v1.0.0 GA (Nov 2025)
- `external-secrets.io/v1beta1` — ESO < 0.17.0 (legacy, auto-fallback)

> **To disable JWT file mounting** (e.g. you handle the key differently), set:
> ```yaml
> marble:
>   externalSecret:
>     jwtSigningKeyProperty: ""
> ```
> You are then responsible for providing `AUTHENTICATION_JWT_SIGNING_KEY` or
> `AUTHENTICATION_JWT_SIGNING_KEY_FILE` through another mechanism.

---

### Option B — Pre-existing Kubernetes Secret

If ESO is not available, create the Secrets manually before installing the chart.

**Main secret** (named exactly `<release>-secrets`):

```bash
kubectl create secret generic marble-prod-secrets \
  --namespace marble \
  --from-literal=PG_CONNECTION_STRING="postgres://..." \
  --from-literal=SESSION_SECRET="..." \
  --from-literal=FIREBASE_API_KEY="..." \
  --from-literal=FIREBASE_PROJECT_ID="..." \
  --from-literal=GOOGLE_CLOUD_PROJECT="..." \
  --from-literal=INGESTION_BUCKET_URL="s3://..." \
  --from-literal=CASE_MANAGER_BUCKET_URL="s3://..." \
  --from-literal=ANALYTICS_BUCKET_URL="s3://..."
```

**JWT secret** (named exactly `<release>-secrets-jwt`):

```bash
# The secret must have a key named "jwt.pem" containing the raw PEM (not base64)
kubectl create secret generic marble-prod-secrets-jwt \
  --namespace marble \
  --from-file=jwt.pem=./jwt.pem
```

Then configure the chart:

```yaml
marble:
  externalSecret:
    enabled: false
    jwtSigningKeyProperty: "JWT_SIGNING_KEY_B64"  # keep non-empty so volumes are mounted
  existingSecret:
    enabled: true
```

> The chart always mounts the JWT volume from `<release>-secrets-jwt` when
> `jwtSigningKeyProperty` is non-empty, regardless of whether ESO is enabled.
> You must create that Secret manually when using Option B.

---

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
