# BADE — yazıcı görünen adları, terminalde bağlı yazıcı çubuğu (17 Eyl 2026)

Dal: `bade/agent-multi-printer` (customer/bade + main merge). Ajan **1.1.1**, BC **1.14.1.55**. Android tarafı bu dalda
derlenip test edildi ama APK yayınlanmadı: BADE terminal girişi (PIN, terminal kartı) diğer oturumda (Codex) commit
edilmemiş durumda; iki iş customer/bade'de birleşince tek APK çıkarılacak.

## Ajan 1.1.1 — Görünen adlar
Yazıcılar sekmesinde yeni tablo: **Windows yazıcısı | Tür | Görünen ad**. İşaretli her etiket yazıcısı ve belge yazıcısı
için ad yazılır (örn. "Mal Kabul Zebra"). Kaydet ve Bağlan → Buluta Eşitle ile `printerSnapshot.displayName` gider.
Boş bırakılırsa Windows adı kalır. En fazla 100 karakter, kontrol karakteri yok (validator). Ayar dosyası geriye uyumlu.

## BC 1.14.1.55
`AzurePrintStatus.UpsertSnapshotPrinter`: `displayName` varsa `Printer.Description` olur, yoksa Windows adı.
Eski ajan alanı göndermez, davranış değişmez.

## Terminal (bu dalda, `feature/TerminalPrinterBar.kt`)
- `LabelPrinterBar`: üst çubuğun altında her operasyon ekranında (Ana Menü, Bağlantı, Yazıcılar, Yardım hariç)
  "Etiket yazıcısı · Mal Kabul Zebra" + durum noktası (yeşil çevrimiçi / kırmızı çevrimdışı / gri bilinmiyor).
  60 sn'de bir BC'den tazelenir. Seçilmemişse kırmızı zemin "Etiket yazıcısı seçilmedi". Dokununca Yazıcılar açılır.
- `TerminalPrintersScreen`: müşteri terminalinde Yazıcılar ekranı iki karttan ibaret: Etiket yazıcısı ve Belge yazıcısı
  (ad, durum, son görülme, kod; etikette Test düğmesi), Yenile ve Değiştir. Değiştir klasik listeyi açar.
  Codex'in terminal modunda (yazıcı BC terminal kartından gelir) `onChange = null` verilip Değiştir gizlenir.
- `rememberDevicePrinter(usage)` `getDefaultPrinter` üzerinden okur; Codex'in terminal kapsamlı anahtarıyla uyumludur.

## Merge notu (customer/bade'ye alırken)
PrintersModule.kt: Codex'in `terminalManaged` metin satırlarını ("Etiket: KOD / Belge: KOD") kaldır, başa
`if (productionCustomer && !showFullList) { TerminalPrintersScreen(onChange = if (terminalManaged) null else { showFullList = true }); return }`.
AppRoot.kt: Scaffold içeriğindeki Column + LabelPrinterBar bloğunu koru; Codex'in "Aktif kullanıcı" bandı bunun üstünde kalabilir.

## Doğrulama
360 BADE birim testi, lint 0 hata; agent Core 50 test; alc 0 hata; emülatörde bar + ekran görüntüsü alındı
(BC bağlantısı olmadan: adlar kod olarak, durum gri). Windows'ta ajan paneli ve fiziksel baskı denenmedi.
