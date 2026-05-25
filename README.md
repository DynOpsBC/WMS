# BCWMSApp

Advanced Warehouse Management System for Microsoft Dynamics 365 Business Central SaaS.

This monorepo contains:

- `al/` - Business Central AL extension, publisher `DynOps`, prefix `DOPSWHS`.
- `android/` - Kotlin/Jetpack Compose handheld application.
- `web/` - React/Vite workstation SPA bundled into AL control add-in resources.
- `push-relay/` - Azure Functions relay for BC webhooks, SignalR, and FCM.

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

