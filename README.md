# BCWMSApp

[![Release](https://img.shields.io/github/v/release/DynOpsBC/WMS?label=latest&color=6c5ce7)](https://github.com/DynOpsBC/WMS/releases/latest)
[![License Tier](https://img.shields.io/badge/license-Essentials%20%E2%80%A2%20Advanced%20%E2%80%A2%20Enterprise-6c5ce7)](docs/license-protocol.md)
[![BC Platform](https://img.shields.io/badge/Business%20Central-24.0%2B-026CC5)](docs/install-pte.md)
[![Customer Portal](https://img.shields.io/badge/portal-bcwms.dynops.com-success)](https://portal.bcwms.dynops.com)

Advanced Warehouse Management System for Microsoft Dynamics 365 Business Central SaaS.

> **Müşteri kurulumu için:** [docs/install-pte.md](docs/install-pte.md) (PTE upload + lisans key + ilk demo) · **Sürüm güncellemeleri:** [docs/update-flow.md](docs/update-flow.md) · **Lisans + JWT protokolü:** [docs/license-protocol.md](docs/license-protocol.md) · **v1.10.0 yol haritası:** [docs/release-roadmap.md](docs/release-roadmap.md)
>
> **📱 Android telefona kurulum:** [releases/android/bcwms-1.10.0-debug.apk](releases/android/bcwms-1.10.0-debug.apk) (32 MB) · sideload rehberi [docs/android-install-guide.md](docs/android-install-guide.md) · [CHANGELOG](releases/android/CHANGELOG.md)

This monorepo contains:

- `al/` — Business Central AL extension, publisher `DynOps`, prefix `DOPSWHS`.
- `android/` — Kotlin/Jetpack Compose handheld application + Play Closed Track + APK in-app update.
- `web/` — React/Vite workstation SPA. Two build modes: AL ControlAddIn (default) and SaaS bundle (`BCWMS_TARGET=saas`) with Service Worker auto-update.
- `push-relay/` — Azure Functions relay for BC webhooks, SignalR, and FCM.
- `print-agent/` — Cross-platform Go binary for the self-hosted print bridge (BC → relay → local printer).
- `licensing-service/` — RS256 JWT issuer/verifier Azure Function (KeyVault-backed).
- `customer-portal/` — Vite + MSAL SaaS portal for license + version management.

## Quickstart

Prerequisites vary by artifact:

- AL extension: Business Central AL extension tooling on Windows for packaging/publish.
- Android: JDK 17 and Android SDK for Gradle builds.
- Web and push relay: Node.js 20 and pnpm.

Useful commands once prerequisites are available:

```bash
cd web && pnpm install && pnpm typecheck && pnpm build
cd push-relay && pnpm install && pnpm build
cd android && ./gradlew lintDebug testDebugUnitTest assembleDebug
```

AL packaging and sandbox publish are intentionally not run from this macOS scaffold. Use the sandbox defined in `al/.vscode/launch.json`.

