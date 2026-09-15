# Play Publisher Setup

`gradle-play-publisher` Closed Track upload yardımcısı için gerekli credentials.

## Secrets (CI'da bu klasör boş kalır — secrets repo'ya commit edilmez)

| Dosya | Kullanım |
|---|---|
| `play-service-account.json` | Play Console "Setup → API access" sayfasından oluşturulan service account JSON anahtarı |
| `keystore/upload-keystore.jks` | Play App Signing için upload keystore |
| `keystore/keystore.properties` | `storeFile=play/keystore/upload-keystore.jks` / `storePassword=...` / `keyAlias=upload` / `keyPassword=...` |

## CI'da
GitHub Actions release workflow'u şu secret'ları çözer:
- `PLAY_SERVICE_ACCOUNT_JSON` → `play/play-service-account.json`
- `ANDROID_KEYSTORE_BASE64` → base64 decode → `play/keystore/upload-keystore.jks`
- `KEYSTORE_PASSWORD`, `KEY_PASSWORD` → `play/keystore/keystore.properties`

Sonra:
```
./gradlew :app:publishReleaseBundle -PwithPlayPublisher
```

## Saha paketi kuralı

- Terminallere yalnız `assembleBadeRelease` / `assembleEmuRelease` çıktısı verilir.
- Debug APK'lar `.debug` applicationId kullanır, stabil uygulamanın üstüne kurulmaz
  ve uygulama içinden release güncellemesi istemez.
- Tüm release APK'ları aynı BCWMS sertifikasıyla imzalanır. Yayın hattı BADE ve
  EMU sertifika parmak izlerini sabit değerle doğrular; farklı imzada yayını keser.
- `1.14.105-emu` tarihî debug sertifikasıyla kurulu cihazlar kaldırılmadan
  `emuLegacyRelease` paketiyle güncellenir. Bu paket release optimizasyonlarını
  kullanır, debug erişimini kapatır, uygulama kimliğini ve eski imzayı korur.
  İlk uyumlu APK doğrudan kurulur; sonraki güncellemeler
  `android-emu-legacy-channel/latest.json` kanalından gelir. Ana EMU kanalına
  bu imzalı APK konulmaz; orada farklı release imzasıyla çalışan cihazlar vardır.

Eski EMU cihazları için derleme (anahtar yolu dışarıdan verilir, sertifika
parmak izi Gradle tarafından zorunlu doğrulanır):

```sh
./gradlew :app:assembleEmuLegacyRelease \
  -PlegacyEmuUpdates=true -PlegacyEmuKeystore=/secure/path/debug.keystore \
  -PreleaseVersionCode=200109 -PreleaseVersionName=1.14.109
```

Sonraki yayınlarda sürüm kodu artırılmalı; aynı tarihî anahtar ve aynı kanal
korunmalıdır. APK/hash/manifest doğrulanmadan kanal güncellenmemelidir.

Build sırasında `withPlayPublisher` property'si verilmezse plugin
yüklenmez ve Play credentials gerekmez (yerel dev için ideal).

## Closed Track listesi
İlk müşteri admin gmail'leri Play Console → Internal/Closed testing →
Tester list olarak eklenir. Tester listesi propagation ~6 saat.
