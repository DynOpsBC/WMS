# BADE production LP HTTP concurrency — 2026-09-22

Only sand0309 Sandbox was accessed. Main AL stays at 1.14.1.67; APK stays at 1.14.154. No production application code was changed or deployed during this run.

## Real API results

Six two-phase round trips were exercised using the same preparation and delivery endpoints called by the terminal. Each phase starts two independent HTTP clients at a shared synchronization gate. Requests have overlapping client start/end timestamps. This proves behavior under concurrent incoming requests; it does not claim that server statements execute in parallel behind database locks.

- Three rounds: same operator sends duplicate preparation and duplicate delivery.
- Three rounds: the assigned operator races a different operator for preparation and delivery.
- 24 concurrent action requests, with 12 post-phase server assertion calls.
- Duplicate preparation returns 204/204 and moves stock exactly once.
- Foreign-operator preparation returns 400; the owner succeeds.
- Exactly one delivery succeeds. The other is rejected with 400 (ownership) or 404 (the pick already closed).

Every round checks source LPs and warehouse stock 100 → 90 in RAW and RAW2; target LP = 20; staging stock = 20 and production picked = 0 after preparation; staging = 0, production stock = 20, production picked = 20 after delivery. Target LP remains attached to the intended production order. No doubled stock, double production pick, lost quantity or unauthorized mutation was observed.

The test fixture API is in the test extension only, guarded by IsSandbox and exact sand0309 environment name. Synthetic active data is cleaned in finally. The API assertions run in separate requests after competing mutations, rather than relying only on response status codes. The initial isolated AL test method could not persist cross-session fixtures; the final harness therefore sets them up through the guarded API.

## Remaining UI check

This is an actual sandbox API integration test, not a two-physical-terminal test or completed terminal UI walkthrough. The emulator is available, but an authenticated BADE sand0309 terminal session is still needed to verify scanning, confirmation dialogs, screen refresh and navigation end to end. The user was asked to log in without sharing passwords or PINs. Do not describe this remaining check as passed.

The earlier 43 named AL regression tests and the AL 67 physical-stock fix remain documented in bade-production-lp-sandbox-validation-20260922.md. Test extension 1.0.0.73 adds the HTTP fixture/harness; it is not a live release package.

Reproducer: tools/sandbox/production-lp-concurrency/README.md. Results: SANDBOX-CONCURRENCY-RESULTS.json attached to the AL 67 GitHub release.
