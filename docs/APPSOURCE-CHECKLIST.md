# AppSource submission checklist

## Extension (`apps/al-extension`)
- [ ] Unique GUID, publisher, AL object ID range (50100–50249 today).
- [ ] `runtime`, `platform`, `application` match the BC version family (26.0).
- [ ] Privacy statement URL, EULA URL, help URL resolve and are HTTPS.
- [ ] Logo PNG attached at the `logo` slot of `app.json`.
- [ ] At least one test codeunit per service codeunit (`WMS Receive Svc`, `WMS Pick Svc`, …).
- [ ] AL-Go for GitHub workflow green on `main`.
- [ ] AppSource validation pipeline run (Visual Studio Code AL: Package).

## Web app (`apps/web`)
- [ ] Production build clean (`pnpm -C apps/web build`).
- [ ] Lighthouse PWA score ≥ 90.
- [ ] No third-party trackers in the bundle.

## Mobile app (`apps/mobile`)
- [ ] iOS build through TestFlight; reviewer notes include test credentials.
- [ ] Android build signed with the Play Console keystore.
- [ ] App Store + Play Store listings reference Zebra / Honeywell compatibility.

## Marketing
- [ ] Screenshots: 6 per surface (login, menu, receive, pick, pack, dashboard).
- [ ] One-line value prop ≤ 100 chars.
- [ ] 30-second product video (optional but lifts conversion).
