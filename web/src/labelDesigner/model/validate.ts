// Kaydı engellemeyen uyarılar: etiket dışına taşan eleman, bilinmeyen alan,
// boş metin, sığmayan yazı, geçersiz EAN-13 vb.
import { elementName, isKnownType, resolveValue } from "./design";
import { edgeClearanceMm, labelDots, layoutBarcode, layoutQr, layoutText, overflowDots, type LayoutContext } from "./layout";
import { LIMITS, type LabelDesign } from "./types";
import { dotsPerMm, formatDecimal } from "./units";
import { ean13Status } from "../render/barcode";

/** error = baskıda kesilir/BC kaydetmez, warn = kontrol edin, info = öneri (güvenli kenar). */
export type WarningLevel = "error" | "warn" | "info";
export type WarningCode = "overflow" | "margin" | "other";

export interface Warning {
  elementId: string | null;
  message: string;
  level: WarningLevel;
  code: WarningCode;
}

export interface ValidateOptions {
  /** Güvenli kenar (mm): yazı/barkod/QR/resim kenara bundan yakınsa öneri. 0 = kapalı. */
  safeMarginMm?: number;
}

/** Yazıcının etiketi kaydırma payı (±1 mm) + pay: varsayılan güvenli kenar. */
export const DEFAULT_SAFE_MARGIN_MM = 1.5;

export function validateDesign(design: LabelDesign, ctx: LayoutContext, opts: ValidateOptions = {}): Warning[] {
  const safe = opts.safeMarginMm ?? 0;
  const warnings: Warning[] = [];
  const L = labelDots(ctx);
  const dpm = dotsPerMm(ctx.dpi);
  const fieldKeys = new Set(design.fields.map((f) => f.key));
  const imageIds = new Set(design.images.map((i) => i.id));
  if (design.widthMm > LIMITS.widthMm || design.heightMm > LIMITS.heightMm) {
    warnings.push({ elementId: null, message: `Etiket en çok ${LIMITS.widthMm} × ${LIMITS.heightMm} mm olabilir; BC kaydetmez.`, level: "error", code: "other" });
  }
  if (design.dpi !== 203) {
    warnings.push({
      elementId: null,
      message: `${design.dpi} dpi seçili: yazıcı 203 dpi ise (Zebra ZD230, ZD220, ZQ630) etiket ${formatDecimal(Math.round((dotsPerMm(design.dpi) / 8) * 100) / 100)} kat büyük basılır ve sığmaz. Yazıcınızın çözünürlüğünü seçin.`,
      level: "warn",
      code: "other",
    });
  }
  if (design.elements.length === 0) {
    warnings.push({ elementId: null, message: "Etiket boş: soldaki paletten öğe sürükleyin.", level: "info", code: "other" });
  }
  for (const el of design.elements) {
    const name = elementName(design, el);
    const add = (message: string, level: WarningLevel = "warn", code: WarningCode = "other") =>
      warnings.push({ elementId: el.id, message: `${name} — ${message}`, level, code });
    if (!isKnownType(el.type)) {
      add(`bilinmeyen öğe türü (${el.type}); tasarımcı bunu çizemez ama korur.`);
      continue;
    }
    // BC sınırları: aşan değer kaydı hatayla durdurur.
    if (el.id.length > LIMITS.id) add(`öğe kimliği ${LIMITS.id} karakteri aşıyor; BC kaydetmez.`, "error");
    if (el.text.length > LIMITS.text) add(`metin ${LIMITS.text} karakteri aşıyor; BC kaydetmez.`, "error");
    if (el.field.length > LIMITS.field) add(`alan adı ${LIMITS.field} karakteri aşıyor; BC kaydetmez.`, "error");
    if (el.prefix.length > LIMITS.prefix) add(`ön ek ${LIMITS.prefix} karakteri aşıyor; BC kaydetmez.`, "error");
    if (el.suffix.length > LIMITS.suffix) add(`son ek ${LIMITS.suffix} karakteri aşıyor; BC kaydetmez.`, "error");
    if (!el.enabled) continue;

    // Taşma yazıcı noktasıyla ölçülür: BC ^PW×^LL (80×40 mm @203 dpi = 640×320).
    const over = overflowDots(el, ctx);
    if (over > 0) {
      add(`etiketin dışına ${formatDecimal(Math.max(0.01, over / dpm))} mm taşıyor (${L.w} × ${L.h} nokta); yazıcı bu kısmı basamaz.`, "error", "overflow");
    } else if (safe > 0 && el.type !== "box" && el.type !== "line" && !el.inverted) {
      // Kutu/çizgi ve siyah şerit üstündeki ters yazı kenara dayanabilir (şerit taşar).
      const clear = edgeClearanceMm(el, ctx);
      if (clear < safe - 0.01) {
        add(`kenara ${formatDecimal(Math.max(0, clear))} mm yakın (güvenli kenar ${formatDecimal(safe)} mm). Yazıcı etiketi biraz kaydırırsa kesilebilir.`, "info", "margin");
      }
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
