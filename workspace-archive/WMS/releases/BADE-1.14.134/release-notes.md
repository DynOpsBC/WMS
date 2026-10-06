BADE Android **1.14.134-bade** (versionCode **200134**).

- MTE ekranında Giriş Yapan seçilmezse, etiket yazıcısına aktif PIN kullanıcısının adı gönderilir. LP'yi oluşturan servis hesabı adı bu boş seçimin yerine kullanılmaz.
- Elle seçilen çalışan önceliklidir. Diğer alanları boş bırakıp yazdırma işlemi de PIN kullanıcısını kullanır; kalite kontrol onayı otomatik doldurulmaz.
- Çalışan eşleştirmesi yalnızca aktif şirketin listesinden yapılır. Oturum bitmişse veya şirket değişmişse yazdırma durdurulur.
- PDF MTE raporu gerçek çalışan numarası gerektirir. PIN kullanıcısının adı o şirkette tek bir çalışanla eşleşiyorsa otomatik kullanılır; eşleşme yoksa veya belirsizse Giriş Yapan seçimi istenir. Bu, yanlış kişi veya servis hesabı ile çıktı verilmesini önler.
- BADE'de ek bilgileri kaybeden eski MTE aksiyonuna otomatik dönüş kapatıldı.

Bu düzeltme mevcut BCWMS etiket servisinin desteklediği isim alanını kullanır; yeni BC uzantısı gerekmez. EMU davranışı ve güncelleme kanalı değişmez. Production erişimi ve yönetici kısıtlamaları korunur.

Doğrulama: 386 BADE + 369 EMU birim testi, emülatörde 3 PIN oturumu/şirket ayrımı testi, BADE lint ve imzalı APK derlemesi. Fiziksel etiket baskısı yapılmadı; yüklemeden sonra boş ve elle seçilmiş Giriş Yapan alanlarıyla birer etiketi kontrol edin.
