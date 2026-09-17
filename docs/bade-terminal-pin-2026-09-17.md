# Bade — terminal ve çalışan girişi

Android: **1.14.129-bade** (200129). BC: **1.14.1.54**.

## BC kurulumu

1. **WMS Terminaller ve Kullanıcılar** ekranını açın (eski Local WMS Users ekranı).
2. **Yeni** ile `TERMİNAL-1` oluşturun. Etiket ve belge yazıcılarını seçin.
3. Terminal kartındaki **Kullanıcı Oluştur** ile yalnız **Ad Soyad** ve **4 Haneli PIN** girin.
4. İkinci terminal ve kullanıcıları için aynı adımları uygulayın.

Kullanıcı kimliği sistem tarafından oluşturulur; PIN düz metin saklanmaz veya API'de gösterilmez.
Aynı terminalde aynı görünen adla ikinci kayıt oluşturulamaz. Kullanıcılar terminale özeldir.

Mevcut kullanıcılar silinmez. **Tüm Kullanıcılar** ile kaydı açın, terminal atayın ve yeni
4 haneli PIN belirleyin. Kullanıcı kodu ve geçmiş işlemleri korunur. PIN sıfırlamak için aynı
karttaki **Yeni 4 Haneli PIN** alanını kullanın. Devre Dışı seçimi yeni girişi engeller.

## Yönetici

Aynı ekrandaki **Yönetici Oluştur** ile ad soyad ve 4 haneli PIN belirleyin. Yönetici
bu BC şirketindeki tüm etkin terminallerin kullanıcı listesinde **Yönetici** olarak görünür;
ayrı terminal kullanıcıları açmak gerekmez. Kendi PIN’iyle giriş yapar ve seçilen terminalin
yazıcısını kullanır. Yanlış PIN ve geçici kilit kuralları yöneticide de geçerlidir.

Mevcut kullanıcı kartındaki **Yönetici (Tüm Terminaller)** seçeneğiyle bu erişim verilir veya
kaldırılır. Bu seçenek BC sistem yetkisi ya da şifresiz servis hesabı geçişi vermez.

## Terminal kullanımı

BC bağlantısı yönetici tarafından mevcut yöntemle bir kez kurulur. Ardından:

1. İlk açılışta terminali seçin.
2. Adınızı seçin, 4 haneli PIN girin.
3. İşiniz bittiğinde ana menüde **Kullanıcı çıkışı** seçin; sonraki çalışan kendi adı ve PIN’iyle girer.

PIN doğrulaması 30 dakika geçerlidir; uygulamayı kapatıp açmak süreyi uzatmaz. Süre dolunca kullanıcı seçimi ve PIN ekranı açılır. Aynı çalışan açık ekranına döner; farklı çalışan ana menüye geçer. Terminal ve yazıcı seçimi korunur. Yeni depo yazma istekleri doğrulama tamamlanana kadar engellenir. Önceden sunucuya gönderilmiş işlemler geri alınmaz.
Açılışta BC üzerinden terminal ve kullanıcı etkinliği tekrar kontrol edilir. Bağlantı sorunu
varsa operasyonlar açılmaz. Devre dışı bırakılan veya terminal yetkisi kaldırılan kullanıcı
yeniden giriş ekranına döner. Kullanıcı çıkışı ana menüden yapılır; açık işlem
sırasında değiştirme düğmesi gösterilmez. PIN telefonda saklanmaz.

Yazıcılar BC terminal kartından gelir ve şirket/ortam/terminal kapsamında tutulur. Kullanıcı
değiştirmek yazıcıyı başka bir çalışanın seçimine taşımaz. Yazıcı ayarı değişince tekrar giriş
yapın. Açık yazıcı parametresi isteyen bir baskıda yazıcı boşsa ortak BC varsayılanına düşmek
yerine anlaşılır hata gösterilir. BC'nin kendi otomatik kayıt/baskı işlerinin ayarları ayrıdır.

## Kontroller

- Terminal-kullanıcı eşleşmesi ve devre dışı kontrolü BC'de yapılır.
- 5 hatalı PIN, 5 dakika kilit uygular; yönetici PIN sıfırlayınca kilit kalkar.
- Eski servis hesabı ile şifresiz yönetici geçişi Bade giriş ekranında kapalıdır.
- Önceki kişiye ait profil, kullanıcı değişiminde temizlenir; yeni kişinin mevcut operatör
  kimliği kullanan WMS akışlarına kendi kimliği aktarılır. BC'nin standart sistem kullanıcı
  alanları servis hesabını göstermeye devam eder; tüm hareketler için yeni bir merkezi
  oturum/audit sistemi bu değişikliğin parçası değildir.

## Doğrulama ve yükleme

