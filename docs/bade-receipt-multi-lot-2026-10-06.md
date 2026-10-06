# Tek mal kabul belgesinde birden fazla lot

Aynı ürünün 400 adedi A102370, 600 adedi A102371 lotuyla geldiğinde terminal tüm LP'leri ortak lota zorladığı için iki ayrı kayıt yapılması gerekiyordu. Düzeltme, tek satın alma/ambar mal kabul satırında miktarı lot gruplarına ayırır; kaydetme işlemi belge başına bir kez yapılır.

## Kullanım

1. Mal kabul belgesinde **Palet LP** ekranını açın ve toplam kabul miktarını girin.
2. İlk lot grubunun iç lotunu, tedarikçi lotunu ve gerekiyorsa SKT bilgisini girin.
3. **Lot Grubu Ekle** ile diğer lotları ekleyin. İç lot boş bırakılırsa her grup için ayrı numara üretilir; aynı gruptaki LP'ler bu numarayı paylaşır.
4. LP miktarlarını girip her LP'nin lot grubunu seçin. Örnekte ilk grup 400, ikinci grup 600 adet olmalıdır. Bir lot grubu birden fazla LP içerebilir.
5. LP taslaklarını hazırlayın. Satıra tekrar dokunarak lot, tedarikçi lotu ve LP miktarlarını kontrol edin.
6. **Mal Kabulü Kaydet** ile tüm grupları birlikte kaydedin.

Aynı kaynak satın alma belgesindeki lotlar ayrı takip/defter girişleri olarak korunur. Birden fazla kaynak satın alma belgesi içeren ambar mal kabullerinde standart BC'nin kaynak belge kuralları değişmez.

## Uygulama

- `createBulkLPDistribution` mevcut sözleşmedeki `groupId` değerini kullanır. Eksik grup kimliği eski ortak lot davranışını korur.
- LP başlığındaki 128–130 alanları, lot ve SKT bilgisini boş taslakta saklar. Ürün/miktar satırları kayıt işlemine kadar oluşturulmaz.
- Kayıt öncesinde her LP kendi takip bilgisiyle doldurulur; miktarlar lot/seri bazında toplanarak standart rezervasyon kayıtlarına yazılır. Satın alma veya mal kabul kaynak satırı bölünmez.
- Yeniden gönderilen eski tek lotlu satır onayı, hazırlanmış dağılımı ilk lota indirgeyemez. Farklı toplam veya takip bilgisi reddedilir.
- `receiptLpAllocations` alanı hazırlanmış dağılımı yeniden açılan terminal ekranına taşır. Bu alanı sunmayan eski BC paketlerinde ortak lot girişi kullanılabilir; yeni lot grubu ekleme gösterilmez.
- Pozitif miktar, açık miktar sınırı, toplam eşitliği, 200 LP sınırı, SKT ve aynı iç lot için tedarikçi lotu/SKT tutarlılığı kontrol edilir.
- İptalde taslak lot bilgileri temizlenir. Kayıttan dışlanan satırın taslakları korunur.

## Doğrulama ve yayın durumu

- Android: 473 birim testi ve 3 emülatör arayüz testi geçti. Arayüz testleri 400 + 600 dağılımının tek gönderimini, yeniden açılan planı ve eski sunucu uyumluluğunu kapsar; canlı BC çağrısı yapmaz.
- Android debug APK derlemesi başarılı. Lint: 0 hata, 77 uyarı.
- Değişen AL dosyaları Microsoft AL söz dizimi ayrıştırıcısıyla kontrol edildi: 0 söz dizimi hatası. Bu kontrol paket derlemesi veya çalışma zamanı testi değildir.
- BC: altı AL regresyon testi eklendi. Lot bazında rezervasyon/LP miktarları, otomatik lot grupları, ortak lot uyumluluğu, çelişen tedarikçi lotu, miktar uyuşmazlığı ve dışlama/iptal davranışı kapsanır.
- BCWMSApp **1.14.1.125**, genel AL test paketi ve yazıcı test paketi [GitHub Windows derlemesinde](https://github.com/DynOpsBC/WMS/actions/runs/37451750721) başarıyla derlendi. AL testleri BC ortamında çalıştırılmadı; gerçek mal kabul kaydı, defter girişleri, yerleştirme ve etiketler için sandbox doğrulaması gereklidir.
- Yayın sürümleri: BADE Android **1.14.169** (200169), BCWMSApp **1.14.1.125**. Release APK önceki BADE paketiyle aynı sertifikayı kullanır. Çoklu lot için BC paketi ayrıca yüklenmelidir; GitHub yayını canlı BC kurulumu yapmaz.

Yerel doğrulama çıktıları: `build/receipt-multi-lot-20261006/` ve `build/bade-release-1.14.169-publication/`.
