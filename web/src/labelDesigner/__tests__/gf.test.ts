import { describe, expect, it } from "vitest";
import { monoToGfa, parseGfa, rgbaToMono, rotateMono, type MonoBitmap } from "../render/gf";

function bitmap(rows: string[]): MonoBitmap {
  const height = rows.length;
  const width = rows[0].length;
  const bits = new Uint8Array(width * height);
  rows.forEach((row, y) => [...row].forEach((c, x) => (bits[y * width + x] = c === "#" ? 1 : 0)));
  return { width, height, bits };
}

describe("^GFA dönüşümü", () => {
  it("bilinen 10×3 bitmap → beklenen onaltılık veri", () => {
    // 10 nokta genişlik → satır başına 2 byte (son 6 bit dolgu)
    const bmp = bitmap([
      "#.........", // 1000 0000 | 00.. → 80 00
      "########.#", // 1111 1111 | 01.. → FF 40
      ".#.#.#.#.#", // 0101 0101 | 01.. → 55 40
    ]);
    expect(monoToGfa(bmp)).toBe("^GFA,6,6,2,8000FF405540");
  });

  it("8 noktalık tam byte ve boş satır", () => {
    expect(monoToGfa(bitmap(["########", "........"]))).toBe("^GFA,2,2,1,FF00");
  });

  it("RGBA %50 eşik: koyu → siyah, açık ve saydam → beyaz", () => {
    const rgba = new Uint8ClampedArray([
      0, 0, 0, 255, // siyah
      127, 127, 127, 255, // eşiğin altı → siyah
      128, 128, 128, 255, // eşik → beyaz
      255, 255, 255, 255, // beyaz
      0, 0, 0, 0, // saydam siyah → beyaz zemin
      0, 0, 0, 200, // çoğunlukla opak siyah → siyah
    ]);
    const mono = rgbaToMono(rgba, 6, 1);
    expect([...mono.bits]).toEqual([1, 1, 0, 0, 0, 1]);
    expect(monoToGfa(mono)).toBe("^GFA,1,1,1,C4");
  });

  it("90° döndürme saat yönünde (ZPL R)", () => {
    const src = bitmap(["##.", "..."]); // 3×2
    const r = rotateMono(src, 90); // 2×3
    expect(r.width).toBe(2);
    expect(r.height).toBe(3);
    // sol üstteki iki nokta sağ sütunun üstüne gelir
    expect([...r.bits]).toEqual([0, 1, 0, 1, 0, 0]);
    expect(rotateMono(rotateMono(r, 270), 0).bits).toEqual(src.bits);
    expect([...rotateMono(src, 180).bits]).toEqual([0, 0, 0, 0, 1, 1]);
  });

  it("^GFA geri okunabilir", () => {
    const gf = monoToGfa(bitmap(["#.#.#.#.#", "........#"]));
    const back = parseGfa(gf);
    expect(back?.height).toBe(2);
    expect(back?.width).toBe(16);
    expect(back?.bits[0]).toBe(1);
    expect(back?.bits[16 + 8]).toBe(1);
    expect(parseGfa("^GFA,2,2,1,FF")).toBeNull();
  });
});
