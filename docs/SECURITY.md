# Security review checklist — BCWMSApp

Run before each AppSource release.

## Auth & identity
- [ ] Web PWA uses MSAL with PKCE; access token requested with `https://api.businesscentral.dynamics.com/.default` scope only.
- [ ] Mobile uses `expo-auth-session` PKCE; `redirectUri` matches the Entra ID app registration.
- [ ] No client secret embedded in either app binary; service-to-service tokens stay on the BC side.
- [ ] All BC custom API calls authenticated; anonymous endpoints disabled.
- [ ] Token cache: web → `sessionStorage`; mobile → MMKV protected via OS keystore (Keychain / Keystore).

## Network
- [ ] HTTPS only. TLS 1.2 minimum, prefer 1.3.
- [ ] Domain pinning considered for mobile (optional).
- [ ] CSP headers on web dist: `default-src 'self'; connect-src 'self' https://*.businesscentral.dynamics.com https://login.microsoftonline.com`.
- [ ] CORS on BC custom APIs: allow only the PWA origin.

## Data
- [ ] No PII in telemetry payloads — strip usernames, replace with Entra `oid`.
- [ ] Offline queue stored encrypted at rest (MMKV `encryptionKey`).
- [ ] Carrier API keys stored in BC's Isolated Storage; never in app.json.
- [ ] Print template strings sanitized (ZPL injection guard on `^FD` payloads).

## Code
- [ ] `pnpm audit` clean.
- [ ] AL extension passes `Microsoft.Dynamics.Nav.AppCheckPipeline.Tests`.
- [ ] No `eval`, no `dangerouslySetInnerHTML`.
- [ ] All API surface area covered by Zod schemas at the boundary (`packages/shared/src/validation/`).

## Privilege
- [ ] BC permission set "WMS" reviewed by a partner admin; non-mutating reads should not require RIMD.
- [ ] Worker role grants only the necessary tables.

## Pen test
- [ ] One full pen-test cycle on web + mobile + BC APIs prior to GA.
- [ ] Burp/ZAP scan of API surface area.

## AppSource specifics
- [ ] Translations files complete for the supported locales (English-only at GA).
- [ ] Privacy policy + EULA URLs in `app.json` resolve.
- [ ] Telemetry opt-in disclosed.
