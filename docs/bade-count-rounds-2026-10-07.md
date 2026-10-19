# BADE — Sayım turları (7 Ekim 2026)

Durum: kaynak geliştirmesi ve Android aday paketi hazır. Canlıya yayınlanmadı.
Android: **1.14.171-bade (200171)**. Gerekli BC kaynak sürümü: **1.14.1.126**.
Canlı terminal kanalı **1.14.170-bade** olarak kaldı.

## Kullanım

1. Sayım V2 belgesindeki ilk sayımı tamamlayın; atanmış bütün sayıcılar sonuçlarını kaydetsin.
2. İlk turdaki bulgulara göre Ad-hoc raf/stok düzeltmelerini yapın.
3. Aynı sayfa üzerinde **Ad-hoc Sonrası Yeni Tur Başlat** eylemini kullanın.
4. Yeni tur, önceki turun raf kapsamındaki güncel stok ve LP bilgileriyle açılır. Önceki sonuçlar korunur ve değiştirilemez.
5. Terminalde **Turları Yan Yana Karşılaştır** ile geçmiş turu seçin. BC kartında önceki tur satırları ve mevcut satırlarda önceki tur sütunları görünür.
6. Yeni turu tamamlayıp kaydedin. Stok düzeltmesi yalnız etkin son turun kendi stok görüntüsü ve sayım sonucu üzerinden yapılabilir.

Her tur ayrı belge anahtarı taşır; kök sayım numarası ekranda aynı kalır. Böylece gecikmiş okutmalar önceki turdan yeni tura yazılamaz. Yeni tur açma işlemi aynı eski tur için tekrarlandığında mevcut yeni tur döner. Yeni stok görüntüsü ile geçmiş bağlantısı tek işlemde oluşturulur; bu işlem stok hareketi yaratmaz.

Karşılaştırma LP kimliğini raf değişse bile korur. Turda olmayan satır ile henüz sayılmamış satır, sıfır sayımdan ayrılır. Yanlış rafta bulunan LP'nin kayıtlı miktarı raf stok görüntüsüne ikinci kez eklenmez. Eski turda kalan ürünler de karşılaştırmada gösterilir. Yeni tur tamamlanmadan stoklara işlenemez; raf bulgularına ilişkin mevcut kontroller sürer.

## Doğrulama ve kalan adımlar

- Android: **477 birim testi**, **2 emülatör arayüz testi** başarılı.
- BADE release APK oluşturuldu; sürüm ve mevcut BADE imza sertifikası doğrulandı.
- Değişen AL dosyaları ve test dosyası Microsoft AL ayrıştırıcısıyla kontrol edildi: **0 söz dizimi hatası**. Bu kontrol AL derlemesi değildir.
- AL tarafında geçmişin korunması, yeni stok görüntüsü, idempotent başlatma, geri alma ve arşivlenmiş tura yazma engelleri için testler eklendi; BC üzerinde henüz çalıştırılmadı.
- **Windows AL paket derlemesi ve gerçek BC ortamında testler tamamlanmadan canlıya hazır sayılmaz.** BC paketi kurulmadı, 1.14.171 yayınlanmadı.

APK, SHA-256, doğrulama kaydı ve 300 dp genişlikte karşılaştırma bileşeninin test ekran görüntüsü: [aday paket dizini](../releases/BADE-1.14.171-COUNT-ROUNDS-CANDIDATE/).
Ekran görüntüsü arayüz test verisidir; canlı BC testi değildir.
Derleme/test günlükleri: `build/bade-count-rounds-20261007/`.

Bu geliştirme sayım turu akışını kapsar. Aynı iç lotta farklı tedarikçi lotu isteği bu değişikliğe dahil değildir.
