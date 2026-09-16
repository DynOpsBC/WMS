# Müşteri dalları (15 Eylül 2026'dan itibaren)

| Müşteri | Dal | Çalışma kopyası | Android flavor / kanal |
|---|---|---|---|
| BADE | `customer/bade` | `EL_TERMINAL/WMS` | `bade` → `android-bade-channel/latest.json` |
| EMU (DKÇ) | `customer/emu` | `EL_TERMINAL/WMS-emu` (git worktree) | `emu` → `android-emu-channel/latest.json`; eski imzalı cihazlar `android-emu-legacy-channel` |

İki dal da `5313e92` (BADE 1.14.116 / BC 1.14.1.38) noktasından ayrıldı; o ana kadarki
bütün düzeltmeler (okuyucu girişi, raf-önce toplama, MTE geri dönüşü, EMU eski imza köprüsü)
ikisinde de var. Bu noktadan sonra:

- EMU'ya özgü kod yalnız `customer/emu` dalına yazılır; BADE'ye özgü kod yalnız `customer/bade`.
- İki müşteriyi ilgilendiren genel düzeltmeler önce bir dalda yapılır, sonra diğerine
  `git cherry-pick` ile taşınır (tam merge yapılmaz, yoksa müşteriye özgü değişiklikler karışır).
- `main` paylaşılan tarihçedir; müşteri dalları `main`'e geri merge edilmez.
- Eski `fix/bade-pallet-feedback-20260914`, `release/bade-*`, `audit/*` dalları tarihçe
  içindir; yeni iş açılmaz.

## EMU derleme notları

- BC paketi sürümü EMU dalında **1.14.2.x** (BADE 1.14.1.x'te kalır); aynı uygulama kimliği, iki
  müşterinin BC ortamları ayrı olduğu için çakışmaz.

- Sürüm: `-PreleaseVersionCode=2001NN -PreleaseVersionName=1.14.NN` (BADE ile aynı numara
  bandı, aynı `build.gradle.kts`; iki flavor aynı kaynaktan derlenir).
- Sahadaki 1.14.105 kurulumları tarihi debug sertifikasıyla imzalı: bu cihazlar için
  `-PlegacyEmuUpdates=true -PlegacyEmuKeystore=<tarihi-anahtar-yolu>` ile derlenip
  `android-emu-legacy-channel` üzerinden dağıtılır (bkz. `docs/emu-update-2026-09-14.md`).
- Yeni sertifikalı EMU kurulumları `android/play/keystore/bcwms-release.jks` ile imzalanır
  (dosya git dışında; worktree'ye kopyalandı).
- BC ortamı: DKÇ `Sandbox3007` (flavor `emu`, `BC_DEFAULT_ENVIRONMENT`).

`Desktop/el_terminal_dkc` (github DynOpsBC/el_terminal_dkc) 27–28 Ağustos'ta açılmış bağımsız
bir EMU kopyasıdır (AL 1.14.0.73, Android 1.14.59); o tarihten sonra EMU sürümleri WMS
deposundan çıktığı için güncel değildir. Kullanılmaz.
