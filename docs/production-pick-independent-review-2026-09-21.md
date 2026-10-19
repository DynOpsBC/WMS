> tarihsel çalışma notu: bu dosya 21 eylül tarihindeki sürüm ve inceleme durumunu korur. güncel sürüm için [apk 155 / al 68 notlarına](bade-source-repair-and-delivery-1.14.155.md) bakın.

# Hazır LP ile üretim çekmesi — bağımsız inceleme

21 Eylül 2026. Bu inceleme sırasında aynı çalışma klasöründe başka bir yürütme dosyaları değiştirip Android derlemesi başlattı. Bu oturum uygulama kaynaklarına müdahale etmedi; aşağıdaki bulgular devam eden değişikliklerin anlık durumuna aittir. Canlı stok/çekme kaydı, APK yayını veya BC kurulumu yapılmadı. Kod incelemesi, BC üzerinde çalıştırılmış uçtan uca test yerine geçmez.

## Tamamlanmadan çözülmüş sayılmaması gereken noktalar

1. **Aynı bileşenin farklı raflardan alınan satırları yanlış Yer satırına bağlanıyor.** `al/src/Pick/PickMgmt.Codeunit.al` içindeki `SyncRelatedPlaceLine` ve `FindRelatedPlaceLineForShippingLp`, kaynak anahtarları ve izleme filtrelerinden sonra `FindFirst` kullanıyor. PI001949 örneğinde AB.00090 için 1200 ve 6800 miktarlı iki Al satırı, aynı lotta/boş lotta ilk Yer satırını seçebilir. `SyncRelatedShortPlaceLine` ise eşleşen bütün Yer satırlarını değiştiriyor. Ortak eşleştirme yordamı kaynak kimliği, değişiklik öncesi temel miktar, izleme bilgisi ve BC satır sırasını dikkate almalı; belirsiz eşleşmede kayıt reddedilmeli. Sadece bitişik satırı almak yeterli değil: standart BC bir Al satırı için birden fazla Yer satırı üretebilir.

2. **LP başka rafta hazırlandıysa mevcut çekme hâlâ eski rafı istiyor.** Yeni `ProdMgmt.ValidateProductionLpPick`, mevcut çekmeyi tekrar kullanırken LP rafıyla Al rafının birebir aynı olmasını istiyor. Bu doğrulamayı kaldırmak çözüm değildir. Hiç işlenmemiş çekme için açık bir yeniden planlama akışı veya kaynak raf değişmeden hazırlanmış LP akışı gerekir; aksi halde PI001949'un eski raf bilgisi engeli sürer. İşlenmiş miktarlar ve başka operatör sahipliği korunmalı.

3. **Hazır LP seçimi, boş lotlu çekme satırına taşınmıyor.** `LPPickPreference.StampProductionPickLines` LP satırını çekmenin lot/seri değerlerine tam eşitlikle filtreliyor. Çekme lotu boş, LP lotu doluysa seçilen LP damgalanmıyor. Android `buildPalletPickPlan` ayrıca tercih edilen LP'yi sıralamadan önce bütün adayların tek lot olmasını istiyor. Aynı rafta iki lot bulunduğunda hazırlanmış LP açıkça seçilmiş olsa bile işlem duruyor. Açık LP seçimi ile kaynak belgede önceden belirlenmiş lot kısıtını ayırmak; lotlar arası karışımı reddetmek gerekiyor.

4. **Toplanacak miktar seçilen LP miktarından başlamıyor.** `PalletPickSheet` miktarı `group.totalOutstanding` ile başlatıyor. Hazır LP 4, üretim ihtiyacı 10 ise plan başka LP de isteyebilir veya stok eksik hatası verir. Hazır LP akışı seçilen LP'nin içerik miktarını ve uygun bileşen satırlarını açıkça taşımalı; üretim ihtiyacının kalanı açık kalmalı. Çok ürünlü LP'nin tamamı bir üretim emri ve hedef rafa doğrulanmalı.

