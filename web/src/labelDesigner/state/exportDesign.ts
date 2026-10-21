// Giden DesignJson: resim elemanlarının ^GFA verisi eleman boyutu + dpi +
// döndürmeyle burada üretilir (BC resmi döndürmez, olduğu gibi basar).
import { serializeDesign } from "../model/design";
import type { LabelDesign, LabelImage } from "../model/types";
import { imageElementGf } from "../render/imageRaster";

export type ImageDecoder = (image: LabelImage) => Promise<HTMLImageElement | null>;

export async function withImageGf(design: LabelDesign, decode: ImageDecoder): Promise<LabelDesign> {
  const elements = await Promise.all(
    design.elements.map(async (el) => {
      if (el.type !== "image") return el;
      if (!el.imageId) return el.imageGf ? { ...el, imageGf: "" } : el;
      const image = design.images.find((i) => i.id === el.imageId);
      // dataUrl'si olmayan resim yalnız referanstır: mevcut ^GFA korunur.
      if (!image || !image.dataUrl) return el;
      const decoded = await decode(image);
      if (!decoded) return el;
      const imageGf = imageElementGf(el, image, decoded, design.dpi);
      return imageGf === el.imageGf ? el : { ...el, imageGf };
    }),
  );
  return { ...design, elements };
}

/** BC'ye gidecek JSON (readOnly yalnız BC → tasarımcı yönündedir, gönderilmez). */
export async function buildDesignJson(design: LabelDesign, decode: ImageDecoder): Promise<string> {
  const full = await withImageGf(design, decode);
  const { readOnly: _readOnly, ...rest } = full;
  void _readOnly;
  return serializeDesign(rest as LabelDesign);
}
