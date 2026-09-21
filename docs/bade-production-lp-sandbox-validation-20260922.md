# BADE production LP sandbox validation — 2026-09-22

Environment: sand0309 (Sandbox). No Production environment was opened or modified.
Application: BCWMSApp 1.14.1.67. Android: BADE 1.14.154 (unchanged).

## Defect found and fixed

AL 1.14.1.66 accepted preparation in the source bin when LP metadata showed enough stock but actual warehouse stock was insufficient. Because this path creates no warehouse movement, native movement validation did not run. The new regression reproduced the defect on 66.

AL 67 checks actual warehouse quantity before LP mutations, rejects outbound-blocked bins, and accumulates demand across lines sharing location, bin, item, variant, lot, serial and package. This prevents counting the same physical stock twice. The regression passes on 67.

## Sandbox results

43 named AL test methods passed; zero failures. The runner also emits one unnamed aggregate per codeunit (45 runner results total). Codeunits: 72186 and 72183. Test extension version: 1.0.0.70 (see test manifest for authoritative version).

Covered: multiple source bins; partial source LP quantities consolidated into one target LP; same-bin preparation; mixed products and lots; box/base-unit conversion; lot-preserving warehouse movements and production delivery; insufficient physical stock; shared-stock cumulative demand; rollback after a second source fails; native registration failure rollback; wrong owner and ownership change between preparation and delivery; wrong/moved/blocked source; blocked lot and staging bin; production bin rejected as staging; missing, excess, insufficient or duplicate scan plans; preparation replay; stale delivery; missing delivery proof; whole-LP identity and production assignment; HM/YM expiry ordering and other-item receipt FIFO; explicit lot preservation; demand spilling into a newer lot.

Preparation leaves production quantity unpicked. Delivery records the production pick and moves the prepared LP. Test assertions cover source, staging and destination warehouse quantities and LP quantities.

Synthetic fixture scope: PPTEST location, PROD-LP-TEST order and PROD-PICK-TEST pick. After tests, read-only sand0309 API checks returned empty lists for LPs, warehouse entries and picks at PPTEST.

## Limits

These are server-side sandbox tests, not a guarantee of zero defects. Real simultaneous requests from two physical terminals and the complete physical operator workflow were not exercised in this run. APK 154 was not changed or rebuilt for this server fix. Prior APK verification is documented in the preparation release report.

For morning validation use AL 67 with APK 154; AL 66 is superseded by this stock-validation fix. No live deployment was performed.
