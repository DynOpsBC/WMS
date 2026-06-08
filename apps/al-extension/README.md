# BCWMSApp — AL Extension

Business Central AL extension publishing custom tables, list/card pages, and **v1.0 custom APIs** under the `dynopsbc/wms` namespace, consumed by the BCWMSApp web PWA and React Native mobile app.

## Object ID range

`50100–50249` (per `app.json`).

## Custom APIs

All exposed at `https://api.businesscentral.dynamics.com/v2.0/{tenant}/{environment}/api/dynopsbc/wms/v1.0/companies({id})/...`:

| Entity set | Backing table | Page |
|---|---|---|
| `wmsWorkers` | `WMS Worker` | 50110 |
| `wmsLicensePlates` | `WMS License Plate` | 50111 |

(M1 will add `wmsWorkerMenus`, `wmsMenuItems`, `wmsLicensePlateLines`, plus extensions to the standard `Item`, `Location`, `Bin`, `Zone`.)

## Build

Open this folder in VS Code with the **AL Language** extension installed and target a Business Central SaaS sandbox.

```
Ctrl+Shift+P → AL: Publish
```

CI: see `.github/workflows/al.yml` (AL-Go for GitHub style).
