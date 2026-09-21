DKÇ / EMU terminal güncellemesi — **1.14.154** (200154).

- Ürün sorgu ekranında daha anlaşılır ürün kartları, stok bilgileri ve etiket işlemleri.
- Birden fazla ürünü seçip her ürün için ayrı etiket adedi belirleyerek toplu yazdırma.
- Toplu etiket penceresinde kompakt ürün satırları, kolay adet değişimi ve hemen altında toplam / yazdırma düğmesi.
- Raf etiketinde Tek raf, Toplu raf ve Alan etiketi seçenekleri; raf seçimi veya okutma sonrası otomatik hazırlama.
- Önceki güncellemelerdeki çoklu ürün sorgusu, yedek parça filtresi ve Stok ekranı dahildir.

**Paket seçimi:** Yeni kurulumlar için `RELEASE.apk`; tarihsel imzalı mevcut terminaller için `UYUMLU.apk`. Uygulama içindeki güncelleme işlemi kurulu imzaya uygun kanalı kullanır. İmzayı değiştirmek için uygulamayı kaldırmayın.

Her iki EMU güncelleme kanalı bu sürüme yönlendirilir. Bu yayın Android terminal güncellemesidir; BC uzantısı ve Print Agent değişmez.

Doğrulama: 381 birim testi başarılı; toplu etiket seçimi/adetleri ve uzun liste, raf etiketi akışı emülatörde kontrol edildi. İki APK'nın paket kimliği, sürümü ve imzası doğrulandı. Gerçek yazıcıya test çıktısı gönderilmedi.

## Build and update channels

- Android source: customer/emu. Build properties: `releaseVersionCode=200154`, `releaseVersionName=1.14.154`.
- Standard build: `:app:assembleEmuRelease`; legacy build: `:app:assembleEmuLegacyRelease -PlegacyEmuUpdates=true -PlegacyEmuKeystore=<historical-key-path>`.
- Standard channel: `android-emu-channel`; historical certificate channel: `android-emu-legacy-channel`.
- Release: https://github.com/DynOpsBC/WMS/releases/tag/android-v1.14.154-emu
- Standard APK SHA-256: `db959e1939084be1ec30f281b6f4557769442cc8e7ee5822d4cc289c539dbe57`.
- Compatible APK SHA-256: `a1822f5951b077dbfd4289677559d3e373f9d37ca9170ce208573d8ae54cbf6e`.
- Standard certificate: `ea7710af652faf6beff836d64327159b021c0561297cf9ae60987d26592b81eb`.
- Historical certificate: `b28316a8ba08c9241392fe881bd9f55eaa6b3c330970003197bbe54fe25e2204`.

Both packages have application ID `com.dynops.bcwms.emu`. EMU debug lint and both release builds passed. Instrumented UI checks covered bulk selection and per-product counts, a 30-product list with reachable footer, and single/bulk/zone bin-label flows. No live printing was performed. BADE and general GitHub latest remain unchanged. Local AL and Print Agent changes are outside this release.
