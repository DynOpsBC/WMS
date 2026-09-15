# BADE 1.14.113 — LP ve mal kabul ekranlarından MTE yazdırma

Android sürümü: **1.14.113-bade**, versionCode: **200113**. Kaynak, 1.14.112 yayınının düzeltmelerini içerir.

## Kullanım

- **LP → LP kartı → MTE Yazdır** ile ürün içeren LP'nin madde tanımlama etiketleri yazdırılır. Boş, içeriği tam yüklenmemiş veya mal kabul kaydı bekleyen LP için düğme pasiftir.
- **Mal Kabul → Kaydet** başarılı olunca **Mal kabul kaydedildi · MTE** ekranı açılır. Etiketi eksik olan LP'leri seçip **Seçilen MTE'leri Yazdır** düğmesine basın. Mal kabul tekrar kaydedilmez.
- Kayıt sırasında BC zaten etiket isteği oluşturduğu için başlangıçta hiçbir LP seçilmez. Ekran, aynı belgenin önceki kısmi kabullerindeki LP'leri de içerebilir. Yeniden yazdırmadan önce fiziksel çıktıyı kontrol edin.
- Ürün içeren LP'lerin toplu baskısı mevcut ZPL MTE işlemini kullanır. **LP QR Belgesini Yazdır** ayrı PDF QR belgesi işlemidir.

## Doğrulama

- BADE ve EMU için ayrı ayrı **342 JVM testi**, 0 hata/atlanan.
- BADE lint: **0 hata**, 77 uyarı ve 18 bilgi (1.14.112 ile aynı sayılar).
- BADE emülatörde **4 pencere testi** başarılı; yeni MTE ekranının liste yükleme hatasında baskıyı engellemesi, yenileme ve devam düğmeleri dahil.
- İmzalı BADE APK'nın applicationId, sürüm kodu ve sertifikası doğrulandı; sertifika 1.14.112 ile aynı. Emülatörde 1.14.98 üzerine veri silmeden kurulum başarılı oldu.

Bu özellik mevcut BC `licensePlates/printPalletLabels` işlemini ve ZPL MTE şablonunu kullanır. Bu sürüm için AL veya Windows Print Agent değişikliği yoktur. Sand0309'da Azure yazıcı bağlantısı ve etiket yazıcısı eşleştirmesi kurulmuş olmalıdır.

Fiziksel yazıcıda ve gerçek BC mal kabul işleminde uçtan uca test yapılmadı. Bu paket BADE içindir.
