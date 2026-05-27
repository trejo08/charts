# trejo08/charts

Helm charts maintained by [Juan Trejo](https://github.com/trejo08).

## Usage

```bash
helm repo add trejo08 https://trejo08.github.io/charts
helm repo update
```

## Available charts

| Chart | Description | Version | App Version |
|-------|-------------|---------|-------------|
| [marble](charts/marble/) | Kubernetes deployment for [Marble](https://www.checkmarble.com) — open-source fraud detection and AML platform | 0.1.3 | 1.1.0 |

## Install a chart

```bash
# Classic Helm repo
helm install marble trejo08/marble

# OCI registry
helm install marble oci://ghcr.io/trejo08/charts/marble --version 0.1.3
```

## marble

Covers the full Marble stack:

- **API** (`--server`) — REST API for decisions and data ingestion
- **Worker** (`--worker`) — async job queue (River/PostgreSQL)
- **Analytics** (`--analytics`) — DuckDB analytics proxy (optional)
- **Migrations** (`--migrations`) — schema migrations as a pre-install/upgrade Helm hook
- **Frontend** — Marble web console
- **HPA** — horizontal pod autoscaling for API and frontend
- **Ingress** — configurable for nginx, ALB, Traefik
- **ExternalSecret** — automatic ESO integration with cluster-version auto-detection
- **Sanctions stack** — optional self-hosted Elasticsearch (ECK) + Yente + Motiva

See [charts/marble/README.md](charts/marble/README.md) for full documentation and values reference.

## Prerequisites

Charts in this repository may require the following operators in your cluster:

| Operator | Required by | Notes |
|----------|-------------|-------|
| [External Secrets Operator](https://external-secrets.io) | `marble` (optional) | Enables automatic secret sync from AWS Secrets Manager, Vault, etc. |
| [Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/guide/en/cloud-on-k8s/) | `marble` sanctions stack | Only needed if `sanctions.enabled: true` |

## License

MIT
