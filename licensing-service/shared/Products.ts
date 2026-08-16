// The products this licensing service issues keys for.
//
// The service was born as the BCWMSApp backbone and is now the shared licensing spine
// for the DynOpsBC product family. Adding a product here is deliberate and reviewed:
// issue rejects unknown names so a typo cannot mint a key no extension will ever accept,
// and verify refuses cross-product keys so a WMS Enterprise key cannot unlock another
// product's paid tier.
export const KNOWN_PRODUCTS = ["BCWMSApp", "BCTraining"] as const;

export type KnownProduct = (typeof KNOWN_PRODUCTS)[number];

export function isKnownProduct(product: string): product is KnownProduct {
  return (KNOWN_PRODUCTS as readonly string[]).includes(product);
}
