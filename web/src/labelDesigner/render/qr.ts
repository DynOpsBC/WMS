// QR matris üretimi (qrcode-generator, çevrimdışı paket). ZPL ^BQN,2,m ve
// ^FDLA, ile aynı: hata düzeltme L, bayt kipi, UTF-8 (^CI28).
import qrcode from "qrcode-generator";
import { qrModules } from "../model/zplMetrics";

qrcode.stringToBytes = qrcode.stringToBytesFuncs["UTF-8"];

export interface QrMatrix {
  size: number;
  dark: Uint8Array;
}

type TypeNumber = Parameters<typeof qrcode>[0];

const cache = new Map<string, QrMatrix | null>();

function build(data: string, typeNumber: TypeNumber): QrMatrix {
  const qr = qrcode(typeNumber, "L");
  qr.addData(data, "Byte");
  qr.make();
  const size = qr.getModuleCount();
  const dark = new Uint8Array(size * size);
  for (let r = 0; r < size; r += 1) {
    for (let c = 0; c < size; c += 1) dark[r * size + c] = qr.isDark(r, c) ? 1 : 0;
  }
  return { size, dark };
}

/** BC'nin tahmin ettiği sürümle dener; veri sığmazsa otomatik sürüm. */
export function qrMatrix(data: string): QrMatrix | null {
  if (cache.has(data)) return cache.get(data) ?? null;
  let result: QrMatrix | null = null;
  const version = ((qrModules(data) - 17) / 4) as TypeNumber;
  try {
    result = build(data, version);
  } catch {
    try {
      result = build(data, 0);
    } catch {
      result = null;
    }
  }
  if (cache.size > 200) cache.clear();
  cache.set(data, result);
  return result;
}