5. **Yeni çekme oluşturma sırasında kilitler korunmuyor.** Yerel Microsoft Base Application 28.1 paketindeki `ProductionOrder.Table.al` `CreatePick` yordamı açık `Commit()` içeriyor. Dolayısıyla yeni `CreateProductionPickInternal` başındaki emir/LP kilitleri bütün işlem boyunca tutulmuş sayılmaz. Standart çağrı sonrası LP, içerik, bileşen ve oluşan çekme yeniden okunup doğrulanmalı. TryFunction otomatik geri alma garantisi vermez. Bu bulgu tek başına çağrının mutlaka hata vereceği anlamına gelmez.

6. **Eski BC sürümünde yeni üretim davranışı varmış gibi kayıt gönderilebilir.** `BcApi.kt` üretim için `registerScannedFor` varlığını yeterli görüyor; bu servis önceki BC 1.14.1.62 paketinde de vardı. Yeni üretim LP koruması ayrı bir servis/yetenek bilgisiyle doğrulanmalı. Eski pakete üretim kaydı gönderilmemesi için Android testi gerekli.

7. **Mevcut tam miktarlı belgede tek hazır LP kapsamı açık değil.** Eski çekme tekrar kullanıldığında diğer Al satırlarının `Qty. to Handle` değerleri dolu kalıyor; tam belge doğrulaması bunların da okutulmasını istiyor. Satır miktarına 0 girilebiliyor fakat her ilgisiz satırı elle temizlemek gerekiyor. Açık kullanıcı seçimiyle yalnız seçilen LP kapsamını hazırlayan, başka operatörün çalışmasını silmeyen bir işlem gerekli. Multi toplama modu ayrıca bütün satırları tamamlamayı şart koşuyor; üretimde kısmi hazır LP kaydı hem istemcide hem sunucuda tutarlı ele alınmalı.

## İyi yönde olan değişiklik

Yeni `PrepareProductionPallets` / `StageProductionPickLp`, LP içeriğini ürün-varyant-lot-seri bazında doğrulayıp LP kimliğini koruyarak üretim emrine (`ProdConsumption`) bağlıyor. Fiziksel raf hareketi standart ambar çekme kaydında kalıyor. Bu yaklaşım, üretim LP'sini kapanmış çekme belgesine atayan önceki sevkiyat yoluna göre doğru yönde. Ancak yukarıdaki akış engellerini tek başına çözmüyor.

## Çekmeden sonraki ayrı sorun

Mevcut `ProdMgmt.Consume` LP verildiğinde istenen miktarı tüm LP ürün miktarıyla değiştiriyor; `ResolveLpQuantity` farklı lot miktarlarını ilk lotla birleştirebiliyor. Üretim tüketiminin LP içeriğini doğru azaltması ayrıca doğrulanmalı. Çekme düzeltmesi bu tüketim davranışını da çözmüş gibi anlatılmamalı.

## Gerekli doğrulama

- Aynı bileşen/lot için 1200 + 6800 Al/Yer çifti; ilk, ikinci ve kısmi satır onaylarında karşı satır korunmalı.
- Aynı ürün, farklı lotlar; boş lotlu çekmede açık seçilen LP'nin lotu korunmalı.
- İhtiyaç 10, hazır LP 4; yalnız 4 taşınmalı, 6 ihtiyaç açık kalmalı.
- Bir LP'de iki bileşen; tamamı aynı emir ve üretim rafına taşınmalı, LP numarası/içeriği bozulmamalı.
- LP hazırlama sırasında raf değişmesi ve eşzamanlı başka operatör/emir talebi; eski plan kabul edilmemeli.
- Standart BC kayıt hatasında LP rafı/ataması ve miktarlar birlikte geri alınmalı.
- PI001949 benzeri önceden tam miktarlı oluşturulmuş belgede yalnız seçilen LP'yi toplama; diğer satırlar kendiliğinden kaydedilmemeli.

İncelenen standart davranışın kaynağı: yerel `al/.alpackages/Microsoft_Base Application_28.1.49838.51713.app` içindeki `WarehouseActivityLine.Table.al` (`CopyItemTrackingToRelatedLine`), `CreatePick.Codeunit.al` ve `ProductionOrder.Table.al`.
