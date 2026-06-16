# Self-Hosted Print Bridge — Setup Guide

End-to-end setup of the BCWMSApp print bridge: register a printer in Business
Central, generate an agent token, deploy `bcwms-print-agent` to the workstation
that owns the printer, and verify a label prints from the web/mobile app.

> Architecture: BC Print Job Queue → Azure Function `print-relay` → local
> `bcwms-print-agent` → native OS printer. Direct BC SaaS → printer is not
> possible; the agent pulls jobs via HTTPS and signs every request with a
> per-printer HMAC secret.

## 1. Configure BC

1. Open **Advanced WMS Setup**.
2. Set **Print Channel** = `Self-Hosted (Local Agent)`.
3. Set **Print Relay URL** to the deployed Azure Function host (e.g.
   `https://bcwms-relay.azurewebsites.net`).
4. Open **Printers** (action on the role center or Setup card) → **+ New**
   - Code: short identifier (`WH-LP1`)
   - Description: human-readable
   - Format: `ZPL` for Zebra label printers
   - Printer Handle: OS printer name (macOS/Linux) or `host[:port]` (Windows)
   - Active: ✓
5. Click **Generate Token** → copy the value shown once. Only the SHA-256
   hash is stored on the BC side; rotation invalidates older tokens.

## 2. Deploy the Azure Function

```bash
cd push-relay
pnpm install
pnpm build
func azure functionapp publish bcwms-relay
```

Required app settings (KeyVault refs recommended):

| key | value |
|-----|-------|
| `PRINT_TENANT_CONFIG_JSON` | JSON map `{ "tenants": { "default": { "bcBaseUrl": "https://api.businesscentral.dynamics.com/v2.0/<aad>/<env>", "bcCompanyId": "<guid>", "bcBearer": "<service-account-token>", "printerSecrets": { "WH-LP1": "<plain-token-from-bc>" } } } }` |

`bcBearer` is the access token used by the relay to call BC OData. Use an
S2S app registration with `Automation.ReadWrite.All` or a dedicated service
account with the `DOPSWHS-ADMIN` permission set.

## 3. Deploy the Local Agent

Cross-compile on a dev machine:

```bash
cd print-agent
GOOS=darwin  GOARCH=arm64 go build -o build/agent-mac-arm64 .
GOOS=linux   GOARCH=amd64 go build -o build/agent-linux-amd64 .
GOOS=windows GOARCH=amd64 go build -o build/agent.exe .
```

Drop the binary on the workstation that owns the printer and write
`~/.bcwms-print-agent/config.json` (or `/etc/bcwms-print-agent/config.json`
for a service install):

```json
{
  "relayUrl": "https://bcwms-relay.azurewebsites.net",
  "tenantId": "default",
  "printerId": "WH-LP1",
  "secret": "<token from BC>",
  "printerHandle": "ZDesigner-GK420t",
  "format": "ZPL",
  "pollIntervalSec": 5
}
```

`printerHandle` resolution:
- macOS/Linux: `lpstat -p` lists CUPS printers — use the queue name.
- Windows: `host[:port]` of the network printer (raw TCP 9100). For local
  spooler integration see `print-agent/README.md`.

Install as a service: see `print-agent/README.md` (NSSM / launchd /
systemd templates).

## 4. Smoke Test

1. From the BC Printer Card click **Test Print** — a self-test ZPL job is
   queued.
2. Within `pollIntervalSec` the agent logs `job N printed (... bytes)`.
3. The label should physically print. Status in BC → **Print Job Log**
   moves to `Sent`.
4. From the web app: open **Yazıcılar**, mark `WH-LP1` as Default, then open
   any LP detail and click **🖨 Print Label** — same flow.
5. From the mobile app: open **Yazıcılar**, mark default, print an LP from
   the LP detail screen.

## 5. Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| `list jobs status=401` agent log | Token rotated on BC side or wrong tenant | Re-issue token, update `secret` in config |
| Status stays `Queued` indefinitely | Agent not running, wrong `printerId`, or job in `BCNative` channel | Check Print Channel = Self-Hosted on Setup; confirm agent log shows tick |
| Status `Failed` with `lp failed: ...` | Wrong `printerHandle` or printer offline | `lpstat -p` to verify, re-test |
| Status `Failed` with `dial X:9100` | Network printer unreachable from agent host | Validate firewall + IP |
| HTTP 502 from relay | BC OData rejected (expired bearer / permission) | Refresh `bcBearer` env var, ensure DOPSWHS-ADMIN |

## 6. Multi-Printer Layout

Each printer is a distinct registry row with its own token. One agent per
host is the default; one agent can serve multiple printers if you create
one config + agent process per printer (no shared state).

## 7. Cost

- Azure Function consumption plan: typically <$1/month at warehouse-scale
  poll rates (12 polls/min/agent ≈ 17k req/day).
- KeyVault: ~$0.03 / secret / month.
- No PrintNode subscription.
