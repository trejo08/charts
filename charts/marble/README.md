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
helm install marble oci://ghcr.io/trejo08/charts/marble --version 0.1.8 \
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
| `MARBLE_APP_URL` | Public URL of the frontend app: `https://marble.example.com` |
| `FIREBASE_API_KEY` | Firebase Web API key (from Firebase Console → Project Settings → General → Your apps) |
| `FIREBASE_PROJECT_ID` | Firebase / GCP project ID |
| `GOOGLE_CLOUD_PROJECT` | GCP project ID (same value as `FIREBASE_PROJECT_ID` in most cases) |
| `FIREBASE_AUTH_DOMAIN` | Set to `<project-id>.firebaseapp.com` — **not** your custom app domain. Marble uses `signInWithPopup` which requires Firebase's own domain to load the auth iframe. Setting this to a custom domain will cause login to silently fail. |
| `INGESTION_BUCKET_URL` | Blob storage URL for data ingestion: `s3://marble-ingestion` |
| `CASE_MANAGER_BUCKET_URL` | Blob storage URL for case attachments: `s3://marble-cases` |
| `SESSION_SECRET` | Secure random string for frontend session cookie signing. Generate: `openssl rand -base64 48` |
| `JWT_SIGNING_KEY_B64` | RSA 4096 private key PEM **base64-encoded** — see generation instructions below |
| `GCP_SERVICE_ACCOUNT_B64` | GCP service account JSON **base64-encoded** — required for Firebase Admin SDK on non-GCP infra — see instructions below |

#### Recommended

| Key | Default | Description |
|-----|---------|-------------|
| `ANALYTICS_BUCKET_URL` | — | Blob storage URL for analytics Parquet exports: `s3://marble-analytics` |
| `LOGGING_FORMAT` | `text` | Log format: `json` (recommended for production) or `text` or `gcp` |
| `PG_MAX_POOL_SIZE` | `40` | PostgreSQL connection pool size |
| `DISABLE_SEGMENT` | `false` | Set to `true` to disable Segment analytics telemetry |
| `REQUEST_LOGGING_LEVEL` | `all` | HTTP request log verbosity: `all`, `liveness`, or empty (disabled) |
| `SCREENING_INDEXER_TOKEN` | auto-generated | Shared secret between marble-backend and sanctions indexer. Must be stable — if absent, a random UUID is generated per restart, breaking self-hosted sanctions. Generate: `openssl rand -hex 32` |

#### Optional — authentication (Firebase)

| Key | Default | Description |
|-----|---------|-------------|
| `AUTH_PROVIDER` | `firebase` | Authentication provider: `firebase` or `oidc` |
| `FIREBASE_AUTH_EMULATOR_HOST` | — | Firebase emulator host for local dev (e.g. `localhost:9099`) |

#### Optional — authentication (OIDC)

| Key | Description |
|-----|-------------|
| `AUTH_OIDC_ISSUER` | OIDC issuer URL |
| `AUTH_OIDC_CLIENT_ID` | OAuth client ID |
| `AUTH_OIDC_CLIENT_SECRET` | OAuth client secret |
| `AUTH_OIDC_SCOPE` | Comma-separated scopes (default: `openid,profile,email,offline_access`) |
| `AUTH_OIDC_ALLOWED_DOMAINS` | Comma-separated allowed email domains |
| `AUTH_OIDC_EXTRA_PARAMS` | URL-encoded extra params (e.g. `prompt=consent&access_type=offline`) |
| `AUTH_OIDC_EMAIL_CLAIM` | Override email claim (e.g. `upn` for Entra ID) |

#### Optional — JWT signing

| Key | Description |
|-----|-------------|
| `AUTHENTICATION_JWT_SIGNING_KEY` | Inline RSA PEM (not recommended in production — use file mount instead) |
| `AUTHENTICATION_JWT_SIGNING_KEY_FILE` | Path to JWT PEM file. The chart injects this automatically when `jwtSigningKeyProperty` is set (`/secrets/jwt.pem`) |
| `TOKEN_LIFETIME_MINUTE` | JWT token lifetime in minutes (default: `120`) |

#### Optional — database

| Key | Default | Description |
|-----|---------|-------------|
| `PG_SSL_MODE` | `prefer` | PostgreSQL SSL mode: `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full` |
| `PG_IMPERSONATE_ROLE` | — | Role to `SET ROLE` after connect (for IAM-auth RBAC) |
| `PG_DATABASE` | `marble` | Database name (when not using `PG_CONNECTION_STRING`) |
| `PG_HOSTNAME` | — | Database host (when not using `PG_CONNECTION_STRING`) |
| `PG_PORT` | `5432` | Database port (when not using `PG_CONNECTION_STRING`) |
| `PG_USER` | — | Database user (when not using `PG_CONNECTION_STRING`) |
| `PG_PASSWORD` | — | Database password (when not using `PG_CONNECTION_STRING`) |
| `CLIENT_DB_CONFIG_FILE` | — | Path to per-org database config JSON (enterprise multi-tenancy) |

