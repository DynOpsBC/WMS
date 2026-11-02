# BADE satın alma iadesi LP düzeltmesi — 1.14.1.161

Sand2809 / BS İlaç Kozmetik San.Tic.A.Ş. üzerinde doğrulandı. Production yüklemesi yapılmadı.

## Bulgu

LP000874 ve LP000875, MERKEZDEPO / S.K01.11 gözünde 400'er adet AB.00067 / A102400 içerikle Assigned kalmıştı. 105040 ve 105041 satın alma iade sevkleri stoktan 400'er adet düşmüş, ambar girişleri 50162 / 50167 ile madde girişleri 13548 / 13549 LP'siz kalmıştı. Kayıtlı ambar sevkleri S_000832 / S_000833, kaynak ambar sevkleri SH000999 / SH001000.

Mevcut resyncPostedShipment çağrısı her iki kaydı da bulup birer LP düzeltti; kayıt bulma ve göz bakiyesi hesabı bu örneklerde çalışıyor. Eksik olan, bu adımın terminal Shipment Mgmt sarmalayıcısının dışındaki BC sevk kayıt zincirinde çağrılmasıydı. Eski kodda StampPostedReturnShipmentLps ve SyncPostedWhseShipment yalnız terminal sarmalayıcısı ve elle onarım tarafından çağrılıyordu. Geçmiş işlemin hangi istemciden başlatıldığına dair oturum izi alınmadı.

## Değişiklik

Whse.-Post Shipment.OnAfterPostWhseJnlLines olayında satın alma iadesi kontrol edilir. Takip bölümlerinin tamamı kaydedildikten sonra kayıtlı toplama üzerinden LP ambar/madde girişlerine yazılır ve göz stokunu aşan LP miktarı düşülür. TerminalPosting bayrağı bu sonlandırmayı engellemez; terminalin sonradan aynı mutabakatı çalıştırması çift düşüm oluşturmaz. Genel ambar günlüğü dinleyicisi iade sevk girişlerini bu adıma bırakır; böylece LP eşleşmesi yapılmadan başka palet FEFO ile düşülmez.

## Doğrulama

Ana uygulama ve test uzantısı derlendi, Sand2809'a Synchronize ile yüklendi. Codeunit 72149: 13 adlandırılmış test başarılı, 0 hata; AL aracı ayrıca bir adsız codeunit toplamıyla 14 başarılı sonuç raporluyor. İki yeni regresyon, kısmi iadenin doğru LP'yi seçmesini ve TerminalPosting etkinken tam paletin boşalmasını kontrol ediyor; tekrar çağrıda çift düşüm kontrolü de var. Mevcut testlerde eksik hedef göz ve beklenen hatadan sonra geri alınan mal kabul başlığı düzeneği düzeltildi, kayıtlı toplama/sevk test verisine gerekli dolaylı izinler eklendi. Testler AutoRollback ile çalışır.

Gerçek sandbox onarımı sonrası LP000874 / LP000875: totalQuantity=0, status=Used, atamalar temiz. Madde defteri 105040 → LP000874; 105041 → LP000875. 105041 onarımının tekrarında changedLps=0. Yeni bir ticari satın alma iade belgesi oluşturulup uçtan uca kaydedilmedi; otomatik kayıt bağlantısı derlendi, sonlandırma çekirdeği sunucu testleriyle doğrulandı.

Kanıtlar ve paket: `output/bade-return-1.14.1.161/` (EL_TERMINAL çalışma alanı kökündeki output). Geçici salt okunur teşhis uzantısı yalnız sandbox'a yüklendi ve teşhis sonrası uninstall ve unpublish işlemleriyle kaldırıldı.

Paket SHA256: `b987834af465590cbf96b833fc1841eff67cee191e83165d23dcc503adc32ed7`.
