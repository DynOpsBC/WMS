# BCWMSApp

[![Release](https://img.shields.io/github/v/release/DynOpsBC/WMS?label=latest&color=6c5ce7)](https://github.com/DynOpsBC/WMS/releases/latest)
[![BC Platform](https://img.shields.io/badge/Business%20Central-24.0%2B-026CC5)](docs/install-pte.md)
[![AL](https://img.shields.io/badge/AL-1.12.0.0-026CC5)](al/app.json)
[![Android](https://img.shields.io/badge/Android-1.13.0-3DDC84)](android/app/build.gradle.kts)

Microsoft Dynamics 365 Business Central SaaS için gelişmiş depo yönetim sistemi (WMS): el terminali, BC eklentisi ve iş istasyonu arayüzü.

> **Kurulum:** [docs/install-pte.md](docs/install-pte.md) · **Sürüm güncelleme:** [docs/update-flow.md](docs/update-flow.md) · **Lisans/JWT:** [docs/license-protocol.md](docs/license-protocol.md)
>
> **Android kurulumu:** [docs/android-install-guide.md](docs/android-install-guide.md) · **Operatör kılavuzu:** [docs/wms-end-user-quickstart.md](docs/wms-end-user-quickstart.md) · [CHANGELOG](releases/android/CHANGELOG.md)

---

## Depo yapısı

| Klasör | İçerik |
|---|---|
| `al/` | Business Central AL eklentisi — publisher `DynamicsOps`, prefix `DOPSWHS`, obje aralığı `72000-72099` + `72200-72489` |
| `android/` | Kotlin / Jetpack Compose el terminali uygulaması (iki flavor) |
| `web/` | React + Vite iş istasyonu arayüzü — BC ControlAddIn ve bağımsız SaaS PWA olmak üzere iki hedef |
| `print-agent/` | Go ile yazılmış çapraz platform yazdırma köprüsü (BC → relay → yerel yazıcı) |
| `push-relay/` | BC webhook + SignalR + FCM için Azure Functions relay'i |
| `licensing-service/` | RS256 JWT lisans üretici/doğrulayıcı Azure Function (KeyVault destekli) |
| `customer-portal/` | Lisans ve sürüm yönetimi için Vite + MSAL portal |
| `docs/` | Teknik dokümantasyon, kurulum kılavuzları, kod standartları |
| `releases/` | Yayınlanan `.app` ve `.apk` paketleri |

---

## Depo akışları

Uygulama ELOG saha gözlemlerine göre tasarlandı; standart BC ambar akışlarının üzerine oturur.

**Mal kabul** — Satınalma siparişi veya ambar mal kabul belgesi okutulur, satır bazında miktar girilir. Post etme iki adımlıdır: önce *"Hazır olarak işaretle"*, sonra *"Kaydet"*. Yanlışlıkla post etmeyi engeller, geri alınabilir.

**Toplama (picking)** — Operatör terminalde bir toplama belgesini *"Üzerime Al"* der; atama BC'deki **Toplanacak Siparişler** ekranına da yansır. Ürün okutulunca sepete kaç adet konacağı ekranda onaylatılır. Kullanılan ana sepet (LP) belgeye kalıcı olarak yazılır ve paketlemeye taşınır.

**Paketleme (packing)** — Pick bazlıdır: **1 sepet = N sipariş**, hepsi tek oturumda. Sepetten alınan ürün okutulunca sistem hangi siparişe yazılacağını kendi seçer (yarım kalan sipariş varsa ona, yoksa en çabuk kapanacak olana). Bir siparişin payı bitince o sipariş için **kargo kolisi** istenir; koli okutulunca sevk + fatura + fiş çıkar.

> **Önemli ayrım:** *Sepet (tote/LP)* depoda kalır ve kayıtlı bir License Plate'tir. *Kargo kolisi* müşteriye gider ve kayıtlı LP olmak zorunda değildir — kargo etiketi, SSCC ya da matbu koli barkodu olabilir.

**Öner (suggestion engine)** — BC'deki Toplanacak Siparişler ekranı, ortak ürünü olan ve sevk tarihi yakın siparişleri tek toplama grubunda birleştirmeyi önerir. Puanlama ortak ürüne en yüksek ağırlığı verir.

---

## Geliştirme

### Ön koşullar

| Bileşen | Gereksinim |
|---|---|
| AL | **Windows** + AL Language uzantısı — macOS'ta derlenmez |
| Android | JDK 17 + Android SDK |
| Web / relay / portal | Node.js 20 + pnpm |
| print-agent | Go 1.22+ |

### Android

İki flavor var, aynı kaynak koddan derlenir. Fark yalnızca Entra uygulama kaydı, tenant, varsayılan ortam ve markadır.

| Flavor | Application ID | Entra client | Varsayılan ortam |
|---|---|---|---|
| `dynops` | `com.dynops.bcwms` | `8193e5c6-…` | `SandboxUS` |
| `bade` | `com.dynops.bcwms.bade` | `3c4ba25a-…` | `sand1506` |

```bash
cd android
./gradlew :app:assembleDynopsDebug
./gradlew :app:assembleBadeDebug
./gradlew lintDebug testDebugUnitTest
```

> Entra uygulama kaydı tenant'a özeldir: bir flavor'ı kendi tenant'ı dışındaki bir e-postayla açmaya çalışmak `AADSTS700016` verir. DynOps hesabıyla `dynops`, Bade hesabıyla `bade` derlemesini kullanın.

**V2 modu**, üst çubuktaki düğmeyle açılan yerel bir özellik anahtarıdır; sunucu verisini değiştirmez, klasik ekranları silmez, cihazda hatırlanır. Her iki flavor'da da mevcuttur.

### Web

```bash
cd web
pnpm install
pnpm build        # BC ControlAddIn paketi
pnpm build:saas   # bağımsız SaaS PWA
pnpm typecheck
```

### AL

macOS'ta derleme ve AppSourceCop doğrulaması **yapılmaz**. Yayın için Windows AL araç zinciri gerekir; sandbox tanımı `al/.vscode/launch.json` içindedir. Ayrıntı: [docs/al-publish-from-macos.md](docs/al-publish-from-macos.md).

Kaynak dili `en-US`, çeviriler `tr-TR` ve `de-DE`.

---

## Kimlik doğrulama modeli

Tüm BC API çağrıları **tek bir servis hesabının** AAD token'ıyla gider. Gerçek operatör ise BC içinde tanımlı bir **yerel WMS kullanıcısıdır** (`DOPSWHS Local User`) — kendi kullanıcı adı ve şifresiyle terminale girer.

Bunun sonucu: AL tarafında `UserId()` her zaman servis hesabını döndürür. Operatörü izlemek gereken her yerde (atama, log, telemetri) WMS kullanıcı kimliği ayrıca taşınır. Yeni kod yazarken bu ayrımı koruyun.

---

## Dokümantasyon

| Konu | Belge |
|---|---|
| Ürüne genel bakış | [docs/product-overview.md](docs/product-overview.md) |
| Teknik şartname | [docs/AdvWMS-Technical-Spec.md](docs/AdvWMS-Technical-Spec.md) |
| ELOG saha notları | [docs/ELOG-Gelistirme-Notlari.md](docs/ELOG-Gelistirme-Notlari.md) |
| AL kod standartları | [docs/al-coding-standards.md](docs/al-coding-standards.md) |
| Android kod standartları | [docs/android-coding-standards.md](docs/android-coding-standards.md) |
| Yazdırma köprüsü | [docs/print-bridge-setup.md](docs/print-bridge-setup.md) · [protokol](docs/print-bridge-protocol.md) |
| Operasyon runbook | [docs/operations-runbook.md](docs/operations-runbook.md) |
| Güvenlik denetimi | [docs/security-audit.md](docs/security-audit.md) |
| Üretime hazırlık | [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) |
| Bade teknik borç | [docs/BADE-TECHNICAL-DEBT.md](docs/BADE-TECHNICAL-DEBT.md) |

---

## Bilinen eksikler

Aşağıdakiler tespit edildi, henüz kapatılmadı:

- **Belge yazdırma çalışmıyor.** `Print Dispatcher.QueueReport` kuyruğa yazıcısı, kanalı ve içeriği boş bir satır yazıyor; paket fişi ve sevkiyat notu hiçbir zaman basılmıyor. Etiket basımı (LP / ürün / raf, ZPL) etkilenmiyor.
- **print-relay Azure Function'ı depoda yok.** `print-agent` `{relayUrl}/api/print-jobs` çağırıyor ama o fonksiyonun kaynağı burada değil. Ajanı doğrudan BC API sayfası `72299`'a bağlamak bu bağımlılığı kaldırır.
- Sevkiyat ekranındaki *"Faturalandır"* seçeneği işlevsiz.
- Paketlemede geri alma (undo) yok.
- `PATCH pickLines` yolunda sunucu tarafı eşzamanlılık koruması eksik.
- Android arayüzünde emoji hâlâ işlevsel rol taşıyor (ana ekran kutucuk ikonları, durum rengi öneki). Gerçek ikonlara geçilmeli.

---

## Katkı kuralları

`CLAUDE.md` dosyasındaki kurallar bağlayıcıdır. Özetle:

- AL objeleri `DOPSWHS` prefix'i ve tanımlı obje aralıklarını kullanır.
- macOS'ta AL derlenmez.
- Depo dışına dosya yazılmaz.
- Commit ve push yalnızca açıkça istendiğinde yapılır.
