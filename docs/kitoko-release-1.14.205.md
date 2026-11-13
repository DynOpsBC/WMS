# Element4 / Kitoko Android 1.14.205

13 Kasım 2026 · versionCode 200205 · com.dynops.bcwms.kitoko

- Toplam stoğun hemen altında depo, alan (zone), raf/göz (bin) ve miktar doğrudan görünür; popup veya ek buton yoktur.
- Birden fazla raftaki stok ayrı satırlardadır: örneğin HM1 — 500 ADET, MONT — 200 ADET. LP’siz stoklar dahildir.
- Kaynak BC depo gözü içerikleridir. Tüm sayfalar alınır; eksik/hatalı sorgu boş stok olarak gösterilmez ve tekrar deneme sunulur.
- Sıfırlar gizlenir; negatif/kesirli miktarlar, varyantlar ve satır ölçü birimleri korunur. Depo toplamı yalnız BC temel birim miktarından hesaplanır.
- Barkod/QR ve elle madde numarası girişi desteklenir. Ardışık sorgularda son okutulan ürün geçerlidir; LP okutması LP kartını açar.
- Form ve sonuçlar tek kaydırılabilir listede. BC paketi veya stok kayıt işlemleri değişmez.

Doğrulama: 642 birim testi ve 7 Android emülatör testi geçti (hata/atlanan yok). Testler doğrudan satırlar, negatif/farklı birimli stok, temel birim toplamı, hata/tekrar deneme, boş stok, uzun listede kaydırma, QR/madde/LP girişi ve alan ekrandan çıktıktan sonra donanım tarama olayını kapsar. Sand2010 / Element4 BC API’sinden salt okunur alınan güncel depo gözü yanıtı ekranla karşılaştırıldı.

Bağımsız Claude incelemesi: approve, engelleyici/orta bulgu yok. İmzalı release derlemesi başarılı; paket com.dynops.bcwms.kitoko, versionCode 200205 ve kalıcı yayın sertifikası doğrulandı. Fiziksel terminal/kamera testi ve uygulamanın BC bağlantısıyla tam uçtan uca kabul testi ayrıca yapılmadı.
