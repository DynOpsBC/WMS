# EMU 1.14.110 publication — 14 September 2026

Published at the user's request, using the same Android source as BADE 1.14.110. Both APKs use application ID `com.dynops.bcwms.emu`, versionCode `200110` and versionName `1.14.110-emu`.

## Packages and update paths

| Installed signature/version | Update path |
| --- | --- |
| Historical signature, 1.14.109 compatible package | Update button downloads 1.14.110 from `android-emu-legacy-channel`. |
| Historical signature, 1.14.105 | Update button installs the existing 1.14.106 bridge; press Update again after reopening to install 1.14.110 from the legacy channel. |
| Standard DynOps signature | Install the standard 1.14.110 APK directly from the shared release. The main update channel still serves the bridge until migration of historical 1.14.105 devices is confirmed. |

Do not uninstall the application to change signing populations. The two APKs are not interchangeable as in-place updates.

- [Standard APK release](https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.110): `BCWMS-EMU-1.14.110-RELEASE.apk`.
- [Historical-signature release](https://github.com/DynOpsBC/WMS/releases/tag/android-emu-legacy-v1.14.110): `BCWMS-EMU-1.14.110-UYUMLU.apk`.
- `releases/android/emu/latest.json` now mirrors the public main channel's existing 200106 bridge; only its public release notes changed from 1.14.109 to 1.14.110. The bridge APK, hash and version are unchanged.
- `releases/android/emu/legacy/latest.json` mirrors the public legacy channel, advanced from 200109 to 200110.
- BADE's public update manifest remains unchanged at 200110. The shared release retains its BADE assets and manifest; the standard EMU manifest is named `latest-emu.json`.

## Validation

- 324 EMU JVM tests passed, with no failures, errors or skipped tests.
- EMU debug lint: 0 errors, 73 warnings.
- Both release builds completed with minification and debugging disabled. Application identity, version, signing certificate and embedded update-channel URL were checked.
- Both public APK downloads were hashed and matched their published manifests. The main, legacy and BADE public channel manifests were checked after publication.
- Standard APK SHA-256: `cfbb2f46528d8ceb8c067a82ce0830dea304e0b5b73a33e7eaa34488616bf293`.
- Compatible APK SHA-256: `071a911529367f7093f94453b5b95d2f0dcd29d67192376db6e6794d72f6ae60`.
- Standard certificate SHA-256: `ea7710af652faf6beff836d64327159b021c0561297cf9ae60987d26592b81eb`.
- Historical certificate SHA-256: `b28316a8ba08c9241392fe881bd9f55eaa6b3c330970003197bbe54fe25e2204`.

Source: commit `454b5b315dae5e0f290d4bdc1847e83c0e701a89` plus the existing `android-build-source.patch` asset in the shared release. Build arguments: `-PlegacyEmuUpdates=true -PlegacyEmuKeystore=<historical-key-path> -PreleaseVersionCode=200110 -PreleaseVersionName=1.14.110`.

## Scope and remaining limitations

EMU retains its existing BC-controlled pallet policy; BADE's forced pallet workflow is not applied to EMU. No BC extension was compiled, published or installed. The lot-filter AL change needs a separate BC deployment. The unresolved multi-pallet `confirmLine` limitation described in `bade-feedback-2026-09-14.md` remains. No physical terminal installation or real BC posting test was performed.
