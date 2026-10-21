// Tasarımdaki resimleri (dataUrl) arka planda çözer; çözüldükçe sürüm artar.
import { useCallback, useEffect, useRef, useState } from "react";
import type { LabelImage } from "../model/types";
import { loadImage } from "../render/imageRaster";

interface Entry {
  dataUrl: string;
  img: HTMLImageElement | null;
  promise: Promise<HTMLImageElement | null>;
}

export function useDecodedImages(images: readonly LabelImage[]) {
  const cache = useRef(new Map<string, Entry>());
  const [version, setVersion] = useState(0);

  const ensure = useCallback((image: LabelImage): Promise<HTMLImageElement | null> => {
    const hit = cache.current.get(image.id);
    if (hit && hit.dataUrl === image.dataUrl) return hit.promise;
    const entry: Entry = { dataUrl: image.dataUrl, img: null, promise: Promise.resolve(null) };
    entry.promise = image.dataUrl
      ? loadImage(image.dataUrl)
          .then((img) => {
            entry.img = img;
            setVersion((v) => v + 1);
            return img;
          })
          .catch(() => null)
      : Promise.resolve(null);
    cache.current.set(image.id, entry);
    return entry.promise;
  }, []);

  useEffect(() => {
    for (const img of images) if (img.dataUrl) void ensure(img);
  }, [images, ensure]);

  const get = useCallback((image: LabelImage): HTMLImageElement | null => {
    const hit = cache.current.get(image.id);
    return hit && hit.dataUrl === image.dataUrl ? hit.img : null;
  }, []);

  return { get, ensure, version };
}
