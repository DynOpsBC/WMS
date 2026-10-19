# BADE sayım akışı — ek hata taraması

Kaynak sürümü: **BC 1.14.1.127**. Bu kayıt statik incelemeyi ve eklenen test senaryolarını açıklar; BC çalışma zamanı test sonucu değildir.

## Kapatılan riskler

1. **Arşivleme / stoklara işleme geçişi:** Başlık koruması kayıtlı durumdan karar verir; ilk geçiş ile kapalı belgeyi yeniden değiştirme birbirinden ayrılır. Son stok kaydı artık tablo tetikleyicisini atlamaz. Silme ve yeniden adlandırma da kayıtlı tur bağlantılarını kilit altında denetler.
2. **Kaydedilmemiş sayım:** Kart, yeni tur onayından önce satırların ve sayıcıların tamamlandığını kontrol eder. Aynı kontrol yeni tur oluşturulurken başlık kilidi altında tekrarlanır. Mesaj operatörü terminaldeki **Sayım Turunu Kaydet** eylemine yönlendirir.
3. **Geçmişi başka belgeye taşıma:** Satır ve sayıcı kayıtları başka sayım turuna yeniden adlandırılamaz. Okutma kaydının belge veya işlem kimliği değiştirilemez. Arşivlenmiş/işlenmiş turun okutma kayıtları değiştirilemez veya silinemez. Geri alma ve yeniden sayım işlemleri bu korumalardan geçer.
4. **Yarım stok kaydı:** `Item Jnl.-Post Batch.SetSuppressCommit(true)` kullanılarak stok günlüğü, LP güncellemesi ve sayım başlığının kapanışı arasındaki ara commit engellenir. Metodun varlığı yerel Microsoft Base Application 28.1 sembollerinden doğrulandı. Gerçek stok farkı ve sonradan oluşan hata ile işlem geri alma testi BC'de yapılmalıdır.
5. **Tamamlanamayan boş yeni tur:** Ad-hoc sonrasında eski kapsamda hiç güncel stok satırı kalmazsa boş alt tur bırakılmaz; işlem açıklamalı hata ile geri alınır, ilk tur korunur.
6. **Elle kapalı durum verme:** Kart ve liste üzerinden `Status` elle değiştirilemez. Operatör stoklara işleme eylemini kullanır.

Önceki düzeltme ayrıca filtreli eski karttan yeni kart açmayı, eski tur eylemlerinin görünürlüğünü ve üçüncü/sonraki tura ulaşmayı kapsar. Android kaynakları ve yayın kanalı bu taramada değiştirilmedi.

Ek saha bildirimi: **Sonraki Tura Geç** düğmesi sonraki tur bağlantısı boşken sessizce çıkıyordu. Yeni sürümde bu durumda düğme görünmez; eski ekran durumu nedeniyle eylem yine de çağrılırsa yeni turun henüz oluşmadığını ve hangi adımın gerektiğini açıklayan mesaj verilir. Başarısız tur oluşturma sonrasında bu düğmenin görünmemesi de kart testine eklendi.

## Eklenen altı regresyon senaryosu

| Senaryo | Beklenti |
| --- | --- |
| Kaydetmemiş sayıcıyla BC'den yeni tur | Onay penceresinden önce açıklamalı ret; arşivleme yok |
| Yeni tur onayını iptal etme | İlk belge etkin kalır; yeni belge oluşmaz |
| Ad-hoc sonrasında kapsamın tamamen boşalması | Yeni belge ve arşiv bağlantısı geri alınır |
| Eski satır/sayıcı/okutmayı etkin tura taşıma | Geçmiş değişmeden işlem reddedilir |
| Bellekte bağlantısı silinmiş eski belgeyi silme/adlandırma | Veritabanındaki bağlantı esas alınır, geçmiş korunur |
| İlk turdan üçüncü turu açma ve eski isteği yineleme | Mevcut son tur açılır; dördüncü tur oluşmaz |

Bu altı senaryo ile önceki iki kart testi **henüz BC'de çalıştırılmadı**. İlk tur sonucu, yeni stok görüntüsü, idempotent başlatma ve stoklara işleme engelleri için önceki AL testleri de paket içinde bulunur. Yeni tur test verisi, ilk sayım kaydedildikten sonra tamamlanmış Ad-hoc hareketini taklit edecek şekilde düzeltildi.

## Kontrol sonucu ve tamamlanması gerekenler

- Değişen AL dosyaları ve test dosyası Microsoft AL ayrıştırıcısında **0 söz dizimi hatası** verdi.
- `git diff --check` başarılı.
- Android için önceki 477 + 2 test sonucu bu AL değişikliklerini doğrulamaz.
- **Windows paket/test paketi derlemesi yapılmadı. BC çalışma zamanı testleri yapılmadı. Canlıya yayınlanmadı.**
- Windows iş akışı `.github/workflows/al-package-verified.yml` kaynaktan uygulama ve test paketlerini derler; BC testlerini çalıştırmaz. Güncel kaynağı alabilmesi için ayrı dalda commit/push gerekir. `CLAUDE.md`, açık kullanıcı talebi olmadan commit yapılmasını yasaklar.
- BC'de ek olarak gerçek stok farkıyla başarılı kayıt, aynı kaydı tekrar deneme, kayıt ortasında hata/geri alma ve eşzamanlı iki istemcinin yeni tur isteği doğrulanmalıdır.

Söz dizimi günlüğü: `build/bade-count-audit-20261007/al-syntax.log`.
