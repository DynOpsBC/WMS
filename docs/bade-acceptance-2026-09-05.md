# BADE simulator acceptance — 2026-09-05

Environment: E-DefterSandbox, BS GROUP İÇ VE DIŞ TİC. SAN. A.Ş.
Device: Medium_Phone_API_36.1, com.dynops.bcwms.bade.
The user completed authentication. No sign-in credentials were entered by the agent.

## Reproduced on 1.14.97-bade

| Scenario | Observed result |
| --- | --- |
| RE000921 / PUO.B100929, 100 units, LP + Kaydet | Failed in standard posting: Warehouse Receipt Header field 72423 Boolean conflicted with Posted Whse. Receipt Header field 72423 Code[20]. |
| LP000066 after that failed post | Open, planned quantity 50, zero content lines. No receipt stock was left inside this LP. LP000067 was also listed as an open 50-unit plan. |
| Open pending LP000066 from LP menu | Generic add-item and delete actions were offered despite the pending receipt. These could bypass or invalidate the receipt plan. |
| Search source entry 8338 in Stoktan LP Oluştur | Failed with HTTP 501 because the query used OR across entryNo and itemNo. |

## Corrections

- Receipt posting guard moved to field 72435. Old field 72423 is Removed, retaining its installed database column without ForceSync.
- Related shipment copy reviewed against Base Application source: source LP Code[20] was copied into destination SSCC Code[18]. Destination SSCC now uses the source SSCC ID 72407. Existing SSCC data is migrated from the widened, obsolete legacy column.
- Pending receipt LPs expose their pending document through the API. Generic LP mutations are restricted, and the LP screen directs the operator to the receipt's LP + Kaydet operation.
- Numeric stock entry and numeric item searches use separate BC-compatible queries and merge results by entry number.
- Reconfirming a 100-unit receiving row with an existing 50 + 50 pallet plan preserves both allocations; a conflicting total is rejected before changing the plan.
- Added posting-field compatibility check to AL CI. Running against the previous commit fails on both reproduced/potential field collisions; corrected schema passes nine posting paths.
- Added AL regression cases for header TransferFields, long LP / SSCC transfer, pending LP mutation guards, and bulk-row reconfirmation. These cases require a BC test runner; compilation of the application alone does not execute them.

## Verified on 1.14.98-bade

- Release APK built and installed over the existing app without clearing authentication. Device reports versionCode 200098 and versionName 1.14.98-bade.
- Repeated numeric search 8338 in the actual emulator: returned entry #8338, AB.00118, 100000 ADET, lot A101809, document 107756. The previously failing query now succeeds against the connected BC environment.
- Android release unit suite: 243 tests, no failures or errors. Release APK assembly succeeded after retrying a local disk-space failure with reduced build memory.
- BC application 1.14.1.29 compiled successfully with the AL compiler. Posting-field schema audit passes all nine configured paths.
- This is an acceptance candidate, not a confirmed production-ready release. The BADE automatic-update channel has not been promoted.

## Acceptance still required

The automated AL publishing tool could not access its saved authentication key, and no controlled browser session was available. The user was asked to install the corrected AL package in E-DefterSandbox.

After installation, retry RE000921 and check successful 100-unit receipt, two 50-unit LP contents, a single unchanged purchase/ledger source line, and exact LP-to-ledger links. Then test stock-to-LP creation across bins and shipping completion. Do not interpret local compilation, Android unit tests, or green CI checks as a successful BC posting test.

The workflow named AL Build currently runs audits and a placeholder packaging step. Real application compilation for this work was performed locally with the AL compiler.
