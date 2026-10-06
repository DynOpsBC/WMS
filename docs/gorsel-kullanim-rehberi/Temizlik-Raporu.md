# EL_TERMINAL alan kullanımı ve temizlik raporu

29 Eylül 2026

Güvenli temizlikte 3.66 GB (3.41 GiB) alan açıldı. Git tarafından dışlanan, kaynak içermeyen 51 derleme/önbellek klasörü kaldırıldı.

## Neden büyüdü

Ana depo ve altı ayrı Git worktree klasöründe aynı projenin farklı dalları tutuluyor. WMS/tmp altında ayrıca bir inceleme worktree’si var. Her kopya kendi derleme çıktılarını ve yayın paketlerini biriktirmiş.

Yedi ana kopyadaki releases klasörlerinin toplamı 10.27 GB. SHA-256 ile aynı olduğu doğrulanan, 1 MB üzeri tekrarlı yayın dosyalarının fazladan kopyaları yaklaşık 6.87 GB tutuyor. Bu kopyalar silinmedi.

Başlangıç ölçümü yaklaşık 21 GiB / 22 GB idi. İlk temizlik sonrası, kılavuz render dosyaları üretilmeden önce klasör 18,93 GB / 17,63 GiB olarak ölçüldü.

## Silinenler

| Kategori | Açılan alan |
|---|---:|
| Android derleme ara dosyaları | 2.03 GB |
| Android proje önbelleği | 0.19 GB |
| Windows ajanı derleme ara dosyaları | 1.44 GB |

Tam klasör listesi ve ölçümler: cleanup-manifest.json.

## Korunanlar

- DKC/EMU ve BADE kaynakları, Git geçmişi ve tüm çalışma dalları.
- Commit edilmemiş kaynak değişiklikleri ve kaynak yedekleri.
- Yayın APK/APP/ZIP paketleri, teslim klasörü ve mevcut ekran görüntüleri.
- Çalışan uygulamanın verileri ve oturum bilgileri.

## Tekrar büyümeyi azaltma

1. Yayın paketlerini tek bir arşiv konumunda tutun; her worktree içinde paket kopyalamayı bırakın. Mevcut paketler yayın ve geri dönüş ihtiyacı belirlenmeden kaldırılmamalı.
2. Eski release worktree’lerini kaynak değişikliği ve geri dönüş ihtiyacı kontrolünden sonra kapatın. Klasörleri elle silmek yerine git worktree remove kullanın.
3. Derlemeler tamamlandığında yalnız üretilen intermediates, tmp, bin ve obj klasörlerini temizleyin. Bir sonraki derleme bu dosyaları tekrar oluşturacağı için daha uzun sürebilir.
4. WMS/tmp içindeki kaynak yedeklerini sırf tmp adından dolayı topluca silmeyin; bu dizinde Git worktree ve commit edilmemiş çalışma kopyaları var.

## Kılavuz kaynak ve doğrulama notları

EMU cihazında 1.14.159-emu ve 1.14.156-emu-debug paketleri bulunuyor. İşlem ekranları ve son ana menü/giriş görüntüleri bağlı geliştirme paketinden (1.14.156-emu-debug) alındı; incelenen kaynak ağacında varsayılan sürüm 1.14.160. Ana menü ve giriş görüntüleri emülatörden alındı. Oturum başlangıçta bağlı değildi; bağlantı yenilendikten sonra operasyon, sorgu ve ayar ekranları da görüntülendi. Stok kaydı, atama, baskı veya belge onayı çalıştırılmadı. Detay örnekleri için kullanılan proje arşiv görselleri kılavuzda ayrıca etiketlendi.

İşlem metinleri TerminalHelpModule.kt, ReceivingModule.kt, PackingModule.kt, CountV2Module.kt, HierarchicalLpModule.kt, PrintersModule.kt, DkcShippingScreens.kt ve ilgili operasyon kodlarıyla karşılaştırıldı. Eski yardım metninin paketleme sırası ve Sayım V2 kayıt açıklaması güncel uygulama koduna göre düzeltildi.

Kullanıcının son tercihine göre uzun metinli doküman yerine 9 başlık, 27 ekran/etiket görseli ve 2 işlem şeması içeren tek dosyalı görsel HTML rehberi hazırlanmıştır. Görseller dosyaya gömülüdür; kartlarda kısa işlem adımları bulunur. Görseller tıklanınca büyür.

Temizlik sonrası yedi ana çalışma kopyasında git ls-files --deleted kontrolü yapıldı: takip edilen eksik dosya sayısı her birinde 0. Uygulama kodu değiştirilmediği için derleme/test çalıştırılmadı.

Görsel rehber doğrulaması: 9 bölüm, 29 görsel kart (27 ekran/etiket görseli ve 2 şema); eksik görsel veya harici görsel bağımlılığı yok. Masaüstü ve mobil görünümde yatay taşma yok. Büyütme, önceki/sonraki görsel, Esc ile kapatma ve bölüm bağlantıları kontrol edildi.