#### Optional — Redis

| Key | Default | Description |
|-----|---------|-------------|
| `REDIS_HOST` | — | Redis address: `host:6379` |
| `REDIS_KEY` | — | Redis auth password |
| `REDIS_TLS` | `false` | Enable Redis TLS |
| `REDIS_TLS_SKIP_VERIFY` | `false` | Skip Redis TLS cert verification |
| `CACHE_ENABLED` | `false` | Enable Redis caching layer |

#### Optional — storage

| Key | Description |
|-----|-------------|
| `OFFLOADING_BUCKET_URL` | Blob storage URL for data offloading |
| `CONTINUOUS_SCREENING_BUCKET_URL` | Blob storage URL for continuous screening datasets |

#### Optional — application URLs

| Key | Default | Description |
|-----|---------|-------------|
| `MARBLE_API_URL` | — | Public URL of the backend API (returned to frontend via `/config`) |
| `MARBLE_API_INTERNAL_URL` | falls back to `MARBLE_API_URL` | Internal URL for server-to-server calls |
| `MARBLE_BACKOFFICE_URL` | — | URL of the Marble backoffice app |

#### Optional — timeouts (server)

| Key | Default | Description |
|-----|---------|-------------|
| `BATCH_TIMEOUT_SECOND` | `55` | Batch ingestion request timeout in seconds |
| `DECISION_TIMEOUT_SECOND` | `10` | Decision evaluation timeout in seconds |
| `DEFAULT_TIMEOUT_SECOND` | `5` | Default request timeout in seconds |
| `ANALYTICS_TIMEOUT` | `15s` | Analytics query timeout (Go duration string) |
| `BATCH_INGESTION_MAX_SIZE` | `0` (unlimited) | Max records per batch ingestion call |
| `WEBHOOK_IP_WHITELIST` | — | Comma-separated allowed webhook source IPs |

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
| `SIMILARITY_THRESHOLD` | model default | Fuzzy match threshold for screening (0–1 float) |
| `AI_CASE_REVIEW_TIMEOUT` | `5m` | Case review AI operation timeout |

#### Optional — analytics export (worker)

| Key | Default | Description |
|-----|---------|-------------|
| `DISABLE_ANALYTICS` | `false` | Disable analytics export even when bucket is configured |
| `ANALYTICS_JOB_INTERVAL` | `1h` | Analytics export job frequency |
| `ANALYTICS_BATCH_SIZE` | `10000` | Records per analytics export batch |
| `ANALYTICS_PROXY_API_URL` | auto | URL of analytics proxy API (auto-constructed from service name when `analytics.enabled=true`) |

#### Optional — webhooks (Convoy)

| Key | Default | Description |
|-----|---------|-------------|
| `CONVOY_API_KEY` | — | Convoy project API key |
| `CONVOY_API_URL` | — | Convoy API base URL |
| `CONVOY_PROJECT_ID` | — | Convoy project ID |
| `CONVOY_RATE_LIMIT` | `50` | Convoy delivery rate limit |

#### Optional — sanctions screening

| Key | Description |
|-----|-------------|
| `SCREENING_OPENSANCTIONS_API_HOST` | Self-hosted OpenSanctions API host. If empty, uses public SaaS `https://api.opensanctions.org` |
| `SCREENING_OPENSANCTIONS_API_KEY` | API key for OpenSanctions SaaS |
| `SCREENING_OPENSANCTIONS_AUTH_METHOD` | `bearer` or `basic` (for self-hosted) |
| `SCREENING_OPENSANCTIONS_SCOPE` | Dataset scope override |
| `SCREENING_LEXISNEXIS_API_HOST` | LexisNexis provider host |
| `SCREENING_LEXISNEXIS_TOKEN` | LexisNexis authentication token |
| `SCREENING_ALGORITHM` | Screening algorithm type selection |
| `NAME_RECOGNITION_API_URL` | External name recognition service URL |
| `NAME_RECOGNITION_API_KEY` | Auth key for name recognition service |

#### Optional — observability

| Key | Default | Description |
|-----|---------|-------------|
| `SENTRY_DSN` | — | Sentry DSN for error tracking (backend and frontend) |
| `ENABLE_TRACING` | `false` | Enable OpenTelemetry tracing |
| `TRACING_EXPORTER` | `otlp` | Tracing exporter: `otlp` or `gcp` |
| `TRACING_SAMPLING_RATES` | — | Trace sampling configuration |
| `ENABLE_PROMETHEUS` | `false` | Expose `/metrics` Prometheus endpoint |

#### Optional — AI agent

