BADE Android 1.14.167 / BCWMSApp 1.14.1.123

- Sayım hataları popup olarak gösterilir; sayım kartlarında LP numarası, renkli durum ve sistem/bulunan raf bilgileri görünür.
- Farklı rafta bulunan LP ilk sayımda kaydedilir. Ad-hoc düzeltmesinden sonra ikinci sayım yeni belgeyle yapılır; raf farkı içeren ilk belge stoklara işlenmez.
- LP raf içeriği açılışındaki geçici kayıt / modal işlem hatası düzeltildi.
- Kısmi LP işlemi hedef LP’ye aktarım seçeneğiyle açılır. Doğrudan aktarım aynı raftaki LP’ler içindir; farklı raflardan tek üretim LP’sine toplama mevcut üretim toplama akışıyla yapılır.
- Mal kabulde “Yazdırmadan kaydet” eklendi. LP tamamlama varsayılan olarak yazdırmadan yapılır; etiket sonradan basılabilir.

Sayım özellikleri için ekteki BCWMSApp 1.14.1.123 gereklidir. Bu GitHub yayını BC ortamına kurulum yapmaz.

Doğrulama: 465 Android birim testi geçti. Sayım ekranı için önceki aşamada 5 Compose testi ve dar/koyu tema kontrolü geçti. BC uygulaması ve AL test paketi derlendi; BC ortamında uçtan uca depo testi henüz yapılmadı.
