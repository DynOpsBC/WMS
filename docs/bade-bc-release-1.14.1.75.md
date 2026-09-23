# BADE BCWMSApp 1.14.1.75 — LP kısmi işlem ve raf görünümü

Bu paket BADE `customer/bade` dalındaki **1.14.1.74** kaynakları üzerine hazırlanmıştır.

- **Kalanı yeni LP'ye ayır:** Mevcut LP'de kalacak miktar `0` olabilir. Seçilen ürün satırının tamamı yeni LP'ye aktarılır; kaynak LP'nin son satırı boşalırsa LP **Kullanıldı** durumuna geçer. Diğer kısmi işlemlerde `0` reddedilir.
- **Depo Gözü İçeriği:** **Raftaki LP'ler** eylemi seçili rafın tüm aktif LP başlıklarını, boş LP'ler dahil, açar. LP listesinde satır sayısı ve toplam miktar görünür. **Güncel LP No.ları** sütunu ürün bazlı kalır ve açıklaması bu ayrımı belirtir.

ZIP içindeki `BCWMSApp-1.14.1.75.app` BADE Business Central ortamına yüklenir. Android **1.14.159-bade** bu paketle kullanılabilir. Paket GitHub'da yayımlanınca BC ortamına kendiliğinden kurulmaz.

## Doğrulama

AL 1.14.1.75 hatasız derlendi ve paket manifestindeki sürüm doğrulandı. Production ortamına kurulum veya canlı LP ile işlem bu paket hazırlığında yapılmadı.
