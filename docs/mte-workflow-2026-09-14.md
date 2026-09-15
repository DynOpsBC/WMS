# Terminal MTE access — 14 September 2026

Requested entry points: printing from the LP creation/management page, and obtaining labels after warehouse receipt posting.

## Changes

- The LP card now has an explicit **MTE Yazdır** action. It calls the existing BC `licensePlates/printPalletLabels` action with the device's label printer. It requires loaded contents and blocks LPs awaiting receipt posting.
- The existing PDF action remains available as **LP QR Belgesini Yazdır**. It does not generate an MTE.
- Batch printing of filled LPs retains the MTE action even when only a document printer is selected. An empty label-printer code lets BC resolve its label-printer mapping; it no longer silently substitutes a PDF containing only the LP QR code. Empty carriers retain their previous QR routes.
- Successful warehouse receipt posting opens an MTE sheet before reloading the working receipt, which BC may have deleted. The sheet loads all pages of positive LP contents tied to the exact warehouse receipt, deduplicates LPs and lets the operator explicitly select missing labels.
- Posting already requests MTE labels in BC. Nothing is initially selected in the sheet and no second automatic print is issued. It may include previous partial receipts of the same working document; the screen states this explicitly.
- Manual reprints use the label printer and a long-running print request. LP contents are checked again before sending. Incomplete list reads block selection; unsuccessful or uncertain print results do not trigger automatic retries. Reprinting never posts the receipt again.

## Validation and deployment

- Regression coverage checks MTE versus PDF routing, unloaded/empty/pending LP guards, grouping multiple material/lot lines under one LP, and excluding other receipts, other document types and nonpositive contents.
- BADE and EMU each passed 329 JVM tests (0 failures/errors/skips). BADE lint completed with 0 errors and 73 warnings; the BADE debug APK build succeeded. `git diff --check` passed.
- No connected Android terminal/emulator or physical printer was available. BC services and physical printing have not been exercised.
- No AL change or BC extension deployment is included. This uses the existing `printPalletLabels` action and ZPL MTE template. A PDF MTE layout is not implemented.
- Initial validation on 14 September was local; the changes were absent from APKs 1.14.110–1.14.112. They were subsequently released as BADE 1.14.113 (see below).

## BADE release — 15 September 2026

The MTE changes were applied on top of the published 1.14.112 baseline in `WMS-audit-bade-delivery`, branch `release/bade-1.14.113-mte`, commit `a26aa01d5546798d54af3be8b2093d42e48ffd00`. The unrelated local changes in this checkout were not included.

- Published [BADE 1.14.113](https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.113), versionCode 200113, and advanced the BADE stable update channel.
- BADE and EMU each passed 342 JVM tests; BADE lint has 0 errors, 77 warnings and 18 information messages.
- Four emulator dialog tests passed. The new MTE failure/retry/continue case was additionally verified at 720×1280 px / 320 dpi, with a clean screenshot after dismissing an emulator system warning.
- Signed APK certificate matches 1.14.112. Upgrade installation over emulator BADE 1.14.98 succeeded without clearing data.
- Public APK download SHA-256: `68dab2a21efd30616197b832049f87ba86af03e6b9b38653768cd6c20d007c06`.
- Release evidence: `../WMS-audit-bade-delivery/output/release-1.14.113/`.
- Real BC receipt posting and physical printer output still require on-site verification; no AL or Windows agent change was made for this feature.
