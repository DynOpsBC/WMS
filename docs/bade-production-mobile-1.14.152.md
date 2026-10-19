# BADE 1.14.152 — production LP UI and terminal ownership

## Release correction

The production LP backend was present in BC 1.14.1.64, but the prepared LP
screen and terminal-operator ownership changes had remained in the main local
workspace. The separate checkout used for APK 1.14.151 omitted those changes.
This release integrates them with the multi-entry LP and row isolation fixes.

## Operator behavior

- Menu → Üretim → Sarfiyat → select a released production order →
  **Hazır LP ile Ambar Çekme** → scan LP → inspect contents and destination →
  **Bu LP ile Ambar Çekmesini Aç**.
- Both normal and prepared-LP production pick creation send the signed-in
  terminal operator. Navigation waits for a read-back confirming the pick
  number, production order and owner.
- Production pick details display the production order and destination bins,
  hide the shipping repacking LP action and register intact scanned LPs.
  Prepared rows start with the BC-scoped LP quantity, not the whole demand.
- All pick claim buttons send `claim(userId)` and verify persisted ownership.
  A successful HTTP response that still names `DYNOPS` does not produce an
  operator-assignment success message or unlock the document.
- Existing picks assigned to another user require reassignment through BC.
  The terminal does not force-take an operator's active work.

## Validation

BADE unit suite: 436 tests, zero failures. EMU unit suite: 416 tests, zero
failures. Tests cover MERVE/DYNOPS ownership mismatch, missing operator,
failed ownership read, absent endpoints, wrong production order, scoped LP
quantities and the 1.14.151 row-isolation regression.

`ProductionPickUiTest` exercises the real production composables with offline
component data. It selects an order, checks the ready-LP button and opens the
scanner. The emulator test passed; screenshots of both steps were captured.
Both debug lint tasks and the signed release build passed. The final release
APK was checked for the UI label and production/ownership API action strings.
This does not represent a full authenticated BC transaction or a
physical-terminal scanner acceptance test.

Read-only sandbox verification of `PI001730` returned owner `DYNOPS`, source
order `RLO.B100852`, status `InProgress`. No reassignment was performed.

BC remains 1.14.1.64. Android is 1.14.152-bade, versionCode 200152.
