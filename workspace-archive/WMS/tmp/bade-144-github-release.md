BADE 1.14.144 — test adayı

Mevcut LP'ye ürün eklerken doğru stok girişini açıkça seçip kaynak belge bağlantısını kaydetme ve etiket basımında PIN kullanıcısını iletme düzeltmelerini içerir.

- APK: 1.14.144-bade (200144), com.dynops.bcwms.bade; önceki BADE imzasıyla imzalı.
- Eşleşen BC paketi: 1.14.1.62 (BCWMS-BADE-BC-1.14.1.62-TEST-ADAYI.zip içinde). Yeni kaynak seçim API'si için test ortamında önce BC paketi, sonra APK kurulmalı.
- Eski LP kaynaklarını tahmin ederek otomatik bağlamaz; doğru giriş açıkça seçilir. Kaynak onarımı stok miktarını, rafı ve mevcut SKT'yi değiştirmez.
- 407 Android testi başarılı, lint hatası yok. Üretim/test AL paketleri Windows'ta derlendi: https://github.com/DynOpsBC/WMS/actions/runs/35585781152

**Canlıya geçiş onayı değildir.** BADE sandbox içinde AL testleri, gerçek kullanıcı izinleri, 150+850 LP örneği ve müşteri PDF 60150/PIN çalışan eşleşmesi henüz doğrulanmadı. Kurulu BC veri sürümüne bağlı mevcut yükseltme işlemleri ayrıca kontrol edilmeli. Ayrıntılar CANLI-ONCESI-INCELEME.md ve DOGRULAMA.txt dosyalarındadır.

1.14.143 / BC 1.14.1.61 kullanılmamalı. Bu yayın pre-release olarak sunulmuştur; terminalin kararlı otomatik güncelleme kanalı değiştirilmemiştir.

Kaynak notu: AL paketi 211e468170136c61a18890144b2683d59d1a28f5 commitinden derlendi. APK'nın bu committen sonraki küçük kaynak/test değişiklikleri ve inceleme notu son-kaynak-degisiklikleri.patch dosyasında verilmiştir; 407 test sonucu bu son kaynaklar içindir.
