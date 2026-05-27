# Changelog

All notable changes to this repository's charts will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Charts follow [Semantic Versioning](https://semver.org/).

---

## marble

### [0.1.5] - 2026-05-26

#### Fixed

- Both ExternalSecrets (`<release>-secrets` and `<release>-secrets-jwt`) now have
  `pre-install,pre-upgrade` hook annotations with weight `-10` and
  `hook-delete-policy: before-hook-creation`. This ensures ESO creates both K8s Secrets before
  the migrations Job (weight `-5`) attempts to mount them.

---

### [0.1.4] - 2026-05-26

#### Fixed

- Removed unnecessary `initContainer` (`wait-for-secret`) from the migrations Job. The correct
  ordering is handled by Helm hook weights: ServiceAccount (-15), ExternalSecret (-10),
  migrations Job (-5).

---

### [0.1.3] - 2026-05-26

#### Changed

- `marble.jwtMountPath` helper gate logic clarified: `jwtSigningKeyProperty` only needs to be
  declared when the key name in the remote secret differs from the default `JWT_SIGNING_KEY_B64`.
  In the standard case the default covers it and no override is needed in values.
- `AUTHENTICATION_JWT_SIGNING_KEY_FILE` injected via `env[]` only when `jwtSigningKeyProperty`
  is non-empty. If the env var is also present in the remote secret it arrives via `envFrom` —
  `env[]` takes precedence, ensuring the chart-controlled mount path always wins.
- Secret management validation (`marble.validateSecrets`) now fails at render time with a clear
  message if neither `externalSecret` nor `existingSecret` is configured, or if required ESO
  fields (`clusterSecretStore`, `remoteSecretName`) are missing.
- ArtifactHub support: added `artifacthub-repo.yml`, `LICENSE`, chart annotations
  (`artifacthub.io/license`, `category`, `links`, `images`, `changes`), and workflow step to
  publish `artifacthub-repo.yml` to `gh-pages` on every release.

---

### [0.1.2] - 2026-05-26

#### Added

- `marble.externalSecret.jwtSigningKeyProperty` (default: `JWT_SIGNING_KEY_B64`) — configures the
  key name in the remote secret that holds the RSA private key PEM encoded in base64.
- Second `ExternalSecret` resource (`<release>-secrets-jwt`) rendered when
  `jwtSigningKeyProperty` is non-empty. Uses `decodingStrategy: Base64` to decode the PEM and
  writes it as `jwt.pem` into a dedicated Kubernetes Secret, keeping it separate from the main
  env-var secret to avoid JSON encoding issues with multi-line values.
- `marble.jwtMountPath` helper — auto-constructs the container mount path (`/secrets/jwt.pem`)
  from `jwtSigningKeyProperty` without requiring manual `marble.auth.jwtSigningKeyFile` config.
- `AUTHENTICATION_JWT_SIGNING_KEY_FILE` is now injected automatically when the JWT ExternalSecret
  is active, pointing to the mounted PEM file path.

#### Fixed

- Storing the RSA private key PEM directly as a multi-line JSON string value in AWS Secrets
  Manager caused `invalid character '\n' in string literal` — the `ExternalSecret` failed with
  `could not get secret data from provider`, blocking the entire sync. The new design stores the
  PEM base64-encoded under a separate key and decodes it at the ESO layer.

#### Changed

- `marble.backendVolumes` and `marble.backendVolumeMounts` now reference `<release>-secrets-jwt`
  (with key `jwt.pem`) instead of the main secret. The volume is mounted whenever
  `jwtSigningKeyProperty` is non-empty.
- `marble.auth.jwtSigningKeyFile` is now an override — when left empty, the path is
  auto-derived from `jwtSigningKeyProperty`. Explicit value still takes precedence.

---

### [0.1.1] - 2026-05-26

#### Fixed

- `ExternalSecret` now runs as a `pre-install`/`pre-upgrade` hook (weight `-10`) so ESO creates the
  Kubernetes Secret from AWS Secrets Manager **before** the migrations Job attempts to connect to
  PostgreSQL. Previously the migrations Job failed with `activeDeadlineSeconds` exceeded because the
  Secret did not exist yet at hook execution time.
- `ServiceAccount` now runs as a `pre-install`/`pre-upgrade` hook (weight `-15`) so it exists before
  the `ExternalSecret` (weight `-10`) and migrations Job (weight `-5`) run. Previously the migrations
  pod could not be scheduled because the ServiceAccount was not yet created.

---

### [0.1.0] - 2026-05-26

#### Added

- Initial release.
- `API` deployment (`--server`) with liveness (`/liveness`) and readiness (`/health`) probes, HPA.
- `Worker` deployment (`--worker`) for async River job queue over PostgreSQL.
- `Analytics` deployment (`--analytics`) — optional DuckDB analytics proxy.
- `Frontend` deployment with readiness probe (`/healthcheck`), HPA.
- `Migrations` Job as `pre-install`/`pre-upgrade` Helm hook.
- `ServiceAccount` with support for IRSA annotations (AWS EKS).
- `ExternalSecret` with automatic `apiVersion` detection (`external-secrets.io/v1` vs `v1beta1`).
- `Ingress` for frontend and API with configurable class and annotations (nginx, ALB, Traefik).
- Sanctions stack (`sanctions.enabled`) — Elasticsearch via ECK Operator, Yente CronJob, Motiva.
- HPA for API and frontend deployments.
- Support for Firebase Auth, OIDC, blob storage (S3/GCS/Azure/MinIO), offloading, and client DB config.
