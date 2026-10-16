# BADE BC 1.14.1.138 — sandbox doğrulaması ve canlı yükleme

1.14.1.137'nin madde defterinden MTE etiketi toplaması, kaynak LP satırını lota göre filtrelese de girişteki eski tekli/çoklu LP damgalarını kontrol etmeden ekliyordu. Sand2809’daki gerçek eylem testi, doğru lotun yanına başka lotun LP’sinin de eklendiğini gösterdi. 1.14.1.138 her aday LP’nin mevcut pozitif içeriğini madde, varyant, lot ve seri kimliğiyle doğrular. Geçerli eski LP bağlantıları çalışmaya devam eder.

## Sandbox

Tenant: `3bbd610b-95e4-47b3-8b48-4f7caf717bc3`; ortam: `Sand2809`; şirket: `BS İlaç Kozmetik San.Tic.A.Ş.`. Ana uygulama 1.14.1.138 yüklemesi başarılı. Test uzantısı yalnız sandbox’a yüklendi.

33 adlandırılmış test başarılı, 0 hata, 0 atlanan: 20 mal kabul testi (çoklu lot, aynı LP’de iki ürün, boş paleti kapatma engeli, toplu paletten sonra yeni LP, karma dağıtım, miktar kontrolü, tüm ürünleri birlikte kaydetme, geri alma ve sonraki kabul dalgası), 6 MTE testi (operatör, ortak etiket alanları, karma palette ürün/lot grupları ve RDLC’nin PDF olarak üretilmesi), 7 gerçek BC eylem testi (LP kartı/liste seçimi, yanlış kaynak lotu, eski tekli/çoklu damga, doğru eski bağlantı, varyant).

AL aracının JSON özeti 36 başarılı sonuç gösterir; bunların 3’ü adsız codeunit toplamıdır. Gerçek test yöntemi sayısı 33’tür. İlk 137 çalıştırmasında yanlış eski LP damgası regresyonu kırmızıydı; 138’de yeşil.

Testler `AutoRollback` ile çalışır. Test düzeneklerinde veritabanından güncel satır okunması ve ikinci dalga için gerçekçi alınmış miktar bilgisi düzeltildi; boş palet hata testi, hata sonrası veri geri alma etkisini sonraki işlemlerle karıştırmamak için ayrıldı. Salt okunur denetimde başlangıçta kullanılan Academy ve BS şirketlerinde test LP/madde kaydı bulunmadı; LP numara serisi `AWMS-LP` kaldı.

Gerçek sandbox LP000080 için BC listesinden MTE raporu açıldı ve PDF indirildi: AB.00175 ürününün A101296 / A101812 lotları iki ayrı 10×8 cm sayfa; miktarlar 1.863 / 2.085 ADET; toplam 3.948. İki sayfadaki QR da LP000080 olarak çözüldü. PDF görseli incelendi.

## Canlı

1.14.1.138, sandbox testleri geçtikten sonra Production’a standart Extension Management → Upload Extension yoluyla yükleme için gönderildi. Current version ve Add şema modu kullanıldı. Üç kurulum denemesi (15 Ekim 00:07, 00:17 ve 00:34) aynı “Etkinlik başka bir kullanıcıyla kilitlendi. Lütfen etkinliği yeniden deneyin.” hatasıyla başarısız oldu. Yönetim merkezi son işlemde kaynak sürüm 1.14.1.135, hedef sürüm 1.14.1.138; hata `ExtensionChangeFailed` / `UnknownAppError` gösteriyor. Paket yayımlanmış olsa da kurulu canlı sürümü hâlâ 1.14.1.135. Son işlem kimliği `62774fbb-6810-4920-bced-687d55d98188`; bitiş 00:39:06. ForceSync yapılmadı; diğer kullanıcı oturumları sonlandırılmadı. Açık muhasebe ve arka plan oturumlarını kesecek Production yeniden başlatması için kullanıcı yanıtı bekleniyor.

## Kanıt ve sınırlar

Yerel paket, test JSON’u, yükleme kayıtları, sandbox PDF’i ve görsel: `output/bade-sand2809-1.14.1.137/`. Paket SHA256: `2de642b648858dad567b480cdc9704cd8ee16ffa6bcd12656be7f5c7b0d2e3cd`.

Testler BC sunucusu ve masaüstü rapor işlemlerini kapsar. Fiziksel yazıcı/terminal ile baskı yapılmadı. Karma palet arayüzü için Android 1.14.180 gerekir; Android kanalı bu çalışmada değiştirilmedi.
