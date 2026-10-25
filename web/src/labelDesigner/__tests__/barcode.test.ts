import { describe, expect, it } from "vitest";
import { code128Symbols, ean13CheckDigit, ean13Status, encodeCode128, encodeEan13, encodeGs1128, FNC1, isValidEan13 } from "../render/barcode";

describe("EAN-13", () => {
  it("kontrol hanesi", () => {
    expect(ean13CheckDigit("400638133393")).toBe(1);
    expect(ean13CheckDigit("869000001234")).toBe(3);
    expect(ean13CheckDigit("590123412345")).toBe(7);
    expect(() => ean13CheckDigit("12345")).toThrow();
  });

  it("doğrulama", () => {
    expect(isValidEan13("4006381333931")).toBe(true);
    expect(isValidEan13("5901234123457")).toBe(true);
    expect(isValidEan13("8690000012345")).toBe(false);
    expect(isValidEan13("400638133393")).toBe(false);
    expect(isValidEan13("400638133393X")).toBe(false);
    expect(ean13Status("400638133393")).toBe("computed");
    expect(ean13Status("4006381333931")).toBe("ok");
    expect(ean13Status("4006381333932")).toBe("badCheck");
    expect(ean13Status("AB-1")).toBe("invalid");
  });

  it("95 modül, korumalar ve kontrol hanesi yazıcı gibi hesaplanır", () => {
    const enc = encodeEan13("4006381333932"); // yanlış kontrol → yazıcı doğrusunu basar
    expect(enc?.modules).toHaveLength(95);
    expect(enc?.text).toBe("4006381333931");
    expect(enc?.modules.slice(0, 3)).toBe("101");
    expect(enc?.modules.slice(45, 50)).toBe("01010");
    expect(enc?.modules.slice(92)).toBe("101");
    expect(encodeEan13("ABC")).toBeNull();
  });
});

describe("Code128 / GS1-128", () => {
  it("Wikipedia örneği (B kümesi) kontrol sembolü", () => {
    const s = code128Symbols("Wikipedia");
    expect(s[0]).toBe(104);
    expect(s[s.length - 2]).toBe(88);
    expect(s[s.length - 1]).toBe(106);
  });

  it("yalnız rakam → C kümesi, modül sayısı 11n+13", () => {
    const enc = encodeCode128("12345678");
    expect(enc.symbols[0]).toBe(105);
    expect(enc.symbols.slice(1, 5)).toEqual([12, 34, 56, 78]);
    expect(enc.modules.length).toBe(11 * 6 + 13);
  });

  it("GS1-128 FNC1 ile başlar, değişken AI sonrası ayırıcı", () => {
    const enc = encodeGs1128("(01)08690000000012(10)LOT1(21)A");
    expect(enc.symbols[0]).toBe(105);
    expect(enc.symbols[1]).toBe(102);
    expect(enc.text).toBe("(01)08690000000012(10)LOT1(21)A");
    // (10) değişken uzunluklu: ardından FNC1 (102) gelir
    expect(enc.symbols.filter((v) => v === 102).length).toBe(2);
    expect(encodeCode128(`${FNC1}01`).symbols.slice(0, 3)).toEqual([105, 102, 1]);
  });
});
