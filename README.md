# BCWMSApp

Hybrid Warehouse Management System for **Microsoft Dynamics 365 Business Central** (SaaS), targeting parity with the **Dynamics 365 Warehouse Management mobile app** and **Insight Works Warehouse Insight**.

## Apps

| Path | Stack | Purpose |
|---|---|---|
| `apps/al-extension` | AL (Business Central) | Custom tables, pages, codeunits, and v2.0 APIs published from BC. |
| `apps/web` | React + Vite + TypeScript + Tailwind (PWA) | Manager / supervisor UI: dashboards, exception queues, menu designer, setup. |
| `apps/mobile` | React Native (Expo) + TypeScript | Scanner-driven warehouse worker UI. Targets Zebra (TC-series) and Honeywell (CT45) via Datawedge/BLE. |
| `packages/shared` | TypeScript library | Generated BC OData types, API client, Zod validation, shared domain logic. |

## Targets

- BC: **SaaS** (Microsoft Entra ID, S2S OAuth).
- Localization at GA: English only.
- Carriers (M6 MVP): FedEx, UPS, USPS, DHL.
- Scanner hardware: Zebra Datawedge keyboard-wedge + BLE-paired Honeywell scanners.

## Status

Foundation scaffold (M0). See [`/root/.claude/plans/what-is-left-on-glistening-marble.md`](.) for the full roadmap (M0–M9).

## Local development

```bash
pnpm install
pnpm -C apps/web dev          # web PWA on http://localhost:5173
pnpm -C apps/mobile start     # Expo dev server
# AL extension: open apps/al-extension in VS Code with the AL extension installed
```
