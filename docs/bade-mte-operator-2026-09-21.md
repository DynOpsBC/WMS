# BADE MTE: Giriş Yapan alanı

Fotoğraflardaki DYNOPS / Bülent Abatay farkının kodda bulunan nedeni:
`MteOptionsSheet` PIN kullanıcısını gönderirken, mal kabul sonrası toplu
basım ve LP listesinden basım yalnız yazıcı / kopya adedi gönderiyordu.
Otomatik LP tamamlama ve stoktan LP oluşturma da aynı boş seçenekli yolu
kullanıyordu. ZPL şablonu böyle durumda `LP."Built By User"` değerine
düşüyordu; bu alan LP insert sırasında BC bağlantı hesabıyla doldurulur.

## Değişiklik

- Yalnız BADE Android istekleri PIN oturumunu kontrol eder ve kullanıcının
  görünen adını `optionsJson.operatorDisplayName` ile taşır.
- Toplu LP basımı, mal kabul sonrası basım, LP tamamlama, otomatik mal kabul
  basımı ve stoktan LP oluşturmanın üç API çeşidi kapsanır.
- Manuel MTE ekranındaki açık çalışan seçimi korunur.
- ZPL doğrudan bu adı kullanır. Müşterinin PDF raporu 60150 için yalnız
  mevcut şirketteki aktif çalışanlardan tek ad eşleşmesi kabul edilir.
  Eksik / birden fazla eşleşme, servis hesabına düşmek yerine açıklanır.
- Genel LP PDF raporuna da giriş yapan adı parametre olarak geçirilir.
- Eski API imzaları korunur. Yeni Android yeni uçları çağırır; eski BC
  paketinin kullanıcı bilgisini sessizce yok saymasını önlemek için toplu
  yeniden basımda ayrı `printMteForOperator` ucu kullanılır.
- LP oluşturma requestId, miktar planı, baskı adetleri ve tekrar istekte
  otomatik yeniden basmama davranışı korunur.

## Doğrulama ve yayın sırası

- BADE debug APK derlendi; 400 Android birim testi geçti.
- `al-print-tests/MteOperatorTests.Codeunit.al`: ZPL üzerinde PIN adı,
  DYNOPS'a düşmeme, manuel çalışan önceliği ve PDF çalışan eşleşmesi
  regresyonları eklendi. Test nesnesi 72181 mevcut 72180–72189 test
  uygulaması aralığındadır; üretim nesnesi eklenmedi.
- AL derlemesi / AL test yürütümü bu Mac oturumunda yapılmadı. Depo
  talimatına göre Windows AL araçları gereklidir.
- Yayına çıkmadan önce AL paketini Windows'ta derle, testleri sandbox'ta
  çalıştır, yeni BC paketini yükle, ardından sürümü artırılmış BADE APK'yı
  dağıt. Yeni APK eski BC paketiyle dağıtılmamalıdır.
- Canlıya yayın veya fiziksel yazdırma yapılmadı. PIN ile iki farklı
  kullanıcı için toplu basım, otomatik basım ve yeniden basım çıktıları
  ayrıca doğrulanmalıdır. Önceden basılmış etiketler kendiliğinden değişmez.
