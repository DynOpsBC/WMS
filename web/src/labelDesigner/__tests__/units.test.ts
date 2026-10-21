import { describe, expect, it } from "vitest";
import { CSS_PX_PER_MM, dotsPerMm, formatDecimal, mmToDots, mmToPx, parseDecimal, pxToMm, snapMm } from "../model/units";
import { fitFontMeasured, glyphUnits, maxChars, qrMagnification, qrModules, wrapText } from "../model/zplMetrics";

describe("mm ↔ px / nokta ölçekleme", () => {
  it("%100 yakınlaştırmada 25,4 mm = 96 CSS piksel", () => {
    expect(mmToPx(25.4, 1)).toBeCloseTo(96, 6);
    expect(mmToPx(10, 2)).toBeCloseTo(20 * CSS_PX_PER_MM, 6);
    expect(pxToMm(mmToPx(37.5, 3.25), 3.25)).toBeCloseTo(37.5, 9);
  });

  it("BC ile aynı nokta çevirisi: 203 dpi = 8, 300 dpi = 12 nokta/mm", () => {
    expect(dotsPerMm(203)).toBe(8);
    expect(dotsPerMm(300)).toBe(12);
    expect(dotsPerMm(0)).toBe(8);
    expect(mmToDots(80, 203)).toBe(640);
    expect(mmToDots(40, 300)).toBe(480);
    expect(mmToDots(2.75, 203)).toBe(22);
    expect(mmToDots(-3, 203)).toBe(0);
    expect(mmToDots(0.06, 203)).toBe(0);
  });

  it("ızgaraya yapıştırma ve Türkçe ondalık", () => {
    expect(snapMm(12.26, 0.5)).toBe(12.5);
    expect(snapMm(12.24, 0.5)).toBe(12);
    expect(snapMm(12.26, 1)).toBe(12);
    expect(snapMm(12.2649, 0)).toBe(12.26);
    expect(parseDecimal("2,5")).toBe(2.5);
    expect(parseDecimal("abc")).toBeNull();
    expect(formatDecimal(2.5)).toBe("2,5");
  });
});

describe("BC Label Canvas ölçümleri", () => {
  it("font 0 harf genişlikleri ve sığdırma", () => {
    expect(glyphUnits("SK-10025")).toBe(56 + 56 + 91 + 48 * 5);
    // 53 mm (424 nokta) kolona 32 noktalık yazı sığar mı?
    expect(fitFontMeasured("SK-10025", 424, 32, 18)).toBe(32);
    expect(fitFontMeasured("ÇOK UZUN BİR ÜRÜN NUMARASI 1234567890", 200, 32, 18)).toBe(18);
    expect(maxChars(424, 22)).toBe(35);
  });

  it("kelime kaydırma BC WrapText ile aynı", () => {
    expect(wrapText("ÖRNEK ÜRÜN AÇIKLAMASI 500 ML ŞİŞE", 20, 2)).toEqual(["ÖRNEK ÜRÜN", "AÇIKLAMASI 500 ML"]);
    expect(wrapText("  KISA  ", 20, 2)).toEqual(["KISA"]);
  });

  it("QR modül ve büyütme", () => {
    expect(qrModules("SK-10025")).toBe(21);
    expect(qrMagnification("SK-10025", 168)).toBe(8);
    expect(qrMagnification("x".repeat(40), 30)).toBe(2);
  });
});
