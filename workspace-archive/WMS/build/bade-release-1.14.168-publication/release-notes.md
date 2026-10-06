BADE Android **1.14.168** / BCWMSApp **1.14.1.124**

- **Mal kabul:** “Yazdırmadan kaydet” seçiliyken boş yazıcı alanının kaydı engellemesi düzeltildi. Normal yazdırmada yazıcı seçimi kontrolü korunur.
- **Sayım:** farklı rafta okutulan LP'nin kaynak rafı ve aynı ürün/lotun diğer rafları otomatik sayıma eklenmez. Seçilen rafların stok kontrolleri ve LP'nin eski raf bilgisi korunur.
- Önceki sayım belgelerindeki satırlar otomatik silinmez; güncelleme sonrası yeni belgeyle sayım yapılmalıdır.

Kurulum: Android 1.14.168 terminal güncelleme kanalından veya APK ile kurulabilir. Sayım düzeltmesi için BCWMSApp 1.14.1.124 ayrıca BC Uzantı Yönetimi üzerinden yüklenmelidir. Bu GitHub yayını BC ortamına veya cihazlara kendiliğinden kurulum yapmaz.

Doğrulama: 468 Android birim testi geçti (0 hata, 0 başarısız, 0 atlanan). Release APK derlendi; paket kimliği, 200168 sürüm kodu ve önceki BADE sürümüyle aynı imza sertifikası doğrulandı. BC uzantısı ve AL test paketi derlendi. BC üzerinde AL testleri ve gerçek mal kabul/sayım uçtan uca testi henüz çalıştırılmadı.

BC dosyası GitHub uzantı kısıtı nedeniyle ZIP içindedir. ZIP dosyasını açıp içindeki BCWMSApp-1.14.1.124.app dosyasını BC Uzantı Yönetimi üzerinden yükleyin.
