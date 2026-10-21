// Kaydı engellemeyen uyarılar: etiket dışına taşan eleman, bilinmeyen alan,
// boş metin, sığmayan yazı, geçersiz EAN-13 vb.
import { elementName, isKnownType, resolveValue } from "./design";
import { elementGeometry, layoutBarcode, layoutQr, layoutText, type LayoutContext } from "./layout";
import { LIMITS, type LabelDesign } from "./types";
import { ean13Status } from "../render/barcode";

export interface Warning {
  elementId: string | null;
  message: string;
}

const EPS = 0.05;

export function validateDesign(design: LabelDesign, ctx: LayoutContext): Warning[] {
  const warnings: Warning[] = [];
  const fieldKeys = new Set(design.fields.map((f) => f.key));
  const imageIds = new Set(design.images.map((i) => i.id));
  if (design.widthMm > LIMITS.widthMm || design.heightMm > LIMITS.heightMm) {
    warnings.push({ elementId: null, message: `Etiket en çok ${LIMITS.widthMm} × ${LIMITS.heightMm} mm olabilir; BC kaydetmez.` });
  }
  if (design.elements.length === 0) {
    warnings.push({ elementId: null, message: "Etiket boş: soldaki paletten öğe sürükleyin." });
  }
  for (const el of design.elements) {
    const name = elementName(design, el);
    const add = (message: string) => warnings.push({ elementId: el.id, message: `${name} — ${message}` });
    if (!isKnownType(el.type)) {
      add(`bilinmeyen öğe türü (${el.type}); tasarımcı bunu çizemez ama korur.`);
      continue;
    }
    // BC sınırları: aşan değer kaydı hatayla durdurur.
    if (el.id.length > LIMITS.id) add(`öğe kimliği ${LIMITS.id} karakteri aşıyor; BC kaydetmez.`);
    if (el.text.length > LIMITS.text) add(`metin ${LIMITS.text} karakteri aşıyor; BC kaydetmez.`);
    if (el.field.length > LIMITS.field) add(`alan adı ${LIMITS.field} karakteri aşıyor; BC kaydetmez.`);
    if (el.prefix.length > LIMITS.prefix) add(`ön ek ${LIMITS.prefix} karakteri aşıyor; BC kaydetmez.`);
    if (el.suffix.length > LIMITS.suffix) add(`son ek ${LIMITS.suffix} karakteri aşıyor; BC kaydetmez.`);
    if (!el.enabled) continue;

    const geo = elementGeometry(el, ctx);
    const e = geo.extent;
    if (e.x < -EPS || e.y < -EPS || e.x + e.w > design.widthMm + EPS || e.y + e.h > design.heightMm + EPS) {
      add("etiketin dışına taşıyor, kesilecek.");
    }

    if (el.field && fieldKeys.size > 0 && !fieldKeys.has(el.field)) {
      add(`“${el.field}” alanı bu etiket türünde yok, boş basılır.`);
    }

    const value = resolveValue(el, ctx.values);
    switch (el.type) {
      case "text":
        if (el.text.trim() === "") add("metin boş.");
        break;
      case "field":
        if (!el.field) add("veri alanı seçilmedi.");
        break;
      case "barcode":
      case "qr":
        if (!el.field && el.text.trim() === "") add("veri seçilmedi (alan veya sabit veri girin).");
        break;
      case "image":
        if (!el.imageId) add("resim seçilmedi.");
        else if (!imageIds.has(el.imageId))
          add(el.imageId === "COMPANY" ? "şirket logosu henüz yok: “Şirket logosunu getir”e tıklayın." : "resim bulunamadı; yeniden yükleyin.");
        break;
      default:
        break;
    }

    if ((el.type === "text" || el.type === "field") && value !== "") {
      const t = layoutText(el, value, ctx);
      if (t.overflow) add("yazı kutuya sığmıyor (satırlar üst üste basılır). Yazıyı küçültün, kutuyu genişletin ya da “Genişliğe sığdır”ı açın.");
      if (t.truncated) add(`örnek değer ${el.maxLines} satıra sığmıyor, sonu kesilecek.`);
    }
    if (el.type === "barcode" && value !== "") {
      const b = layoutBarcode(el, value, ctx);
      if (el.symbology === "ean13") {
        const st = ean13Status(value.replace(/ /g, ""));
        if (st === "invalid") add("örnek değer EAN-13 değil (12-13 rakam gerekli); BC bunu Code128 basar.");
        else if (st === "badCheck") add("örnek EAN-13 değerinin kontrol hanesi hatalı; yazıcı doğrusunu hesaplar.");
      }
      if (b && b.barWidth > b.boxW) add("barkod bu genişliğe sığmıyor; kutuyu genişletin.");
      if (b?.nonAscii) add("barkodda Türkçe/özel karakter var, okutulamayabilir.");
    }
    if (el.type === "qr" && value !== "") {
      const q = layoutQr(el, value, ctx);
      if (q && q.symbolSize > q.side) add("QR bu boyuta sığmıyor; büyütün.");
    }
  }
  return warnings;
}
