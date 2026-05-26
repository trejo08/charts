# Changelog

All notable changes to this repository's charts will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Charts follow [Semantic Versioning](https://semver.org/).

---

## marble

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
