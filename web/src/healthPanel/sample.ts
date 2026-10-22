// Örnek yük (21 Eki 2026 BADE olaylarına benzer; Kitoko kategorileriyle) — testler ve ekran görüntüsü
// için. Şekli codeunit "DOPSWHS Health Detector".BuildJson ile aynıdır.
export const SAMPLE_PAYLOAD = {
  version: 1,
  generatedAt: "2026-10-22T06:41:00Z",
  locationFilter: "BADE",
  locations: [
    { code: "BADE", name: "BADE Ana Depo" },
    { code: "URETIM", name: "Üretim Deposu" },
  ],
  maxRowsPerCategory: 50,
  compareAvailable: true,
  summary: { critical: 3, warning: 4, info: 2 },
  categories: [
    {
      key: "stockMismatch",
      title: "LP miktarı ile stok tutmuyor",
      description:
        "Gözdeki BC stoğu ile o gözde duran aktif LP'lerin toplamı farklı. Terminal yanlış palet önerebilir veya toplama takılabilir. Otomatik düzeltme yok; sayım ya da LP düzeltmesi gerekir.",
      total: 2, scanLimited: false, fixable: false, canFix: false, fixDeniedReason: "", fixAllCaption: "",
      issues: [
        {
          id: 1, severity: "critical", title: "K.K03.11 · 15286 PP Granül Naturel · Lot A102511",
          detail: "Gözde 45.000 var, bu gözdeki aktif LP'ler ise 90.000 gösteriyor. LP'lerde 45.000 fazla görünüyor: terminal rafta olmayan paleti önerebilir. Sayım veya LP düzeltmesi gerekir; otomatik düzeltme yapılmaz.",
          location: "BADE", bin: "K.K03.11", item: "15286", variant: "", lot: "A102511", lpNo: "", docNo: "", ref: "",
          qtyBin: 45000, qtyLp: 90000, count: 0, fixAvailable: false, canFix: false, fixCaption: "", fixConfirm: "",
          showCaption: "LP'leri göster", compareAvailable: true,
        },
        {
          id: 2, severity: "warning", title: "A.01.04 · 20114 Koli 40x30 · Lot K2210",
          detail: "Gözde 1.200 var, bu gözdeki aktif LP'ler ise 800 gösteriyor. 400 stok hiçbir LP'de değil (LP'siz stok). LP'siz toplanamayabilir; sayım veya LP oluşturma gerekir.",
          location: "BADE", bin: "A.01.04", item: "20114", variant: "", lot: "K2210", lpNo: "", docNo: "", ref: "",
          qtyBin: 1200, qtyLp: 800, count: 0, fixAvailable: false, canFix: false, fixCaption: "", fixConfirm: "",
          showCaption: "LP'leri göster", compareAvailable: true,
        },
      ],
    },
    {
      key: "orphanAssignment",
      title: "Silinmiş belgeye atanmış LP",
      description: "LP, artık bulunmayan bir belgeye (ör. silinmiş rafa kaldırma) atanmış ve terminalde kullanılamıyor. Serbest bırakmak güvenlidir: stok ve göz değişmez.",
      total: 17, scanLimited: false, fixable: true, canFix: true, fixDeniedReason: "", fixAllCaption: "Tümünü serbest bırak",
      issues: [
        {
          id: 3, severity: "warning", title: "LP LP0004512 · rafa kaldırma PU001127",
          detail: "LP, artık bulunmayan rafa kaldırma PU001127 belgesine atanmış görünüyor (göz MK.01). Bu LP terminalde hiçbir işte kullanılamaz. Serbest bırakınca \"Oluşturuldu\" durumuna döner; stok ve göz değişmez.",
          location: "BADE", bin: "MK.01", item: "", variant: "", lot: "", lpNo: "LP0004512", docNo: "PU001127", ref: "",
          qtyBin: 0, qtyLp: 0, count: 0, fixAvailable: true, canFix: true, fixCaption: "Serbest bırak",
          fixConfirm: "LP LP0004512 serbest bırakılsın mı? LP \"Oluşturuldu\" durumuna döner; stok ve göz değişmez.",
          showCaption: "LP kartını aç", compareAvailable: false,
        },
        {
          id: 4, severity: "warning", title: "LP LP0004513 · rafa kaldırma PU001127",
          detail: "LP, artık bulunmayan rafa kaldırma PU001127 belgesine atanmış görünüyor (göz MK.01). Bu LP terminalde hiçbir işte kullanılamaz. Serbest bırakınca \"Oluşturuldu\" durumuna döner; stok ve göz değişmez.",
          location: "BADE", bin: "MK.01", item: "", variant: "", lot: "", lpNo: "LP0004513", docNo: "PU001127", ref: "",
          qtyBin: 0, qtyLp: 0, count: 0, fixAvailable: true, canFix: true, fixCaption: "Serbest bırak",
          fixConfirm: "LP LP0004513 serbest bırakılsın mı?", showCaption: "LP kartını aç", compareAvailable: false,
        },
      ],
    },
    {
      key: "undoneReceiptLp",
      title: "Geri alınan mal kabulde dolu kalan LP",
      description: "Mal kabul geri alındı ve stok düştü, ama o kabulden gelen LP'ler hâlâ dolu. Onarım yalnız bu kabule bağlı, gerçek stokla desteklenmeyen miktarı boşaltır.",
      total: 1, scanLimited: false, fixable: true, canFix: false,
      fixDeniedReason: "Bu düzeltme için yazma yetkiniz yok. Sistem yöneticinizden \"DOPSWHS-USER\" veya \"DOPSWHS-ADMIN\" izin kümesini isteyin.",
      fixAllCaption: "Tümünü onar",
      issues: [
        {
          id: 5, severity: "warning", title: "İrsaliye 109433 · 15286 PP Granül Naturel · Lot A102511",
          detail: "Mal kabul 20.10.2026 tarihinde geri alındı (-45.000), stok düştü; ama bu kabulden gelen 90 LP satırı hâlâ dolu görünüyor. Onarım yalnız bu kabule bağlı ve gerçek stokla desteklenmeyen miktarı boşaltır.",
          location: "BADE", bin: "", item: "15286", variant: "", lot: "A102511", lpNo: "", docNo: "109433", ref: "",
          qtyBin: -45000, qtyLp: 0, count: 90, fixAvailable: true, canFix: false, fixCaption: "LP'leri boşalt",
          fixConfirm: "109433 irsaliyesinin geri alınan miktarı kadar (en çok 45.000) 90 LP satırı boşaltılsın mı? Gerçek stokla desteklenen LP'lere dokunulmaz; BC stoğu değişmez.",
          showCaption: "Kayıtları göster", compareAvailable: false,
        },
      ],
    },
    {
      key: "lpSourceEntry",
      title: "LP'nin bağlı olduğu madde girişi yok veya tükenmiş",
      description: "LP satırının bağlı olduğu madde girişi silinmiş, başka madde/lot taşıyor ya da kalan miktarı bağlı LP'leri karşılamıyor. Stok LP'den düşülmeden çıkmış olabilir. LP İzlenebilirlik ile inceleyin.",
      total: 1, scanLimited: false, fixable: false, canFix: false, fixDeniedReason: "", fixAllCaption: "",
      issues: [
        {
          id: 6, severity: "critical", title: "Giriş 88412 · 20114 Koli 40x30 · Lot K2210",
          detail: "88412 girişinde kalan 0, bu girişe bağlı aktif LP'ler ise 400 gösteriyor; lokasyondaki toplam stok da (0) LP'leri karşılamıyor. Stok LP'den düşülmeden çıkmış (satış, sarf, geri alma) olabilir.",
          location: "BADE", bin: "", item: "20114", variant: "", lot: "K2210", lpNo: "LP0003311", docNo: "109201", ref: "",
          qtyBin: 0, qtyLp: 400, count: 2, fixAvailable: false, canFix: false, fixCaption: "", fixConfirm: "",
          showCaption: "Girişi göster", compareAvailable: true, traceAvailable: true,
        },
      ],
    },
    {
      key: "blockedItemStock",
      title: "Bloke üründe stok",
      description: "Ürün kartında bloke olan ürünler gözde stokta duruyor. Bu stok toplanamaz ve sevk edilemez. Bilgi amaçlıdır.",
      total: 1, scanLimited: false, fixable: false, canFix: false, fixDeniedReason: "", fixAllCaption: "",
      issues: [
        {
          id: 7, severity: "info", title: "B.02.07 · 30007 Eski Etiket Rulosu",
          detail: "Ürün kartında bloke, ama B.02.07 gözünde 36 stok duruyor. Bu stok toplanamaz ve sevk edilemez. Bloke bilinçliyse sorun yok; değilse ürün kartını kontrol edin.",
          location: "BADE", bin: "B.02.07", item: "30007", variant: "", lot: "", lpNo: "", docNo: "", ref: "",
          qtyBin: 36, qtyLp: 0, count: 0, fixAvailable: false, canFix: false, fixCaption: "", fixConfirm: "",
          showCaption: "Ürün kartını aç", compareAvailable: false,
        },
      ],
    },
    {
      key: "printJob",
      title: "Başarısız veya bekleyen baskı",
      description: "Bugün başarısız olan ya da 10 dakikadan uzun süredir kuyrukta bekleyen etiket ve belge baskıları.",
      total: 2, scanLimited: false, fixable: false, canFix: false, fixDeniedReason: "", fixAllCaption: "",
      issues: [
        {
          id: 8, severity: "critical", title: "Baskı başarısız · ZEBRA-MK1 (Mal Kabul Zebra)",
          detail: "RE001191 belgesinin baskısı 22.10.2026 08:12 tarihinde başarısız oldu (3 deneme). Son hata: Printer offline (TCP 9100 connection refused)",
          location: "BADE", bin: "", item: "", variant: "", lot: "", lpNo: "", docNo: "RE001191", ref: "ZEBRA-MK1 (Mal Kabul Zebra)",
          qtyBin: 0, qtyLp: 0, count: 0, fixAvailable: false, canFix: false, fixCaption: "", fixConfirm: "",
          showCaption: "Baskı kuyruğunu aç", compareAvailable: false,
        },
        {
          id: 9, severity: "warning", title: "Baskı bekliyor · ZEBRA-SVK (Sevkiyat)",
          detail: "SH000812 belgesinin baskısı 22.10.2026 07:55 tarihinden beri \"Dispatched\" durumunda bekliyor. Yazıcı ajanı çalışıyor mu, yazıcı açık mı kontrol edin. Son hata: hata mesajı yok",
          location: "BADE", bin: "", item: "", variant: "", lot: "", lpNo: "", docNo: "SH000812", ref: "ZEBRA-SVK (Sevkiyat)",
          qtyBin: 0, qtyLp: 0, count: 0, fixAvailable: false, canFix: false, fixCaption: "", fixConfirm: "",
          showCaption: "Baskı kuyruğunu aç", compareAvailable: false,
        },
      ],
    },
    {
      key: "printerMapping",
      title: "Eski veya pasif yazıcı eşleşmesi",
      description: "Cihaz–yazıcı eşleşmesi silinmiş, pasif ya da uzun süredir görülmeyen bir yazıcıyı gösteriyor. Bu cihazdan baskı gitmeyebilir.",
      total: 0, scanLimited: false, fixable: false, canFix: false, fixDeniedReason: "", fixAllCaption: "",
      issues: [],
    },
  ],
};

export const SAMPLE_CLEAN_PAYLOAD = {
  ...SAMPLE_PAYLOAD,
  summary: { critical: 0, warning: 0, info: 0 },
  categories: SAMPLE_PAYLOAD.categories.map((c) => ({ ...c, total: 0, issues: [] })),
};
