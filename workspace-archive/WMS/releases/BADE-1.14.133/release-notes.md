BADE Android **1.14.133-bade** (versionCode **200133**).

- BADE uygulamasında Production ortamının otomatik bulunmasını ve elle seçilmesini engelleyen derleme ayarı açıldı.
- Varsayılan ortam E-DefterSandbox olarak kalır; Production'a geçiş ortam seçiminden yapılır.
- Production'da Mal Kabul, Yerleştirme, Sevkiyat, Paketleme, Toplama ve Üretim için Yönetici erişimi zorunluluğu korunur.
- İlk seçimden sonra terminal değiştirmek için Yönetici yetkisi ve doğru PIN gereklidir.
- Değişiklik yalnızca BADE sürümündedir. EMU yayını ve güncelleme kanalı değiştirilmez.

Doğrulama: BADE birim testleri, lint ve imzalı release derlemesi. Production'ın keşif listesinde bulunması ve Sandbox varsayılanının korunması için regresyon testi eklendi. Canlı BC verilerinde işlem yapılmadı; fiziksel yazıcı testi bu yayın kontrolünün kapsamında değildir.

Mevcut BADE uygulamasındaki **Uygulamayı güncelle** seçeneğiyle yükleyebilirsiniz. Sonrasında ortam seçiminde **Production** seçilmelidir.