BC ana paketi ve 9 terminal PIN/atama testini içeren AL test paketi derlendi. Android’de 367 birim
testi ve emülatörde yönetici girişi/çıkış ve süre dolumu sonrası devam/kullanıcı değişimi dahil 7 senaryo geçti. Yanlış PIN, başında sıfır bulunan PIN,
PIN ile giriş ve terminalin yazıcı seçiminin korunması kontrol edildi. AL testleri
BC test servisinde çalıştırılmamıştır.
Canlı BC'de iki fiziksel terminal/yazıcıyla kabul testi ve yayın yapılmamıştır.

İki taraf birlikte güncellenmelidir: önce BC paketi, sonra terminal APK'sı. Yeni APK eski BC
paketinde terminal listesini alamaz ve kullanıcı girişi açmaz. Önce terminal ve kullanıcı
kayıtlarını hazırlayın, ardından APK dağıtın.

Aktif çalışan adı tüm ekranların üstünde gösterilir. Mal kabul, toplama, paketleme ve sayım kullanıcı seçicileri aynı WMS kullanıcı tablosunu kullanır. Mal kabul WMS çalışanını BC Warehouse Employee kaydı gerektirmeden atayabilir; eski BC kullanıcı atama davranışı korunur. Mal kabul/toplama API yanıtları çalışan adını da döndürür. BC paketi APK’dan önce güncellenmelidir.

## PIN sonrası kaldığı yerden devam kontrolü

1.14.127: PIN penceresi açık belgeyi ekrandan kaldırmaz. Aynı çalışan doğrulanınca açık belge ve bellekte tutulan miktar/adım korunur. Farklı çalışan girişinde ana menüye dönülür. Süre dolarken devam eden belge yenilemesinde atanan kişi kimliğinin boşalması düzeltildi; kimliği okumak mümkün olsa da PIN yenilenmeden depo yazma çağrıları reddedilir.

Gerçek PIN penceresini kullanan izole emülatör test ekranında belge `TEST-001`, miktar `12.5` ve `Raf doğrulama` adımıyla yanlış PIN, ardından doğru PIN denenir; belge yeniden oluşturulmadan değerlerin korunduğu doğrulanır. Ayrı senaryo farklı çalışanın eski belgeye dönmediğini doğrular. Bu, canlı BC üzerinde bir mal kabul kaydetme testi değildir.

Süre 30 dakika olarak korundu. Bu davranış uygulama açıkken PIN kilidi içindir; Android uygulama sürecini sonlandırırsa kaydedilmemiş bütün alanların geri gelmesi garanti edilmez. Daha önce sunucuya gönderilmiş bir işlem geri alınmaz, başarısız istekler PIN girişinden sonra otomatik tekrarlanmaz.

## 1.14.128 giriş ekranı

Terminal ve çalışan seçimi logolu, sola hizalı kartlarla düzenlendi. Seçili ortam/şirket ve Ortamı değiştir düğmesi girişte üstte görünür. Düğme Bade’de eski kullanıcı/şifre sayfasına uğramadan ortam ve şirket seçimine açılır. Ortam ekranında mevcut bağlantı ayrı kartta, ortam ve şirket seçimi iki adımda gösterilir. PIN ekranında bağlantı kartı gizlenir; klavye açıkken giriş alanı kaydırılabilir. Şirket bağlantısı kurulurken ortam değişimi engellenir ve seçilen ortam işlem başında sabitlenir. BC paketi yine 1.14.1.53’tür.

## 1.14.129 / BC 1.14.1.54 — görünmeyen kullanıcılar

Terminal kullanıcı sorgusundaki `terminalCode ... or terminalAdmin ...` ifadesi kaldırıldı: Business Central farklı alanlar arasında OR filtresini desteklemiyor (https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/webservices/odata-known-limitations). Terminal çalışanları ve yöneticiler iki ayrı, tam sayfalanmış sorgudan birleştirilir; aynı kullanıcı iki kez gösterilmez, pasif/başka terminale ait sıradan kullanıcılar elenir. İki sorgudan biri tamamlanmazsa eksik liste girişe açılmaz. Aynı yükleme oturum yenilemede de kullanılır.

BC'de Yöneticiler düğmesi eklendi; yönetici oluşturulunca yönetici listesi açılır. Terminal kartında Yöneticiler (Tüm Terminaller) bölümü bulunur. Tüm Kullanıcılar ekranı BC aramasından da açılabilir. Mevcut kayıtları silmek veya yeniden oluşturmak gerekmez. APK sorgu düzeltmesi BC 1.14.1.53 ile de çalışır; yönetici görünürlüğü için BC 1.14.1.54 yüklenir.

1.14.129 son düzenleme: Yenile / Terminal değiştir üst bölüme taşındı ve sistem gezinme alanı için güvenli boşluk eklendi. Yönetici ana giriş seçeneği isim yerine Yönetici girişi olarak gösterilir. Tek yönetici varsa doğrudan PIN; birden çok yönetici varsa hesap seçimi yapılır. Kullanıcının talebiyle bu son UI değişiklikleri için test çalıştırılmadı; yalnız APK derlendi.
