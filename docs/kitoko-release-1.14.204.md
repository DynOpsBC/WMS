# Element4 / Kitoko Android 1.14.204

13 Kasım 2026 · versionCode 200204 · com.dynops.bcwms.kitoko

- Bin Sorgu: ürün kodu veya açıklamasına göre raf içeriği filtresi; okutma ve temizleme desteği.
- Sorgu formu ve sonuçlar tek kaydırılabilir listede. Dar terminal ekranında alt sonuçlara erişilebilir.
- Filtre yalnız Bin İçeriği listesini süzer. Raftaki tüm LP'ler ve son 20 ambar hareketi ayrıca gösterilir; LP seçimi ve etiket işlemleri korunur.
- BC paketi veya stok kayıt işlemlerinde değişiklik yok.

Derleme: `:app:testKitokoDebugUnitTest :app:assembleKitokoRelease -PreleaseVersionCode=200204 -PreleaseVersionName=1.14.204`.
Birim testleri: 634 test, 0 hata/başarısız/atlanan.
Release derlemesi ve bağımsız Claude incelemesi başarılı. Sand2010 / Element4 emülatöründe HM1 rafındaki 1004 ürün arasından P-01061 filtresi tek sonuç verdi; form yukarı kaydırılıp ambar hareketlerine erişildi. Fiziksel cihaz barkod okuyucusu ayrıca denenmedi.
