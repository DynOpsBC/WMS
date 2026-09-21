# BADE production LP terminal UI validation — 2026-09-22

Passed on Android emulator with installed BADE release APK 1.14.154 (versionCode 200154), connected to sand0309 Sandbox and AL 1.14.1.67. No Production environment was accessed.

Company identity was verified through the sandbox companies API: internal name BS İlaç Kozmetik San.Tic.A.Ş. and display name BS GROUP İÇ VE DIŞ TİC. SAN. A.Ş. refer to the same company ID. The initial apparent company mismatch was a display-name difference, not a different environment.

## Completed through terminal screens

1. Opened synthetic PROD-PICK-TEST in Shipping / Picking. It was assigned to DYNOPS and read-only.
2. Pressed Bana Ata. The explicit takeover confirmation appeared. After confirmation, the BC owner changed to the authenticated terminal operator and the document became editable.
3. Selected the first source row, entered RAW through the scanner input, then PROD-LP-READY. Confirmed 10 PCS.
4. Selected the second source row, entered RAW2 then SECOND-PREP-LP. Confirmed 10 PCS.
5. Pressed LP Hazırla, entered staging bin STAGE and confirmed. The screen changed to the preparation state, showing both rows at STAGE with TARGET-PREP-LP and the Üretime Teslim Et action.
6. Independently called the read/assertion fixture action verifyPrepared: HTTP 204. Each source LP and source bin held 90, target LP/staging held 20, production quantity picked remained 0.
7. Revalidated STAGE and TARGET-PREP-LP on both rows. Pressed Üretime Teslim Et, entered PROD and confirmed.
8. The app returned to the document list and the completed test pick disappeared, without a persistent missing-document error.
9. Independently called verifyDelivered: HTTP 204. Target LP held 20 at PROD, assigned to the correct production order; production quantity picked = 20; stage = 0; both sources = 90.
10. Cleaned the synthetic fixture through the sandbox-only cleanup action: HTTP 204.

## Scope and limits

This covers the existing production pick → claim → source verification → consolidation into the test target LP → staging → target verification → delivery workflow in the actual release app. Source LPs, the target LP and production pick were deliberately precreated by the sandbox fixture. Creating a new target LP with the UI button was not part of this run. Barcode text was entered via emulator input; a physical scanner, printer/label output and simultaneous physical terminals were not tested. No label print job was sent. The separate six-round concurrent HTTP test covers competing requests and exactly-once stock outcomes.

No application source change or new APK/AL package was required by this run. Use AL 67 with APK 154. Local screenshots capture the prepared screen and final delivery confirmation; they are not publicly uploaded because the terminal screen includes operator/customer details.
