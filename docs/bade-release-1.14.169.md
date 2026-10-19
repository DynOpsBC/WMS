BADE Android **1.14.169** / BCWMSApp **1.14.1.125**

Aynı mal kabul satırındaki 400 ve 600 adetlik ürünleri farklı iç lot ve tedarikçi lotlarıyla hazırlamak için iki ayrı mal kabul kaydı yapılması gerekiyordu. Yeni sürümde **Palet LP → Lot Grubu Ekle** ile lot grupları oluşturulabilir; bütün gruplar aynı mal kabul işlemiyle kaydedilir. Her LP kendi lotunu ve miktarını korur.

- Aynı lot grubunda birden fazla LP kullanılabilir. İç lot boş bırakılırsa her grup için ayrı lot numarası üretilir.
- Hazırlanan satır yeniden açıldığında LP, miktar, iç lot ve tedarikçi lotu dağılımı gösterilir.
- Toplam miktar, açık miktar, SKT ve aynı iç lot için çelişen tedarikçi lotu kontrolleri korunur.
- Eski tek lotlu satır onayının çoklu lot dağılımını ilk lota indirmesi önlenir.

**Kurulum:** Çoklu lot özelliği için **BCWMSApp 1.14.1.125** ve **Android 1.14.169** birlikte gereklidir. BC paketi eskiyse terminal ortak lot akışını korur ve yeni lot grubu ekleme açılmaz. BC ZIP dosyasını açıp içindeki `.app` dosyasını BC Uzantı Yönetimi üzerinden yükleyin; ardından terminalde güncellemeyi yükleyin. GitHub yayını BC ortamına kendiliğinden kurulum yapmaz.

Doğrulama: 473 Android birim testi ve 3 emülatör arayüz testi geçti. İmzalı release APK'nın paket kimliği, 200169 sürüm kodu ve önceki BADE sürümüyle aynı sertifikası doğrulandı. BC uzantısı ve test paketleri GitHub'ın Windows derleyicisinde derlendi. AL testleri BC ortamında çalıştırılmadı; gerçek mal kabul kaydı, defter girişleri, yerleştirme ve etiketler için sandbox kontrolü gerekir.
