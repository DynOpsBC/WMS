// Bağımsız önizleme (BC dışı geliştirme, Playwright ekran görüntüleri) için örnek
// veri. BC bağlıyken SetData bunu ezer. Katalog, AL "DOPSWHS Terminal Layout Mgt"
// ile aynıdır.
import type { CatalogItem, DesignerData, Layout, LayoutHeader, LayoutLine, PreviewData, ScanFlag } from "./types";
import { defaultLine } from "./state";

const tile = (group: string, key: string, label: string, description: string, sort: number, flags: ScanFlag[] = [], availability = "", locked = false): CatalogItem =>
  ({ screen: "HOME", key, kind: "tile", group, label, description, sort, flags, availability, locked });
const button = (screen: string, key: string, label: string, description: string, sort: number, availability = ""): CatalogItem =>
  ({ screen, key, kind: "button", group: "", label, description, sort, flags: [], availability, locked: false });

export const sampleCatalog: CatalogItem[] = [
  tile("Gelen", "RECEIVING", "Mal Kabul", "Gelen ürünü kaydet, LP'yi başlat", 10, ["LP", "LOT"]),
  tile("Gelen", "PUTAWAY", "Yerleştirme", "Ürünü veya LP'yi rafına kaldır", 20, ["LP", "BIN"]),
  tile("Giden", "PICKING", "Toplama", "Sipariş ürünlerini raflardan topla", 30, ["LP", "BIN"]),
  tile("Giden", "PACKING", "Paketleme", "Toplanan ürünleri kolilere ayır", 40),
  tile("Giden", "SHIPPING", "Sevkiyat", "Belgeyi tamamla ve çıkışı kaydet", 50, ["LP"]),
  tile("İç Operasyon", "LICENSE_PLATES", "LP", "Palet ve taşıma kabı işlemleri", 60),
  tile("İç Operasyon", "HIERARCHICAL_LP", "Kutu ve Palet", "Ürün LP'lerini kutuya, kutuları palete bağla", 70, [], "Yalnız EMU / DKÇ sürümünde"),
  tile("İç Operasyon", "ADHOC_MOVE", "Ad-Hoc Hareket", "Belgesiz raf veya LP hareketi", 80, ["LP", "BIN"]),
  tile("İç Operasyon", "DIRECTED_MOVE", "Yönlendirilmiş", "Hazırlanmış taşıma emrini uygula", 90, ["BIN"]),
  tile("İç Operasyon", "COUNT", "Sayım", "Hazır sayım belgesini tamamla", 100, ["BIN"]),
  tile("İç Operasyon", "COUNT_V2", "Sayım V2", "QR okutarak sıfırdan sayım yap", 110, ["BIN"]),
  tile("İç Operasyon", "FIRST_COUNT", "İlk Sayım", "Sadece madde okut, adet gir", 115, [], "Yalnız Kitoko sürümünde"),
  tile("Üretim", "PRODUCTION", "Üretim", "Tüketim ve üretim çıkışı kaydet", 120, ["LOT"]),
  tile("Üretim", "SUBCONTRACTING", "Fason İşlemler", "Fasona sevk ve referansla teslim alma", 130),
  tile("Üretim", "ASSEMBLY", "Montaj", "Montaj emrinin sarf ve çıktıları", 140),
  tile("Kalite", "QUALITY", "Kalite Denetimi", "Kontrol sonuçlarını değerlendir", 150),
  tile("Kalite", "QUALITY_MGMT", "MS Kalite", "Lot blokajlarını ve ölçümleri yönet", 160),
  tile("Sorgu", "ITEM_INQUIRY", "Ürün Sorgu", "Ürünün raf, lot ve miktarını bul", 170),
  tile("Sorgu", "LABELS", "Etiket Çıkar", "Ürün etiketi · Raf etiketi · A4 belge", 180, [], "Kitoko / EMU sürümlerinde"),
  tile("Sorgu", "BIN_INQUIRY", "Bin Sorgu", "Bir rafın mevcut içeriğini gör", 190),
  tile("Sorgu", "WHSE_ENTRIES", "Ambar Hareketleri", "Geçmiş stok hareketlerini incele", 200),
  tile("Destek ve Ayarlar", "FIELD_SETTINGS", "Alan Ayarları", "Kartlarda gösterilen bilgileri seç", 210, [], "Müşteri sürümlerinde gizli"),
  tile("Destek ve Ayarlar", "SELF_TEST", "Sistem Sağlığı", "Bağlantıları ve servisleri kontrol et", 220, [], "Müşteri sürümlerinde gizli"),
  tile("Destek ve Ayarlar", "PRINTERS", "Yazıcılar", "Etiket ve belge yazıcısını seç", 230),
  tile("Destek ve Ayarlar", "TEST_CENTER", "Test Merkezi", "Operasyon test sonuçlarını incele", 240, [], "Yalnız yönetici test oturumunda"),
  tile("Destek ve Ayarlar", "POSTING_TEST", "Kayıt Testi", "BC kayıt servislerini doğrula", 250, [], "Yalnız yönetici test oturumunda"),
  tile("Destek ve Ayarlar", "CONNECTION", "Bağlantı", "Hesap, ortam ve şirket ayarları", 260, [], "", true),
  button("LABELS", "LABELS.LAYOUT_PICKER", "Etiket tasarımı seçimi", "Ekranın üstünde etiket tasarımı seçilir", 10, "Kitoko"),
  button("LABELS", "LABELS.ALL_ITEMS", "Tüm ürün etiketleri", "BC'deki bütün ürünlerin etiketini tek seferde basar", 20, "DKÇ / EMU"),
  button("LABELS", "LABELS.RANGES", "Aralık blokları (1–300, 301–500 …)", "Ürün no sırasına göre blok blok basar", 30, "Kitoko"),
  button("LABELS", "LABELS.EXCEL", "Excel listesinden etiket", "Excel'den yüklenen ürün listesini basar", 40, "DKÇ / EMU"),
  button("LABELS", "LABELS.PREPARED_LIST", "Hazır listeden etiket", "BC'de hazırlanmış listeyi basar", 50, "DKÇ / EMU"),
  button("PUTAWAY", "PUTAWAY.ALL_TO_ONE_BIN", "Tümünü Bir Bine", "Belgedeki bütün yerleştirmeleri tek rafa atar", 10),
  button("LICENSE_PLATES", "LP.CREATE_SINGLE", "Tekli LP Oluştur", "Listeden yeni boş LP açar", 10),
  button("LICENSE_PLATES", "LP.PRINT_MTE", "MTE Yazdır", "LP detayında MTE etiketi basar", 20),
  button("LICENSE_PLATES", "LP.BREAK", "Boz", "LP'yi bozar (içeriği serbest bırakır)", 30),
  button("COUNT", "COUNT.CREATE_NEW", "Yeni Sayım Oluştur", "Terminalden yeni sayım belgesi açar", 10),
  button("COUNT", "COUNT.PRINT_LP_LABELS", "Sayılan LP etiketlerini yazdır", "Sayım sonrası LP etiketlerini basar", 20),
  button("BIN_INQUIRY", "BIN_INQUIRY.PRINT_LP_LABELS", "Seçilen LP etiketlerini bas", "Raf sorgusunda seçili LP etiketlerini basar", 10),
];

