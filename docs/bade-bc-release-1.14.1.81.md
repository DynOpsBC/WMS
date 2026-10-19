# BADE BCWMSApp 1.14.1.81

Depo Gözü İçeriği sayfasında 1.14.1.80 ile eklenen ana içerik ListPart'ı kaldırıldı. Gizli olduğunda bile alan ayırıp stok listesini aşağı iten bölümün yerine Seçenekler altında kısa LP bilgileri gösterilir.

Yeni **LP Raf İçeriği** eylemi, aktif ve pozitif miktarlı LP satırlarını doğrudan listeler. Konum ve raf LP başlığından okunur; listeye girmek için Bin Content veya kaynak madde defter girişi bulunması gerekmez. LP numarası, ürün, lot ve kaynak giriş alanları listede yer alır. BC raf satırı varlığı ve aynı stok satırının toplam miktarı ayrı gösterilir. Bu toplam birden fazla LP satırında tekrarlanabilir.

LP No. Filtresi girilmişken stok listesi yalnız eşleşen stok satırlarını gösterir. Eşleşme bulunmadığında ilgisiz stok satırlarına geri dönülmez; LP bilgisi Seçenekler alanında kalır. LP numarası kartı, LP içeriği bağlantısı yeni LP satır listesini açar. Ana stok listesine yapay stok satırı eklenmez.

**Eksik Kaynakları Toplu Bağla** algoritması değiştirilmedi; açıklaması ayrıntılandırıldı. Kaynağı boş olan aktif, pozitif LP satırlarında ürün, varyant, lot, seri ve lokasyon birebir eşleştirilir. Varsa kaynak belgeyle daraltılır; dolu SKT'ler çelişemez. Pozitif/kalan miktarlı tek giriş ve yeterli ayrılabilir temel miktar gerekir. Birden fazla aday otomatik seçilmez. Mevcut bağlantılar değiştirilmez; raf veya stok miktarı yazılmaz.

Doğrulama: ana AL paketi ve AL test uygulaması hatasız derlendi; git diff --check geçti. Stok satırı/kaynak bağlantısı olmayan LP, üretim rafına taşınmış LP ve kullanılan/sıfır miktarlı LP filtreleri için üç TestPage testi eklendi. Bu testler BC çalışma zamanında çalıştırılmadı. Canlı kurulum veya ekran doğrulaması yapılmadı. APK değişmedi.
