## BADE BCWMSApp 1.14.1.90 — LP / raf stok mutabakatı

Bu sürüm, `Depo Gözü İçeriği` sayfasındaki seçili göz için **LP / Raf Stok Mutabakatı (CSV)** eylemini ekler. Rapor aynı madde, varyant, lot ve seri için aktif LP'lerin toplam temel miktarını kayıtlı ambar miktarıyla karşılaştırır. LP satırının kaynak depo gözü ve kaynak madde defter girişi de raporda yer alır.

LP kartı, liste, bilgi kutuları ve API üzerinden LP'nin rafının, konumunun, durumunun veya satırlarının doğrudan değiştirilmesi kısıtlandı. Terminalin kayıtlı LP taşıma ve diğer işlem eylemleri korunur. Boş LP için ilk raf ataması API'de mümkündür.

**Bu paket stok hareketi veya düzeltmesi yapmaz.** `Güncel LP Miktarı` LP satırlarından, BC raf miktarı ambar girişlerinden gelir. İki sayı arasındaki fark otomatik olarak yeni stok eklenmesi gerektiği anlamına gelmez. `LP000421` için daha önce önerilen tekil raf hareketi, diğer LP'lerin aynı stoğu talep edip etmediği kontrol edilmeden uygulanmamalıdır. `LP000436`, `LP000445` ve `LP000448` için de rapor incelenmelidir.

**Doğrulama:** Ana BC uygulaması ve AL test uygulaması hatasız derlendi; testler BC ortamında çalıştırılmadı. Production kurulumu ve uçtan uca akış doğrulanmadı. Bu paket bir inceleme adayıdır.

Kaynak commit: `17263af` (`customer/bade`).
