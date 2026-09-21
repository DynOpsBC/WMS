# BADE 1.14.151 — selected pallet row isolation

## Problem and change

Opening item `AB.02029` on bin `A.C01.13` in pick `PI001945` could display
`Uygun kaynak palet bulunamadı` for the earlier item `YM.00273` on `Y.A01.11`.
The terminal planned every preceding take line with a positive quantity to
handle before planning the selected row. An unrelated row without an LP
therefore prevented the selected item's scanner from receiving a plan.

The selected-row lookup now considers only requested rows and preceding rows
that may draw from the same item, variant, location, bin and tracking stock.
Blank lot/serial values remain potential overlaps; different units of measure
do not exclude a row because pallet allocation uses base quantities. Earlier
overlapping rows still reserve pallet capacity. Full document registration
continues to validate every positive take line and require its scan proof.

## Verification

`DocumentPalletPlansTest` reproduces the screenshot values: earlier line 10000,
`YM.00273`, `Y.A01.11`, 240 KG; selected line 30000, `AB.02029`, `A.C01.13`,
7,809 units. With the old selection logic the test failed with the same
`YM.00273` error. After the fix it requests only line 30000 and returns its
7,809-unit pallet plan.

Seven regression tests cover the screenshot, separate stock identities,
shared-pallet quantity limits, blank tracking overlap, full registration
validation, selected-item error attribution and stale row snapshots.
Before the fix, three of these tests failed. After the fix, all seven pass.
Full unit suites pass with zero failures: BADE 416 tests, EMU 396 tests.
Both debug lint tasks pass.

The original `PI001945` has no open pick lines in `sand0309` at verification
time (HTTP 200, empty collection). This specific fix is verified by automated
tests against reconstructed API data, not by a completed operator session on
that original document. The earlier production movement and multi-source LP
API acceptance results are recorded separately in
`sand0309-production-lp-e2e-2026-09-21.md`.

## Delivery

Android version: `1.14.151-bade`, versionCode `200151`.
Compatible BC extension: the already tested `1.14.1.64`; no AL change is needed
for this terminal-side correction. The `1.14.150` APK does not include this fix.
