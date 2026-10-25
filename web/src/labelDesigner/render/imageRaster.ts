// Tarayıcıda resim çözme ve eleman boyutuna (dpi'ye göre nokta) indirgeme.
import type { LabelElement, LabelImage } from "../model/types";
import { mmToDots } from "../model/units";
import { monoToGfa, rgbaToMono, rotateMono, type MonoBitmap } from "./gf";

export function loadImage(dataUrl: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("Resim okunamadı"));
    img.src = dataUrl;
  });
}

/** Resmi w×h noktalık beyaz zemine oranını koruyarak ortalar, RGBA döndürür. */
export function rasterize(img: CanvasImageSource & { naturalWidth?: number; naturalHeight?: number; width: number; height: number }, w: number, h: number): Uint8ClampedArray {
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, w);
  canvas.height = Math.max(1, h);
  const g = canvas.getContext("2d", { willReadFrequently: true });
  if (!g) return new Uint8ClampedArray(canvas.width * canvas.height * 4);
  g.fillStyle = "#fff";
  g.fillRect(0, 0, canvas.width, canvas.height);
  const iw = img.naturalWidth || img.width;
  const ih = img.naturalHeight || img.height;
  if (iw > 0 && ih > 0) {
    const s = Math.min(canvas.width / iw, canvas.height / ih);
    const dw = iw * s;
    const dh = ih * s;
    g.imageSmoothingEnabled = true;
    g.imageSmoothingQuality = "high";
    g.drawImage(img, (canvas.width - dw) / 2, (canvas.height - dh) / 2, dw, dh);
  }
  return g.getImageData(0, 0, canvas.width, canvas.height).data;
}

const bitmapCache = new Map<string, MonoBitmap>();

/** Resim elemanının basılacak 1 bit hali (eleman boyutu, dpi, döndürme). */
export function imageElementBitmap(el: LabelElement, image: LabelImage, decoded: HTMLImageElement, dpi: number): MonoBitmap {
  const w = Math.max(1, mmToDots(el.wMm, dpi));
  const h = Math.max(1, mmToDots(el.hMm, dpi));
  const key = `${image.id}|${image.dataUrl.length}|${image.dataUrl.slice(-40)}|${w}|${h}|${el.rotation}`;
  const hit = bitmapCache.get(key);
  if (hit) return hit;
  const mono = rotateMono(rgbaToMono(rasterize(decoded, w, h), w, h), el.rotation);
  if (bitmapCache.size > 64) bitmapCache.clear();
  bitmapCache.set(key, mono);
  return mono;
}

export function imageElementGf(el: LabelElement, image: LabelImage, decoded: HTMLImageElement, dpi: number): string {
  return monoToGfa(imageElementBitmap(el, image, decoded, dpi));
}

const MAX_UPLOAD_SIDE = 1000;

/** Yüklenen dosyayı okur; çok büyükse 1000 piksele küçültüp PNG yapar. */
export async function readImageFile(file: File): Promise<{ dataUrl: string; width: number; height: number }> {
  const dataUrl = await new Promise<string>((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error("Dosya okunamadı"));
    reader.readAsDataURL(file);
  });
  const img = await loadImage(dataUrl);
  const iw = img.naturalWidth;
  const ih = img.naturalHeight;
  const longest = Math.max(iw, ih);
  if (longest <= MAX_UPLOAD_SIDE) return { dataUrl, width: iw, height: ih };
  const s = MAX_UPLOAD_SIDE / longest;
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(iw * s);
  canvas.height = Math.round(ih * s);
  const g = canvas.getContext("2d");
  if (!g) return { dataUrl, width: iw, height: ih };
  g.drawImage(img, 0, 0, canvas.width, canvas.height);
  return { dataUrl: canvas.toDataURL("image/png"), width: canvas.width, height: canvas.height };
}

/** Geliştirme modunda "şirket logosu" yerine kullanılan örnek logo. */
export function makeSampleLogo(): string {
  const canvas = document.createElement("canvas");
  canvas.width = 360;
  canvas.height = 160;
  const g = canvas.getContext("2d");
  if (!g) return "";
  g.fillStyle = "#fff";
  g.fillRect(0, 0, 360, 160);
  g.fillStyle = "#1a1a2e";
  g.beginPath();
  g.arc(80, 80, 62, 0, Math.PI * 2);
  g.fill();
  g.fillStyle = "#fff";
  g.font = "bold 70px Arial, sans-serif";
  g.textAlign = "center";
  g.textBaseline = "middle";
  g.fillText("Ş", 80, 84);
  g.fillStyle = "#1a1a2e";
  g.textAlign = "left";
  g.font = "bold 54px Arial, sans-serif";
  g.fillText("ÖRNEK A.Ş.", 156, 70);
  g.font = "26px Arial, sans-serif";
  g.fillText("şirket logosu", 160, 118);
  return canvas.toDataURL("image/png");
}