const header = (code: string, description: string, appliesTo: LayoutHeader["appliesTo"], appliesToCode = "", version = 1): LayoutHeader =>
  ({ code, description, appliesTo, appliesToCode, active: true, version, modifiedAt: "2026-10-21T14:05:00Z", modifiedBy: "MERVE" });

function layoutWith(h: LayoutHeader, patch: Record<string, Partial<LayoutLine>>): Layout {
  return {
    ...h,
    lines: sampleCatalog.map((c) => ({ ...defaultLine(c), ...(patch[`${c.screen}|${c.key}`] ?? {}) })),
  };
}

export const sampleLayouts: Layout[] = [
  layoutWith(header("STANDART", "Standart terminal yerleşimi", "all", "", 4), {
    "HOME|FIELD_SETTINGS": { visible: false },
    "HOME|SELF_TEST": { visible: false },
    "HOME|TEST_CENTER": { visible: false },
    "HOME|POSTING_TEST": { visible: false },
    "HOME|HIERARCHICAL_LP": { visible: false },
    "HOME|RECEIVING": { requireLot: true },
    "HOME|PUTAWAY": { requireLp: true, note: "Yerleştirmede palet etiketi okutulmadan raf seçilemez." },
  }),
  layoutWith(header("DEPOCU", "Depo operatörü — sade menü", "role", "PICKER", 2), {
    "HOME|PRODUCTION": { visible: false },
    "HOME|SUBCONTRACTING": { visible: false },
    "HOME|ASSEMBLY": { visible: false },
    "HOME|QUALITY": { visible: false },
    "HOME|QUALITY_MGMT": { visible: false },
    "HOME|FIELD_SETTINGS": { visible: false },
    "HOME|SELF_TEST": { visible: false },
    "HOME|TEST_CENTER": { visible: false },
    "HOME|POSTING_TEST": { visible: false },
    "HOME|HIERARCHICAL_LP": { visible: false },
    "HOME|PICKING": { sort: 30, label: "Sipariş Topla" },
    "HOME|SHIPPING": { sort: 40 },
    "HOME|PACKING": { sort: 50 },
  }),
  layoutWith(header("DKC-ETIKET", "DKÇ etiket terminali", "terminal", "ETIKET-01", 1), {
    "LABELS|LABELS.RANGES": { visible: false },
    "LABELS|LABELS.LAYOUT_PICKER": { visible: false },
  }),
];

