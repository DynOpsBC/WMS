# Self-Hosted Print Bridge — HTTP Protocol

The bridge has three HTTP endpoints exposed by the `push-relay` Azure
Function. The local agent (`bcwms-print-agent`) is the only client.

## Auth

Every request from the agent carries three headers:

| Header | Value |
|---|---|
| `X-Bcwms-Printer-Id` | printer code registered in BC (`WH-LP1`) |
| `X-Bcwms-Timestamp` | unix epoch seconds (server tolerates ±5 minutes) |
| `X-Bcwms-Signature` | hex `HMAC-SHA256(secret, "<ts>.<body>")` |

`secret` is the per-printer token issued by BC (Printer Card → Generate
Token). The plain value is shown once at generation; only its SHA-256 hash
is stored server-side (table `DOPSWHS Printer.Token Hash`). Body is the
raw request body — empty string for GET.

Signature must use lowercase hex. The relay rejects with `401 invalid
signature` on mismatch or clock skew >300s.

## Endpoints

### `GET /api/print-jobs?printer=<code>&tenant=<id>&top=<n>`

Returns up to `n` (default 10) jobs in `Queued` status for the given
printer.

```json
{
  "ok": true,
  "jobs": [
    {
      "jobId": 1234,
      "sourceDoc": "LP000001",
      "printerId": "WH-LP1",
      "channel": "SelfHosted",
      "format": "ZPL",
      "status": "Queued",
      "copies": 1,
      "payload": "XlhBXkZPNTAsNTBeQTBOLDQwLDQwXkZE...",
      "payloadSize": 138,
      "createdAt": "2026-06-15T13:42:11Z"
    }
  ]
}
```

`payload` is base64. The agent must `base64.decode()` before sending bytes
to the printer.

### `POST /api/print-jobs/{jobId}/claim?printer=<code>&tenant=<id>`

Body: `{ "agentId": "agent-floor-1" }`

Marks the job as claimed by this agent. Idempotent: a second claim by the
same agent returns 200; a claim of a job already claimed by someone else
returns 409.

### `POST /api/print-jobs/{jobId}/status?printer=<code>&tenant=<id>`

Body: `{ "status": "Sent" | "Failed", "message": "free text up to 250 chars" }`

On success the BC job moves to `Sent`/`Failed`, a `Print Job Log` entry is
appended (with the message), and on failure `Retry Count` is incremented
and `Last Error` is stored.

## Flow

```
agent.tick()
  ├─ GET /print-jobs?printer=…           → list
  ├─ for each job:
  │   ├─ POST /print-jobs/{id}/claim
  │   ├─ base64-decode(payload)
  │   ├─ printer.Print(format, bytes, copies)
  │   ├─ on success → POST /print-jobs/{id}/status { status: "Sent" }
  │   └─ on error   → POST /print-jobs/{id}/status { status: "Failed", message }
  └─ sleep(pollIntervalSec)
```

## BC OData (server-side, called by relay only)

The relay translates between the agent endpoints above and BC OData
actions on `printJobs` (page 72299) / `printers` (page 72289):

| Agent action | BC OData |
|---|---|
| GET list | `GET /api/dynops/warehouse/v2.0/companies({id})/printJobs?$filter=channel eq 'SelfHosted' and status eq 'Queued' and printerId eq '{code}'` |
| Claim | `POST /printJobs({jobId})/Microsoft.NAV.claim` body `{ "agentId": ... }` |
| Status Sent | `POST /printJobs({jobId})/Microsoft.NAV.markSuccess` body `{ "message": ... }` |
| Status Failed | `POST /printJobs({jobId})/Microsoft.NAV.markFailure` body `{ "message": ... }` |

The relay never exposes BC tokens to the agent.

## Tenant Config

`PRINT_TENANT_CONFIG_JSON` app setting:

```json
{
  "defaultTenant": "default",
  "tenants": {
    "default": {
      "bcBaseUrl": "https://api.businesscentral.dynamics.com/v2.0/<aad>/<env>",
      "bcCompanyId": "<guid>",
      "bcBearer": "<service-token>",
      "printerSecrets": {
        "WH-LP1": "<plain-secret>",
        "WH-LP2": "<plain-secret>"
      }
    }
  }
}
```

The relay never persists secrets to disk; KeyVault → app settings
recommended.

## Versioning

Protocol headers and route names are stable from v1.9.0.0. New optional
fields may be added to the JSON contracts; agents MUST tolerate unknown
keys.
