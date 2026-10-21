EMU 1.14.165 — Excel seçmeden hazır göz listesi

Etiket Çıkar → Ürün Etiketi → **Hazır göz listesi — 1.535 etiket**. 15.10.2026 tarihli liste BC’den açılır; Excel dosyası seçmek veya terminale kopyalamak gerekmez. Önizlemeyi kontrol edip **Tümünü yazdır (1535)** düğmesine basın.

1.535 satır ve 1.227 ürünün sırası, gözleri ve tekrarları korunur. Her satır bir etikettir; stok miktarı kopya sayısına çevrilmez. Hazır liste eksik, farklı tarihte veya değiştirilmişse baskı başlamaz. Önceki Excel seçme ve bütün BC ürünlerini basma seçenekleri kullanılabilir.

BCWMSApp 1.14.2.25 gerekir. Hazır liste BC şirketine ait özel veridir; ürün/göz satırları APK, kaynak yaması veya GitHub yayınına gömülmez. API yalnız okumaya açıktır; listeyi değiştirme yetkisi WMS yöneticisindedir.

Doğrulama: 414 Android birim testi, 4 emülatör testi, lint, standart ve tarihsel imzalı release derlemeleri; Sandbox1510’da 7 AL testi. Sandbox’taki 1.535 kayıt geri okunup orijinal listeyle birebir karşılaştırıldı. Gerçek yazıcıya test işi gönderilmedi.

Paket kimliği com.dynops.bcwms.emu; versionCode 200165. RELEASE standart imzalı, UYUMLU tarihsel imzalı terminaller içindir. Uygulamayı kaldırmadan güncelleyin. Kaynak: customer/emu 56d722a76e0b5b16ce324bbb4515b00a0ddedfec + emu165-source.patch.

Kurulum doğrulaması: DKÇ Production ve Sandbox1510 üzerinde BCWMSApp 1.14.2.25 ve 1.535 satırlık hazır liste kuruldu. İki ortamdaki liste geri okunarak kaynakla birebir karşılaştırıldı. Canlıda 16 iş kuyruğu eski etkin durumuna döndürüldü.