export function sampleData(selected = "STANDART"): DesignerData {
  const layout = sampleLayouts.find((l) => l.code === selected) ?? sampleLayouts[0];
  return {
    catalogVersion: "1",
    catalog: sampleCatalog,
    screens: [
      { key: "HOME", title: "Ana Menü", tileKey: "" },
      { key: "LABELS", title: "Etiket Çıkar", tileKey: "LABELS" },
      { key: "PUTAWAY", title: "Yerleştirme", tileKey: "PUTAWAY" },
      { key: "LICENSE_PLATES", title: "LP (Taşıma Kabı)", tileKey: "LICENSE_PLATES" },
      { key: "COUNT", title: "Sayım", tileKey: "COUNT" },
      { key: "BIN_INQUIRY", title: "Bin Sorgu", tileKey: "BIN_INQUIRY" },
    ],
    layouts: sampleLayouts.map(({ lines: _lines, ...h }) => h),
    roles: [
      { code: "OPERATOR", description: "Genel depo operatörü" },
      { code: "PICKER", description: "Toplayıcı" },
      { code: "RECEIVER", description: "Mal kabul ve yerleştirme" },
      { code: "COUNTER", description: "Sayım" },
      { code: "QUALITY", description: "Kalite" },
    ],
    terminals: [{ code: "ETIKET-01" }, { code: "DEPO-01" }, { code: "DEPO-02" }, { code: "URETIM-01" }],
    layout: structuredClone(layout),
  };
}

/** BC'deki ResolveLayoutCode ile aynı öncelik: Terminal > Rol > Tümü. */
export function samplePreview(roleCode: string, terminalCode: string): PreviewData {
  const active = sampleLayouts.filter((l) => l.active);
  const pick =
    (terminalCode && active.find((l) => l.appliesTo === "terminal" && l.appliesToCode === terminalCode)) ||
    (roleCode && active.find((l) => l.appliesTo === "role" && l.appliesToCode === roleCode)) ||
    active.find((l) => l.appliesTo === "all");
  return {
    roleCode,
    terminalCode,
    layoutCode: pick?.code ?? "",
    layoutDescription: pick?.description ?? "Standart (katalog varsayılanı)",
    layout: structuredClone(pick ?? { ...header("", "", "all"), lines: sampleCatalog.map(defaultLine) }),
  };
}
