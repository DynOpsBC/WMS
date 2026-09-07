# Sayım V2 raf tamamlama ve fark incelemesi

Android 1.14.102 / versionCode 200102 ve BC kaynak sürümü 1.14.1.30 birlikte gerekir.

## Davranış

- Raf açıldığında BC stokları sayım satırlarına eklenir; henüz sayılmayan satırların sayıldı bayrağı kapalıdır.
- **Rafı bitir** onayında yalnız o raftaki henüz sayılmamış satırlar, seçili sayıcının turunda açıkça 0 sayılır. Girilmiş miktarlar ve diğer sayıcıların değerleri korunur. Tekrar denemek satır veya miktar çoğaltmaz.
- Sayılan miktar kayıtlı miktarı aşıyorsa aynı ürün, varyant, lot, seri ve birimde stok bulunan diğer raflar sayılmayı bekleyen satırlarla kapsama alınır. Diğer raf otomatik sıfırlanmaz ve stoktan düşülmez.
- Diğer rafın bütün bekleyen satırları tamamlanmadan tur kaydı ve stoklara işleme sunucuda engellenir. İlgili raf belge alan filtresinin dışındaysa işlem durur; iki rafı da kapsayan sayım gerekir.
- Raf farkları ürün, varyant, lot, seri ve birim bazında birlikte gösterilir. Toplamın sıfır olması yalnız **olası raf farkı** olarak adlandırılır; otomatik transfer yapılmaz.
- Diğer rafta bulunan lotun sistem miktarı, fiziksel sayım miktarı olarak kopyalanmaz; operatör bulduğu miktarı girer.
- Terminal stoklara işleme yetkisi mevcut BC ayarına bağlıdır. Yetkili terminalde son onay penceresi farkları gösterir. BC sayım kartında da raf farkları inceleme sayfası açılır ve ardından ayrı stok işleme onayı istenir.
- LP satırları ve kalan paletsiz stok ayrı miktarlarla hazırlanır. Yanlış raftaki LP okutmasına ilişkin mevcut engel korunur; bu değişiklik LP taşıma akışı oluşturmaz.
- Sayım sırasında stok miktarı veya LP dağılımı değişirse mevcut sistem miktarı sessizce yenilenmez; uyumsuz sayımın işlenmesi durdurulur.
- Eski BC paketinde `binReviewSupported` bulunmaz; yeni Android raf tamamlama ve tur kaydını güncelleme mesajıyla engeller.

## Sandbox kabul testi

1. A1 rafına X ve Z, A2 rafına E ürünü için 5 adet stok hazırlayın.
2. Yeni V2 sayımında A1 açın; X sayın, Z saymayın ve A1 üzerinde E ürününden fiziksel olarak bulunan 5 adedi girin.
3. A1 için **Rafı bitir** onaylayın. X miktarı korunmalı; Z yalnız mevcut sayıcıda açıkça 0 olmalı; A2 satırları **henüz sayılmadı** görünmeli.
4. Bu noktada tur kaydı reddedilmeli; madde defter girişleri ve ambar hareketleri değişmemeli.
5. A2 gerçekten boşsa **Rafı bitir** ile E miktarını 0 onaylayın. İncelemede A1 +5, A2 −5, toplam 0 ve olası raf farkı görünmeli.
6. Ayrı bir sayımda A2 üzerinde E hâlâ 5 ise A2 miktarını 5 sayın. İncelemede toplam +5 görünmeli; otomatik düşüm yapılmamalı.
7. Farklı lot, seri, varyant veya birim kayıtlarının birbirini mahsup etmediğini doğrulayın.
8. Atanmış tüm sayıcı turlarını kaydedin. BC inceleme ve onay adımından sonra fiziksel stok düzeltmelerini kontrol edin; onaydan önce stok değişmemeli.

## Doğrulama sınırı

Android birim testleri ve derleme yerelde çalıştırılır; sonuçlar `build/count-bin-review/` altında saklanır. AL regresyon testleri `al-tests/src/Count/CountV2Tests.Codeunit.al` içine eklenmiştir.

AL derlemesi ve sandbox testleri bu macOS ortamında çalıştırılmadı. `CLAUDE.md` Windows AL araçlarını gerektirir; mevcut GitHub AL paketleme işi yalnız placeholder içerir. Windows üzerinde uygulama ve test paketlerini derleyip sayım testlerini çalıştırmadan BC 1.14.1.30 paketini dağıtmayın. Mevcut çeviri denetimi de kaynak ile tr/de dosyaları arasında önceden var olan kapsama uyarıları veriyor.

Canlı BC ortamına veya Android kararlı güncelleme kanalına bu çalışma kapsamında dağıtım yapılmadı.
