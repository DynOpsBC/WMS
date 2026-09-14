# BADE feedback changes — 14 September 2026

Status: draft implementation; not approved for production deployment.

## Behavior changes

- Picking and warehouse picking use a common pallet verification sheet for BADE. Wrapped cards expose source bin, pallet, lot and quantity.
- BADE requires scanner/camera input for mandatory pallet fields. Missing configuration or unavailable capabilities do not disable verification.
- Multi-pallet picking shows the quantity required from each pallet, enforces scan order and rechecks the stock plan before confirmation and registration. Previously staged rows are included in the allocation plan; shared pallets are scanned once per group.
- Put-away verifies the LP rather than requiring a separate product barcode.
- Warehouse Entries current LP summaries and drill-downs now match the entry lot and serial, including exact blank tracking. Bin Contents remains an aggregate across lots. Nonpositive LP quantities are excluded from the current stock view. No historical warehouse or item-ledger LP fields are modified by this inquiry change.

## Unresolved production blocker

The terminal records every scanned pallet locally, but the existing confirmLine API receives only the first pallet number. BC can allocate the remainder from other pallets using stock at registration time. Client preflight and registration are separate requests; therefore this implementation cannot guarantee that only the scanned pallets will be consumed if stock changes between them.

Before deployment, transmit and persist the full pallet/quantity allocation in BC and restrict posting to that allocation in the posting transaction. Add real BC integration tests, including concurrent stock changes and failures partway through confirmation.

## Validation performed

- 324 BADE JVM tests passed, including 18 new pallet-plan/put-away-policy tests.
- BADE debug lint: 0 errors, 73 warnings.
- Signed Android release build 1.14.110-bade (versionCode 200110) succeeded locally. This APK is a test candidate, not a production-approved release.
- Five AL scenarios were added to the existing Bin Rollup Tests codeunit for exact lot/serial filtering, blank lots, aggregate bin behavior and matching drill-down totals. They have not been compiled or executed in BC.
- git diff --check passed.
- No real terminal/BC posting test or environment installation was performed.
- The repository AL package workflow currently contains a placeholder, so its completion does not establish AL compilation success.

The accepted bulk LP capacity/count/remainder calculation is unchanged. Existing unrelated Android build, updater and release-workflow edits are outside this commit.

## Publication — 14 September 2026

At the user's explicit request after disclosure of the unresolved BC limitation, Android 1.14.110-bade (200110) was published to the BADE update channel. This publication does not resolve the blocker or establish production test approval.

- Release: https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.110
- BADE channel now serves versionCode 200110. Its public APK download and SHA-256 were verified.
- EMU channel was checked before and after and is unchanged.
- No BC package was published or installed. The lot-filter AL changes still require a separate compiled BC extension.
- No actual terminal installation was performed.
- Release assets include the local Android build/updater patch needed to reproduce the published APK alongside source commit db5d48b.
