# bcwms-print-agent

Cross-platform print agent for BCWMSApp (Business Central → local network printers).

The agent polls the `print-relay` Azure Function on a fixed interval, claims
queued jobs for its configured printer, sends raw ZPL/PDF/ESC-POS payloads to
the local printer, and reports `Sent` / `Failed` status back to Business
Central via the same relay.

## Build

Requires Go 1.22+.

```bash
cd print-agent
go build -o bcwms-print-agent .
```

Cross-compile:

```bash
GOOS=windows GOARCH=amd64 go build -o build/bcwms-print-agent.exe .
GOOS=darwin  GOARCH=arm64 go build -o build/bcwms-print-agent-darwin-arm64 .
GOOS=linux   GOARCH=amd64 go build -o build/bcwms-print-agent-linux-amd64 .
```

## Config

`~/.bcwms-print-agent/config.json`:

```json
{
  "relayUrl": "https://bcwms-relay.azurewebsites.net",
  "tenantId": "default",
  "printerId": "WH-LP1",
  "secret": "abc123...64-char-hex-from-bc",
  "printerHandle": "ZDesigner-GK420t",
  "format": "ZPL",
  "pollIntervalSec": 5,
  "agentId": "agent-floor-1"
}
```

`printerHandle`:
- **macOS/Linux**: the CUPS printer name (`lpstat -p` to list).
- **Windows**: `host[:port]` of a network printer reachable via raw TCP
  (default port 9100). For local Win32 spooler integration extend
  `printer/backend_windows.go` to use the `golang.org/x/sys/windows`
  `OpenPrinter` / `StartDocPrinter` API and the
  `github.com/alexbrainman/printer` package (not vendored to keep the binary
  dependency-free in v1).

`secret`: generated from BC → **Printer List → Generate Token**. Plain value
is shown once; only the SHA-256 hash is stored on the BC side. Rotate via the
same action; old tokens become invalid immediately.

## Run

```bash
./bcwms-print-agent --config ~/.bcwms-print-agent/config.json
```

## Service installation

### Windows (NSSM)

```powershell
nssm install BcwmsPrintAgent "C:\Program Files\BcwmsPrintAgent\bcwms-print-agent.exe" --config "C:\ProgramData\BcwmsPrintAgent\config.json"
nssm start BcwmsPrintAgent
```

### macOS (launchd)

`/Library/LaunchDaemons/com.dynops.bcwms.print-agent.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.dynops.bcwms.print-agent</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/bcwms-print-agent</string>
    <string>--config</string>
    <string>/Library/Application Support/BcwmsPrintAgent/config.json</string>
  </array>
  <key>KeepAlive</key><true/>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
```

```bash
sudo launchctl bootstrap system /Library/LaunchDaemons/com.dynops.bcwms.print-agent.plist
```

### Linux (systemd)

`/etc/systemd/system/bcwms-print-agent.service`:

```ini
[Unit]
Description=BCWMSApp Print Agent
After=network.target

[Service]
ExecStart=/usr/local/bin/bcwms-print-agent --config /etc/bcwms-print-agent/config.json
Restart=always
User=bcwms

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now bcwms-print-agent
```

## Protocol

See `docs/print-bridge-protocol.md` (relay HTTP API, HMAC signing scheme).
