# Marble API Integration Guide

## Overview

Marble exposes a synchronous REST API for fraud detection and AML screening.
Your backend is the consumer — Marble never polls or connects to external databases directly.
All data flows are push-based via REST.

Two main integration flows:

1. **Real-time decision** — call before executing a transaction to get APPROVE/REVIEW/BLOCK/DECLINE
2. **Object ingestion** — call after the transaction to persist state for future aggregations and rule evaluation

## Base URL

```
In-cluster (recommended):  http://<release-name>-api.<namespace>.svc.cluster.local:8080
Via Ingress:                https://api.marble.example.com
```

---

## Authentication

All requests require an API key in the `Authorization` header:

```
Authorization: Bearer <api_key>
```

API keys are generated from the Marble console: **Settings → API keys**.

These are server-to-server credentials. Never expose them to frontend clients.

---

## Endpoints

### `POST /v1/decisions` — Synchronous decision

Call **before** executing a transaction. Returns a fraud decision immediately.

**Request:**
```json
{
  "scenario_id": "<scenario-uuid>",
  "trigger_object": {
    "object_id": "txn_abc123",
    "updated_at": "2026-05-25T10:00:00Z",
    "amount": 9999,
    "currency": "USD",
    "payment_method": "card"
  }
}
```

**Response 200:**
```json
{
  "id": "<decision_id>",
  "outcome": "APPROVE",
  "score": 25,
  "case_id": null,
  "rules_evaluated": [],
  "created_at": "2026-05-25T10:00:00Z"
}
```

**Outcome values:** `APPROVE` | `REVIEW` | `BLOCK_AND_REVIEW` | `DECLINE`

Reference: https://docs.checkmarble.com/reference/post_decisions

---

### `POST /v1/ingest/{table_name}` — Single object ingestion

Persist a single object. Uses UPSERT semantics keyed on `object_id`.

```
POST /v1/ingest/transactions
```

**Request:**
```json
{
  "object_id": "txn_abc123",
  "updated_at": "2026-05-25T10:00:00Z",
  "amount": 9999,
  "currency": "USD",
  "status": "completed"
}
```

**Response:** `200 OK` (no body)

---

### `POST /v1/ingest/{table_name}/batch` — Batch ingestion (up to 100 objects)

```
POST /v1/ingest/transactions/batch
```

**Request:** array of objects of the same type

```json
[
  { "object_id": "txn_001", "updated_at": "2026-05-25T10:00:00Z", "amount": 100 },
  { "object_id": "txn_002", "updated_at": "2026-05-25T10:01:00Z", "amount": 200 }
]
```

If any object is invalid the entire batch is rejected (all-or-nothing).

Reference: https://docs.checkmarble.com/docs/ingesting-data

---

### `POST /v1beta/decisions/async` — Asynchronous decision (optional)

For high-volume deferred processing. The result is delivered via webhook instead of the HTTP response.
Use this only when latency requirements allow for async processing.

---

## Recommended integration pattern

```
1. Receive payment request in your backend
2. POST /v1/decisions            → get outcome
3. if outcome == "DECLINE"       → reject transaction, return error to caller
4. if outcome == "REVIEW"        → proceed but flag for manual review or route to 3DS
5. if outcome == "APPROVE"       → execute transaction normally
6. POST /v1/ingest/transactions  → persist final transaction state
```

Recommended timeout for `POST /v1/decisions`: **3–5 seconds**.

---

## Data model — configuration prerequisite

Before ingesting objects, the data model for each table must be defined in the Marble console.

**Mandatory fields on every table:**
- `object_id` — string, unique identifier for the object
- `updated_at` — RFC 3339 timestamp

Additional fields (amount, currency, user_id, etc.) are defined per table in the console.
The console generates a dynamic OpenAPI spec that reflects your exact data model.

Reference: https://docs.checkmarble.com/docs/example-data-model

---

## Webhooks

Marble can notify your backend when platform events occur.

**Relevant events:**
- `decision.created` — a new decision was produced
- `case.updated` — a review case was updated
- `case.decisions_updated` — decisions within a case were modified

**Payload format:**
```json
{
  "type": "decision.created",
  "timestamp": "2026-05-25T10:00:00Z",
  "content": {
    "decision": { "id": "...", "outcome": "APPROVE", "score": 25 }
  }
}
```

**Signature verification (HMAC-SHA256):**

Header: `webhook-signature: t={unix_timestamp},v1={signature}`

Signed payload: `{timestamp},{raw_request_body}`

Validity window: 1 hour (replay attack protection).
Marble retries up to 24 times over ~10 days with exponential backoff.

Configuration: Marble console → **Settings → Webhooks** (requires admin role)

Reference: https://docs.checkmarble.com/docs/receiving-webhooks

---

## Error handling and fallback policy

| HTTP Status | Meaning | Recommended action |
|---|---|---|
| `200` | Success | Process normally |
| `400` | Invalid parameters | Log + alert (integration bug) |
| `401` | Invalid API key | Alert (rotate credential) |
| `422` | Unprocessable entity | Log + review data model config |
| `5xx` / timeout | Marble server error | **Fail-open: approve + flag for manual review** |

**On Marble unavailability, the recommended policy is fail-open** — never block transactions
due to fraud engine unavailability. Approve and queue for async review.

---

## References

| Resource | URL |
|---|---|
| Documentation | https://docs.checkmarble.com |
| REST API reference | https://docs.checkmarble.com/reference |
| Data ingestion | https://docs.checkmarble.com/docs/ingesting-data |
| Create a decision | https://docs.checkmarble.com/reference/post_decisions |
| Data model example | https://docs.checkmarble.com/docs/example-data-model |
| Technical configuration | https://docs.checkmarble.com/docs/technical-configuration |
| Receiving webhooks | https://docs.checkmarble.com/docs/receiving-webhooks |
| Configuring webhooks | https://docs.checkmarble.com/docs/setting-up-the-webhooks |
| Available events | https://docs.checkmarble.com/docs/available-events-and-webhooks-format |
| marble-backend GitHub | https://github.com/checkmarble/marble-backend |
