# Marble Helm Chart

Kubernetes Helm chart for [Marble](https://www.checkmarble.com) — open-source fraud detection and AML platform.

## Install

```bash
helm repo add trejo08 https://trejo08.github.io/charts
helm repo update
helm install marble trejo08/marble \
  --namespace marble \
  --set marble.externalSecret.enabled=true \
  --set marble.externalSecret.clusterSecretStore=<store-name> \
  --set marble.externalSecret.remoteSecretName=<secret-name> \
  --set marble.firebase.gcpServiceAccountProperty=GCP_SERVICE_ACCOUNT_B64
```

Or via OCI:

```bash
helm install marble oci://ghcr.io/trejo08/charts/marble --version 0.1.7 \
  --namespace marble \
  --set marble.externalSecret.enabled=true \
  --set marble.externalSecret.clusterSecretStore=<store-name> \
  --set marble.externalSecret.remoteSecretName=<secret-name> \
  --set marble.firebase.gcpServiceAccountProperty=GCP_SERVICE_ACCOUNT_B64
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

- **PostgreSQL 16+** with the **PostGIS** extension enabled
- **GCP service account JSON** with `Firebase Authentication Admin` role — required for Firebase Admin SDK on non-GCP infrastructure
- **ECK Operator** — required only if `sanctions.enabled: true`
- **External Secrets Operator (ESO)** — optional but strongly recommended

---

## Secret management

**Design principle:** the chart does not inline any application configuration. Every environment
variable marble-backend and marble-frontend read must live in the remote secret store and arrive
in the pods via `envFrom`. The chart only injects values it constructs itself (mount paths for
volumes it creates).

The chart manages up to three Kubernetes Secrets, all created via ExternalSecret:

| Secret | Name | Purpose |
|--------|------|---------|
| Main | `<release>-secrets` | All env vars — extracted via `dataFrom` from the remote secret |
| JWT | `<release>-secrets-jwt` | RSA private key PEM decoded from base64, mounted at `/secrets/jwt.pem` |
| Firebase SA | `<release>-firebase-sa` | GCP service account JSON decoded from base64, mounted at `/secrets/firebase/firebase.json` |

---

### Remote secret — complete variable reference

Create one secret in your provider with ALL of the following keys. The chart extracts every key
via `dataFrom.extract` and makes them available as env vars inside every backend pod.

#### Required

| Key | Description |
|-----|-------------|
| `PG_CONNECTION_STRING` | Full PostgreSQL DSN: `postgres://user:pass@host:5432/db?sslmode=require` |
| `PORT` | TCP port the backend HTTP server listens on (e.g. `8080`) |
| `ENV` | Environment name: `production` |
| `APP_URL` | Public URL of the frontend app: `https://marble.example.com` |
| `MARBLE_APP_URL` | Same as `APP_URL` — both vars are read by different parts of marble-backend |
| `FIREBASE_API_KEY` | Firebase Web API key (from Firebase Console → Project Settings → General) |
| `FIREBASE_PROJECT_ID` | Firebase / GCP project ID |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID (same value as `FIREBASE_PROJECT_ID` in most cases) |
| `FIREBASE_AUTH_DOMAIN` | Firebase auth domain for OAuth redirects. Set to your app domain (e.g. `marble.example.com`) or `<project-id>.firebaseapp.com` |
| `INGESTION_BUCKET_URL` | Blob storage URL for data ingestion: `s3://marble-ingestion` |
| `CASE_MANAGER_BUCKET_URL` | Blob storage URL for case attachments: `s3://marble-cases` |
| `SESSION_SECRET` | Secure random string for frontend session cookie signing (min 32 chars) |
| `JWT_SIGNING_KEY_B64` | RSA 4096 private key PEM **base64-encoded** — see generation instructions below |
| `GCP_SERVICE_ACCOUNT_B64` | GCP service account JSON **base64-encoded** — required for Firebase Admin SDK on non-GCP infra — see instructions below |

#### Recommended

| Key | Description |
|-----|-------------|
| `SCREENING_INDEXER_TOKEN` | Shared secret between marble-backend and the sanctions indexer (motiva/yente). Must be stable across restarts. If absent, a random token is generated per restart, breaking self-hosted sanctions. Generate with: `openssl rand -hex 32` |
| `ANALYTICS_BUCKET_URL` | Blob storage URL for analytics Parquet exports: `s3://marble-analytics` |
| `LOGGING_FORMAT` | Log format: `json` (recommended for production) or `text` |
| `PG_MAX_POOL_SIZE` | PostgreSQL connection pool size (default: `40`) |
| `DISABLE_SEGMENT` | Set to `true` to disable Segment analytics telemetry |

#### Optional — authentication

| Key | Description |
|-----|-------------|
| `AUTHENTICATION_JWT_SIGNING_KEY_FILE` | Path to the JWT PEM file. Set to `/secrets/jwt.pem` when using the ESO JWT secret (the chart injects this automatically when `jwtSigningKeyProperty` is set). |
| `AUTH_PROVIDER` | `firebase` (default) or `oidc` |
| `AUTH_OIDC_ISSUER` | OIDC issuer URL (when `AUTH_PROVIDER=oidc`) |
| `AUTH_OIDC_CLIENT_ID` | OIDC client ID |
| `AUTH_OIDC_CLIENT_SECRET` | OIDC client secret |
| `AUTH_OIDC_SCOPE` | Comma-separated scopes (default: `openid,profile,email,offline_access`) |
| `AUTH_OIDC_ALLOWED_DOMAINS` | Comma-separated allowed email domains |
| `AUTH_OIDC_EXTRA_PARAMS` | URL-encoded extra params (e.g. `prompt=consent&access_type=offline`) |
| `AUTH_OIDC_EMAIL_CLAIM` | Override email claim (e.g. `upn` for Entra ID) |
| `LICENSE_KEY` | Marble license key for premium features (SSO, advanced screening) |

#### Optional — storage

| Key | Description |
|-----|-------------|
| `OFFLOADING_BUCKET_URL` | Blob storage URL for data offloading |
| `CONTINUOUS_SCREENING_BUCKET_URL` | Blob storage URL for continuous screening datasets |

#### Optional — database

| Key | Description |
|-----|-------------|
| `PG_SSL_MODE` | PostgreSQL SSL mode: `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full` |
| `PG_IMPERSONATE_ROLE` | Role to `SET ROLE` after connect (for IAM-auth RBAC) |

#### Optional — Redis

| Key | Description |
|-----|-------------|
| `REDIS_HOST` | Redis address: `redis:6379` |
| `REDIS_KEY` | Redis auth password |
| `REDIS_TLS` | Enable Redis TLS: `true` or `false` |
| `REDIS_TLS_SKIP_VERIFY` | Skip Redis TLS cert verification: `true` or `false` |

#### Optional — timeouts (server)

| Key | Default | Description |
|-----|---------|-------------|
| `TOKEN_LIFETIME_MINUTE` | `120` | Marble JWT token lifetime in minutes |
| `BATCH_TIMEOUT_SECOND` | `55` | Batch ingestion request timeout in seconds |
| `DECISION_TIMEOUT_SECOND` | `10` | Decision evaluation timeout in seconds |
| `DEFAULT_TIMEOUT_SECOND` | `5` | Default request timeout in seconds |
| `ANALYTICS_TIMEOUT` | `15s` | Analytics query timeout (Go duration string) |
| `BATCH_INGESTION_MAX_SIZE` | `0` (unlimited) | Max records per batch ingestion call |

#### Optional — data offloading (worker)

| Key | Default | Description |
|-----|---------|-------------|
| `OFFLOADING_ENABLED` | `false` | Enable data offloading worker |
| `OFFLOADING_JOB_INTERVAL` | `30m` | Offloading job frequency (minimum 30m) |
| `OFFLOADING_BEFORE` | `168h` | Offload data older than this duration (7 days) |
| `OFFLOADING_BATCH_SIZE` | `1000` | Records per offloading batch |
| `OFFLOADING_SAVE_POINTS` | `100` | Savepoint frequency |
| `OFFLOADING_WRITES_PER_SEC` | `200` | Target write rate |

#### Optional — worker tuning

| Key | Default | Description |
|-----|---------|-------------|
| `RIVER_FETCH_POLL_INTERVAL` | `1s` | River job queue polling interval |
| `FAILED_WEBHOOKS_RETRY_PAGE_SIZE` | `1000` | Batch size for failed webhook retry |
| `SCAN_DATASET_UPDATES_INTERVAL` | `24h` | How often to scan for screening dataset updates |
| `CREATE_FULL_DATASET_INTERVAL` | `24h` | How often to create full screening datasets |
| `METRICS_COLLECTION_JOB_INTERVAL` | `1h` | Metrics collection job frequency |
| `METRICS_FALLBACK_DURATION` | `720h` | Metrics collection fallback window (30 days) |
| `DISABLE_TELEMETRY` | `false` | Disable metrics collection worker job |
| `CACHE_ENABLED` | `false` | Enable in-memory caching layer |
| `SIMILARITY_THRESHOLD` | model default | Fuzzy match threshold for screening (0–1 float) |

#### Optional — analytics export (worker)

| Key | Default | Description |
|-----|---------|-------------|
| `DISABLE_ANALYTICS` | `false` | Disable analytics export even when bucket is configured |
| `ANALYTICS_JOB_INTERVAL` | `1h` | Analytics export job frequency |
| `ANALYTICS_BATCH_SIZE` | `10000` | Records per analytics export batch |
| `ANALYTICS_PROXY_API_URL` | auto | URL of analytics proxy API (auto-constructed from service name when `analytics.enabled=true`) |

#### Optional — application URLs

| Key | Description |
|-----|-------------|
| `MARBLE_API_URL` | Public URL of the backend API (returned to frontend via `/config`) |
| `MARBLE_API_INTERNAL_URL` | Internal URL for server-to-server calls (falls back to `MARBLE_API_URL`) |
| `MARBLE_BACKOFFICE_URL` | URL of the Marble backoffice app |

#### Optional — webhooks (Convoy)

| Key | Description |
|-----|-------------|
| `CONVOY_API_KEY` | Convoy project API key |
| `CONVOY_API_URL` | Convoy API base URL |
| `CONVOY_PROJECT_ID` | Convoy project ID |
| `CONVOY_RATE_LIMIT` | Convoy delivery rate limit (default: `50`) |

#### Optional — sanctions screening

| Key | Description |
|-----|-------------|
| `SCREENING_OPENSANCTIONS_API_HOST` | Self-hosted OpenSanctions API host. If empty, uses public SaaS `https://api.opensanctions.org` |
| `SCREENING_OPENSANCTIONS_API_KEY` | API key for OpenSanctions SaaS |
| `SCREENING_OPENSANCTIONS_AUTH_METHOD` | `bearer` or `basic` (for self-hosted) |
| `SCREENING_OPENSANCTIONS_SCOPE` | Dataset scope override |
| `SCREENING_LEXISNEXIS_API_HOST` | LexisNexis provider host |
| `NAME_RECOGNITION_API_URL` | External name recognition service URL |
| `NAME_RECOGNITION_API_KEY` | Auth key for name recognition service |

#### Optional — observability

| Key | Description |
|-----|-------------|
| `SENTRY_DSN` | Sentry DSN for error tracking (backend and frontend) |
| `REQUEST_LOGGING_LEVEL` | Request log verbosity: `all`, `liveness`, or empty (disabled) |
| `ENABLE_TRACING` | Enable OpenTelemetry tracing: `true` or `false` |
| `TRACING_EXPORTER` | Tracing exporter: `otlp` or `gcp` |
| `ENABLE_PROMETHEUS` | Expose `/metrics` Prometheus endpoint: `true` or `false` |

#### Optional — AI agent

| Key | Description |
|-----|-------------|
| `AI_AGENT_MAIN_AGENT_KEY` | API key for the AI provider (OpenAI-compatible or AI Studio) |
| `AI_AGENT_MAIN_AGENT_URL` | AI provider API base URL |
| `AI_AGENT_MAIN_AGENT_DEFAULT_MODEL` | Default model name (default: `gemini-2.5-flash`) |
| `AI_AGENT_PERPLEXITY_API_KEY` | Perplexity API key |

#### Optional — Metabase embedding

| Key | Description |
|-----|-------------|
| `METABASE_SITE_URL` | Metabase instance URL |
| `METABASE_JWT_SIGNING_KEY` | HMAC key for Metabase embed tokens |
| `METABASE_TOKEN_LIFETIME_MINUTE` | Metabase embed token lifetime in minutes (default: `10`) |
| `METABASE_GLOBAL_DASHBOARD_ID` | Metabase global dashboard resource ID |

#### Optional — first-run seeding

| Key | Description |
|-----|-------------|
| `CREATE_GLOBAL_ADMIN_EMAIL` | Seed a global Marble admin on first startup |
| `CREATE_ORG_NAME` | Seed an initial organization on first startup |
| `CREATE_ORG_ADMIN_EMAIL` | Admin email for the seeded organization |

#### Optional — frontend (marble-frontend process)

The frontend Node.js process reads these from `envFrom` (same secret as the backend):

| Key | Default | Description |
|-----|---------|-------------|
| `SESSION_SECRET` | — | **Required.** Cryptographic secret for session cookie signing. Generate: `openssl rand -base64 48` |
| `SESSION_MAX_AGE` | `43200` | Session cookie max age in seconds (12h) |
| `DISABLE_SEGMENT` | `false` | Disable Segment analytics (shared key with backend) |

> **Note:** The frontend does NOT need `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, or `FIREBASE_AUTH_DOMAIN` as its own env vars. It receives all Firebase config from the backend `/config` endpoint at runtime.

#### Optional — debugging

| Key | Default | Description |
|-----|---------|-------------|
| `LOG_LEVEL` | — | Set to `debug` to log default env var usage at startup |
| `DEBUG_ENABLE_PROFILING` | — | Set to `1` to enable `/debug/pprof/*` endpoints |
| `DEBUG_PROFILING_MODE` | — | `gcp` or `http` profiling mode |
| `DEBUG_PROFILING_TOKEN` | — | Bearer token for HTTP profiling endpoint |
| `FIREBASE_AUTH_EMULATOR_HOST` | — | Firebase emulator host for local development (e.g. `localhost:9099`) |
| `CLOUD_RUN_PROBE_PORT` | — | Worker: port for Cloud Run health probe HTTP server |

---

### Generating secrets

**JWT signing key (RSA 4096):**

```bash
openssl genrsa -out jwt.pem 4096
base64 -i jwt.pem       # macOS
base64 -w 0 jwt.pem     # Linux
# Store the output as JWT_SIGNING_KEY_B64
```

**GCP service account JSON:**

1. Go to GCP Console → project `<your-firebase-project>` → IAM & Admin → Service Accounts
2. Locate the existing `firebase-adminsdk-*@<project>.iam.gserviceaccount.com` service account
3. Keys → Add Key → JSON → Download
4. Base64-encode it:
   ```bash
   base64 -i firebase-service-account.json       # macOS
   base64 -w 0 firebase-service-account.json     # Linux
   # Store the output as GCP_SERVICE_ACCOUNT_B64
   ```

The chart creates an ExternalSecret `<release>-firebase-sa` that decodes this value and mounts
`firebase.json` into every backend pod at `/secrets/firebase/firebase.json`.
`GOOGLE_APPLICATION_CREDENTIALS=/secrets/firebase/firebase.json` is injected automatically.

**Session secret:**

```bash
openssl rand -base64 48
# Store the output as SESSION_SECRET
```

**Screening indexer token:**

```bash
openssl rand -hex 32
# Store the output as SCREENING_INDEXER_TOKEN
```

---

### AWS Secrets Manager example

```bash
aws secretsmanager create-secret \
  --name marble-prod \
  --region us-east-2 \
  --secret-string '{
    "PORT": "8080",
    "ENV": "production",
    "APP_URL": "https://marble.example.com",
    "MARBLE_APP_URL": "https://marble.example.com",
    "PG_CONNECTION_STRING": "postgres://marble:pass@host:5432/marble_db?sslmode=require",
    "PG_MAX_POOL_SIZE": "40",
    "FIREBASE_API_KEY": "<web-api-key>",
    "FIREBASE_PROJECT_ID": "<project-id>",
    "GOOGLE_CLOUD_PROJECT": "<project-id>",
    "FIREBASE_AUTH_DOMAIN": "marble.example.com",
    "INGESTION_BUCKET_URL": "s3://marble-ingestion",
    "CASE_MANAGER_BUCKET_URL": "s3://marble-cases",
    "ANALYTICS_BUCKET_URL": "s3://marble-analytics",
    "SESSION_SECRET": "<openssl rand -base64 48>",
    "JWT_SIGNING_KEY_B64": "<base64-encoded RSA PEM>",
    "GCP_SERVICE_ACCOUNT_B64": "<base64-encoded GCP SA JSON>",
    "SCREENING_INDEXER_TOKEN": "<openssl rand -hex 32>",
    "LOGGING_FORMAT": "json",
    "DISABLE_SEGMENT": "true",
    "AUTHENTICATION_JWT_SIGNING_KEY_FILE": "/secrets/jwt.pem"
  }'
```

---

### Chart configuration for ESO

```yaml
marble:
  externalSecret:
    enabled: true
    clusterSecretStore: aws-secrets-manager   # ClusterSecretStore name in your cluster
    remoteSecretName: marble-prod             # Key name in the remote secret store
    refreshInterval: "1h"
    jwtSigningKeyProperty: "JWT_SIGNING_KEY_B64"   # Key holding the base64 PEM

  firebase:
    gcpServiceAccountProperty: "GCP_SERVICE_ACCOUNT_B64"  # Key holding the base64 SA JSON
    credentialsMountPath: "/secrets/firebase"
    credentialsKey: "firebase.json"
```

The chart creates three ExternalSecret resources:

1. **`<release>-secrets`** — extracts all keys via `dataFrom.extract`. Used as `envFrom` in api, worker, analytics, and migrations pods.
2. **`<release>-secrets-jwt`** — extracts `JWT_SIGNING_KEY_B64` with `decodingStrategy: Base64`, writes `jwt.pem`. Mounted at `/secrets/jwt.pem`. `AUTHENTICATION_JWT_SIGNING_KEY_FILE` injected automatically.
3. **`<release>-firebase-sa`** — extracts `GCP_SERVICE_ACCOUNT_B64` with `decodingStrategy: Base64`, writes `firebase.json`. Mounted at `/secrets/firebase/firebase.json`. `GOOGLE_APPLICATION_CREDENTIALS` injected automatically.

The `apiVersion` of all ExternalSecrets is auto-detected:
- `external-secrets.io/v1` — ESO ≥ 0.17.0 / v1.0.0 GA
- `external-secrets.io/v1beta1` — ESO < 0.17.0 (auto-fallback)

---

### Option B — Pre-existing Kubernetes Secrets

If ESO is not available, create the three Secrets manually before installing:

```bash
# Main secret
kubectl create secret generic marble-prod-secrets \
  --namespace marble \
  --from-env-file=marble.env   # file with KEY=VALUE lines

# JWT secret
kubectl create secret generic marble-prod-secrets-jwt \
  --namespace marble \
  --from-file=jwt.pem=./jwt.pem

# Firebase SA secret
kubectl create secret generic marble-prod-firebase-sa \
  --namespace marble \
  --from-file=firebase.json=./firebase-service-account.json
```

Configure the chart:

```yaml
marble:
  externalSecret:
    enabled: false
    jwtSigningKeyProperty: "JWT_SIGNING_KEY_B64"  # non-empty so volumes are mounted
  existingSecret:
    enabled: true

  firebase:
    credentialsSecretName: marble-prod-firebase-sa
    gcpServiceAccountProperty: ""  # disable ESO-managed SA secret
```

---

## Namespace

The chart creates the namespace defined in `namespace.name` when `namespace.create: true`.
All resources use this same namespace — it is the single source of truth via the
`marble.namespace` helper. When `namespace.create: false`, all resources use `.Release.Namespace`.

```yaml
namespace:
  create: true
  name: marble
```

---

## Ingress

```yaml
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  frontend:
    hostname: marble.example.com
    tls:
      enabled: false
  api:
    enabled: true
    hostname: api.marble.example.com
    tls:
      enabled: false
```

---

## Analytics

```yaml
analytics:
  enabled: true
```

`ANALYTICS_BUCKET_URL` must be set in the remote secret. The worker exports Parquet files to that
bucket; the analytics server reads them via DuckDB.

---

## Sanctions screening

Self-hosted stack (requires ECK Operator installed in the cluster):

```yaml
sanctions:
  enabled: true
  elasticsearch:
    version: "9.3.1"
    replicas: 1
    storage:
      storageClassName: gp3
      size: 30Gi
```

Add to the remote secret:
```
SCREENING_INDEXER_TOKEN=<shared token — same value in marble-backend and motiva>
```

Via OpenSanctions SaaS API (recommended — no Elasticsearch required):

```yaml
sanctions:
  enabled: true
  opensanctions:
    apiHost: "https://api.opensanctions.org"
```

Add to the remote secret:
```
SCREENING_OPENSANCTIONS_API_HOST=https://api.opensanctions.org
SCREENING_OPENSANCTIONS_API_KEY=<your-api-key>
```

---

## Values reference

See [values.yaml](values.yaml) for the full values reference with inline documentation.

## Integration guide

See [docs/integration-guide.md](docs/integration-guide.md) for REST API integration patterns,
webhook verification, and recommended error handling.

## Sources

- [Marble](https://github.com/checkmarble/marble)
- [Marble Backend](https://github.com/checkmarble/marble-backend)
- [Marble Frontend](https://github.com/checkmarble/marble-frontend)
- [Marble Documentation](https://docs.checkmarble.com)
