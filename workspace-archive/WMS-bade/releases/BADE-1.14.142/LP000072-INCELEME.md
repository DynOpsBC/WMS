# LP000072 — etiketlerde kaynak farkı

Gönderilen fotoğrafta iki etiketin QR altındaki LP numarası LP000072. Madde AB.00190; lot, tedarikçi, miktar ve tarih farklı. Sağ etikette lot A102261, miktar 1.175 ADET, tarih 18.09.2026, depo giriş no U.Y görülüyor. Sol etikette miktar 10.230 ADET.

Kod bulguları (canlı kayıt kanıtı değildir):
- PrintDispatcher çok satırlı LP için ürün/lot/kaynak belge grubu başına etiket basabilir. Aynı LP numarası tek başına mükerrer palet oluşturulduğunu göstermez.
- MteZplBuilder.ResolveReceiptNo önce kaynak ILE ile eşleşen kayıtlı depo girişini, ardından kaynak ILE belge numarasını, kaynak ILE yoksa LP satırındaki kaynak belgeyi kullanır. Boş değer U.Y basılır.
- Yerel müşteri raporu 60150 örneğinde de kayıtlı depo girişi, ardından ILE belge numarası kullanılır. Yerel örneğin canlıdaki sürümle aynı olduğu doğrulanmadı.
- Stok hareketinden LP oluşturma kodu LP satırında Source Item Ledger Entry No. ve Source Document No. alanlarını saklar. Manuel satır eklemede bu kaynak alanları otomatik dolmaz.

Kesinleştirmek için BADE Production LP000072 satırları, kaynak ILE numaraları, ilgili ILE belge türü/numarası, LP hareket geçmişi ve baskı kuyruğundaki eski/yeni işlerin karşılaştırılması gerekiyor. Mevcut Azure oturumu BADE tenant erişimine sahip değil; emülatördeki release uygulamasının oturum verisine erişilemiyor. Canlı kayıt değiştirilmedi, yeniden etiket basılmadı.

1.14.142 APK / 1.14.1.60 BC paketi giriş yapan kullanıcı düzeltmesidir. Bu ikinci olay çözüldü olarak işaretlenmemiştir.