| Key | Default | Description |
|-----|---------|-------------|
| `AI_AGENT_MAIN_AGENT_PROVIDER_TYPE` | `openai` | AI provider type |
| `AI_AGENT_MAIN_AGENT_KEY` | — | API key for the AI provider (OpenAI-compatible or AI Studio) |
| `AI_AGENT_MAIN_AGENT_URL` | — | AI provider API base URL |
| `AI_AGENT_MAIN_AGENT_DEFAULT_MODEL` | `gemini-2.5-flash` | Default model name |
| `AI_AGENT_MAIN_AGENT_BACKEND` | — | AI agent backend service |
| `AI_AGENT_MAIN_AGENT_PROJECT` | falls back to `GOOGLE_CLOUD_PROJECT` | AI agent GCP project |
| `AI_AGENT_MAIN_AGENT_LOCATION` | — | AI agent region/location |
| `AI_AGENT_PERPLEXITY_API_KEY` | — | Perplexity API key |

#### Optional — Metabase embedding

| Key | Default | Description |
|-----|---------|-------------|
| `METABASE_SITE_URL` | — | Metabase instance URL |
| `METABASE_JWT_SIGNING_KEY` | — | HMAC key for Metabase embed tokens |
| `METABASE_TOKEN_LIFETIME_MINUTE` | `10` | Metabase embed token lifetime in minutes |
| `METABASE_GLOBAL_DASHBOARD_ID` | — | Metabase global dashboard resource ID |

#### Optional — billing (Lago)

| Key | Description |
|-----|-------------|
| `LAGO_BASE_URL` | Lago billing service base URL |
| `LAGO_API_KEY` | Lago API authentication key |

#### Optional — licensing

| Key | Default | Description |
|-----|---------|-------------|
| `LICENSE_KEY` | — | Marble license key for premium features (SSO, advanced screening) |
| `KILL_IF_READ_LICENSE_ERROR` | `false` | Terminate on license read failure |

#### Optional — BigQuery metrics

| Key | Default | Description |
|-----|---------|-------------|
| `BIGQUERY_PROJECT_ID` | falls back to `GOOGLE_CLOUD_PROJECT` | BigQuery GCP project ID |
| `BIGQUERY_METRICS_DATASET` | default constant | BigQuery metrics dataset name |
| `BIGQUERY_METRICS_TABLE` | default constant | BigQuery metrics table name |

#### Optional — first-run seeding

| Key | Description |
|-----|-------------|
| `CREATE_GLOBAL_ADMIN_EMAIL` | Seeds a global Marble admin (`MARBLE_ADMIN` role) — platform-wide superuser |
| `CREATE_ORG_NAME` | Seeds an initial organization |
| `CREATE_ORG_ADMIN_EMAIL` | Seeds an org admin (`ADMIN` role) scoped to the seeded organization |

> **Critical — order of operations for first deploy:**
> 1. Create the admin user in **Firebase Console → Authentication → Users** first, before the migrations Job runs.
> 2. Add `CREATE_GLOBAL_ADMIN_EMAIL`, `CREATE_ORG_NAME`, and `CREATE_ORG_ADMIN_EMAIL` to the remote secret. Both seeding vars should use the same email if you want one user with full access.
> 3. Deploy the chart — the migrations Job runs and seeds the org and admin user, linking them to the existing Firebase user.
>
> If the Firebase user does not exist when the seeder runs, the Marble user record is created without a Firebase UID and login will silently fail even though `POST /token` returns 200. The user will appear in the UI with role `UNKNOWN`. To recover: drop the database and redeploy following the correct order.

#### Optional — frontend (marble-frontend process)

The frontend Node.js process reads these from `envFrom` (same secret as the backend):

| Key | Default | Description |
|-----|---------|-------------|
| `SESSION_SECRET` | **Required** | Cryptographic secret for session cookie signing. Generate: `openssl rand -base64 48` |
| `SESSION_MAX_AGE` | `43200` | Session cookie max age in seconds (12h) |
| `DISABLE_SEGMENT` | `false` | Disable Segment analytics (shared key with backend) |
| `APP_VERSION` | — | Application version string displayed in the UI |
| `SENTRY_DSN` | — | Sentry DSN (frontend uses same key as backend) |
| `SENTRY_ENVIRONMENT` | — | Environment label for Sentry |
| `METABASE_URL` | — | Metabase analytics dashboard URL |
| `CUSTOM_LOGO_URL` | — | Custom logo URL for white-labeling |

> **Note:** The frontend does NOT need `FIREBASE_API_KEY`, `FIREBASE_PROJECT_ID`, or `FIREBASE_AUTH_DOMAIN` as its own env vars. It receives all Firebase config from the backend `/config` endpoint at runtime.

#### Optional — debugging

| Key | Default | Description |
|-----|---------|-------------|
| `DEBUG_ENABLE_PROFILING` | `0` | Set to `1` to enable `/debug/pprof/*` endpoints |
| `DEBUG_PROFILING_MODE` | — | `gcp` or `http` profiling mode |
| `DEBUG_PROFILING_TOKEN` | — | Bearer token for HTTP profiling endpoint |
| `FIREBASE_AUTH_EMULATOR_HOST` | — | Firebase emulator host for local development (e.g. `localhost:9099`) |
| `CLOUD_RUN_PROBE_PORT` | — | Worker: port for Cloud Run health probe HTTP server |
| `ENABLE_WORKER_ONESHOT` | — | Set to `1` to enable development-only worker flags |

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
