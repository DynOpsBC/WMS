# Paket ve dal düzeni (16 Eylül 2026'dan itibaren)

Tek repo (DynOpsBC/WMS), tek uygulama kimliği (BCWMSApp), üç hat:

| Hat | Dal | Çalışma klasörü | BC sürümü | Android |
|---|---|---|---|---|
| **Ana paket (BASE)** | `main` | `EL_TERMINAL/WMS-main` | 1.14.**0**.x | flavor `dynops` (com.dynops.bcwms) |
| BADE | `customer/bade` | `EL_TERMINAL/WMS` | 1.14.**1**.x | flavor `bade` → `android-bade-channel/latest.json` |
| EMU / DKÇ | `customer/emu` | `EL_TERMINAL/WMS-emu` | 1.14.**2**.x | flavor `emu` → `android-emu-channel/latest.json`; eski imzalı cihazlar `android-emu-legacy-channel` |
| Sonraki müşteri | `customer/<kod>` | `EL_TERMINAL/WMS-<kod>` | 1.14.**3**.x, 1.14.4.x … | yeni flavor + kanal |

Sürüm şeması **A.B.C.D**: `A.B` ürün hattı (1.14), `C` müşteri yuvası (0 = ana paket), `D` yapı numarası.
Ürün hattı 1.15'e geçince ana paket 1.15.0.x, müşteriler 1.15.1.x / 1.15.2.x olur; her müşteride sürüm
hep artar, BC yükseltmeyi kabul eder.

## Karışmaya karşı emniyet

Üç paketin uygulama kimliği aynı olduğundan BC, BADE ortamına EMU paketini "yükseltme" diye kurardı
(1.14.2.x > 1.14.1.x). Bunu codeunit 72322 **DOPSWHS Edition** önler:

- Her paket derlendiği hattı bilir (`Current()` = BASE / BADE / EMU; dallar arasında yalnız bu satır farklıdır).
- Kurulum/yükseltme, Kurulum kaydına **Installed Edition** yazar (Kurulum kartında görünür).
- Yükseltme öncesi `OnCheckPreconditionsPerCompany` başka bir hattın damgasını görürse hata verir; BC
  yükseltmeyi geri alır, eski paket kurulu kalır. Boş damga (eski paket) ve BASE damgası her hatla
  yükseltilebilir (ana paketten müşteri paketine geçiş).

## Kod akışı

- **Genel düzeltme / genel özellik** → önce `main`'e commit, ana paket derlenir, sonra her müşteri dalına
  `git merge main`. Çakışma yalnız `al/app.json` sürüm satırında beklenir: müşteri dalı kendi sürümünü
  tutar (`git checkout --ours al/app.json`, sonra D'yi artır).
- **Müşteriye özgü iş** yalnız o müşterinin dalına yazılır (BADE: MTE rapor entegrasyonu; EMU: DKÇ'ye
  özgü varsayılanlar). Müşteri dalları `main`'e geri merge edilmez; bir müşteri için yazılan genel
  değer taşıyan iş ana pakete alınacaksa `main`'e ayrıca (cherry-pick/elle) taşınır.
- Müşteri dalından müşteri dalına doğrudan merge yapılmaz.

## Yeni müşteri açma listesi

1. `git checkout -b customer/<kod> main` ve `git worktree add ../WMS-<kod> customer/<kod>`.
2. `al/src/Setup/Edition.Codeunit.al` → `exit('<KOD>')`; `al/app.json` → `1.14.<N>.0`.
3. Android: `build.gradle.kts` içine flavor (`applicationIdSuffix ".<kod>"`, `BC_DEFAULT_ENVIRONMENT`,
   `UPDATE_MANIFEST_URL` = `android-<kod>-channel/latest.json`), GitHub'da `android-<kod>-channel`
   release'i ve `releases/android/<kod>/latest.json`.
4. `al/.vscode/launch.json` → müşterinin BC kiracısı/ortamı.
5. İlk paket: BC `.app` + APK; release etiketi `android-v1.14.<N>.0-<kod>`.
6. Bu tabloya satır ekle.

## Derleme

- BC (macOS'ta alc): `"$HOME/Library/Application Support/Code - Insiders/User/globalStorage/ms-dotnettools.vscode-dotnet-runtime/.dotnet/10.0.12~arm64~aspnetcore/dotnet" ~/.vscode-insiders/extensions/ms-dynamics-smb.al-18.0.2732683/bin/alc.dll /project:al /packagecachepath:<WMS>/al/.alpackages /out:<paket>.app`
  (worktree'lerde paket önbelleği `../WMS/al/.alpackages`; test uygulaması için önbelleğe yeni derlenen .app da eklenir).
- Android: `JAVA_HOME=/Applications/Android Studio.app/Contents/jbr/Contents/Home ./gradlew :app:assemble<Flavor>Release -PreleaseVersionCode=2001NN -PreleaseVersionName=1.14.NN`
  (imza `android/play/keystore/bcwms-release.jks`, git dışında). EMU eski imzalı cihazlar:
  `:app:assembleEmuLegacyRelease -PlegacyEmuUpdates=true -PlegacyEmuKeystore=$HOME/.android/debug.keystore`
  (bkz. `docs/emu-update-2026-09-14.md`).

## Yayın etiketleri

- Ana paket: `base-v1.14.0.x` (BC .app + dynops APK).
- BADE: `android-v1.14.NN` (tarihsel ad), kanal `android-bade-channel`.
- EMU: `android-v1.14.NN-emu`, eski imza `android-emu-legacy-v1.14.NN`, kanallar `android-emu-channel` / `android-emu-legacy-channel`.
- BC ortamına yükleme her zaman kullanıcı tarafından yapılır (Uzantı Yönetimi → Yükle); önce BC paketi,
  sonra terminal kanalı ilerletilir.

Eski dallar (`fix/bade-pallet-feedback-20260914`, `release/bade-*`, `audit/*`, `uat-fixes`) tarihçe içindir.
`Desktop/el_terminal_dkc` (DynOpsBC/el_terminal_dkc) 27–28 Ağustos'ta açılmış bağımsız ve güncel olmayan
bir EMU kopyasıdır; kullanılmaz.
