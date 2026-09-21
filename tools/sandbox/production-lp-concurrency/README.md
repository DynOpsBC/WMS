# sand0309 production LP concurrency harness

Sandbox only. Never publish the test extension to Production. Both the fixture API and HTTP helper reject environments other than sand0309. Test data uses the PPTEST location and PROD-PICK-TEST document. The fixture replaces only the designated synthetic records; do not use these IDs for customer operations. No physical device or UI is simulated by this harness.

1. Compile/publish `al-print-tests` (version 1.0.0.73) to sand0309 Sandbox with the installed AL development tools. Main app must be 1.14.1.67 or later.
2. Set `AL_TOOL_DIR` to the installed AL CLI `tools/net10.0/any` directory containing Microsoft.Dynamics.Nav.Deployment.dll. Use the existing authorized BADE account token cache; no tokens are printed or stored in this repo.
3. `dotnet build tools/sandbox/production-lp-concurrency/SandboxHttp.csproj -c Release`
4. Set `SANDBOX_HTTP_DLL` to the resulting SandboxHttp.dll path and run `python3 tools/sandbox/production-lp-concurrency/run.py` from the repository root. Optional `SANDBOX_TEST_OUTPUT` sets the output directory.

Six round trips: three duplicate requests from the same operator and three owner-versus-foreign-operator races. Independent HttpClient instances start from one synchronization gate; start/end timestamps record overlap. Each pair invokes the actual terminal preparation/delivery API. Server assertions verify warehouse balances, LP balances and production quantity after each phase. `finally` cleans synthetic active data. If the process is killed, explicitly invoke the guarded fixture API cleanup action before a new run.

Expected: preparation duplicate is idempotent (204/204); wrong owner rejected (400); exactly one delivery succeeds (204), the other gets 400 or 404 because of ownership/deleted pick. Errors are never automatically retried. Physical terminal UI testing is separate.
