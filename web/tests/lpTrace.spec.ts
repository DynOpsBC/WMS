import { expect, test, type Page } from "@playwright/test";

// LP İzlenebilirlik (BC control add-in "DOPSWHS LP Trace"). Önizleme sayfası
// (src/lpTrace/index.html) BC yerine örnek yükleri döndürür.
// LPTRACE_SHOT_DIR verilirse ekran görüntüleri oraya yazılır.
const shotDir = process.env.LPTRACE_SHOT_DIR;
if (process.env.PW_CHANNEL) test.use({ channel: process.env.PW_CHANNEL });

async function shot(page: Page, name: string) {
  if (shotDir) await page.screenshot({ path: `${shotDir}/lptrace-${name}.png`, fullPage: true });
}

async function search(page: Page, text: string) {
  await page.getByLabel("Arama").fill(text);
  await page.getByRole("button", { name: "Ara" }).click();
}

test.describe("LP İzlenebilirlik", () => {
  test.use({ viewport: { width: 1440, height: 900 }, locale: "tr-TR", timezoneId: "Europe/Istanbul" });

  test("boş durum örnekleri ve arama olayı", async ({ page }) => {
    await page.goto("/src/lpTrace/index.html");
    await expect(page.getByRole("heading", { name: "Bir LP'nin hikâyesini izleyin" })).toBeVisible();
    await shot(page, "empty");
    await search(page, "lptrace-yok");
    await expect(page.getByRole("heading", { name: /LPTRACE-YOK.*bulunamadı/ })).toBeVisible();
  });

  test("LP: yetim atama, karma kaynak, zaman çizelgesi ve BC'de açma", async ({ page }) => {
    await page.goto("/src/lpTrace/index.html");
    await search(page, "lp001740");
    await expect(page.locator(".lt-hero__no")).toContainText("LP001740");
    await expect(page.locator(".lt-hero")).toContainText("Yetim");
    await expect(page.locator(".lt-insight--error")).toContainText("PU001130");
    await expect(page.getByText("Bu LP 2 farklı kaynaktan doldu")).toBeVisible();
    await expect(page.locator(".lt-event")).toHaveCount(4);
    await expect(page.locator(".lt-strike")).toHaveText("PU001130");
    await expect(page.locator(".lt-doc--missing")).toContainText("PU001130");
    await shot(page, "lp");

    await page.getByRole("button", { name: "Kayıtlı ambar mal kabulü KAB000845", exact: true }).click();
    const opened = await page.evaluate(() => (window as unknown as { __lpTraceOpened?: unknown[] }).__lpTraceOpened);
    expect(opened).toEqual([["postedWhseReceipt", "KAB000845"]]);
  });

  test("lot ağacı: LP fazlası ve geri alınan giriş", async ({ page }) => {
    await page.goto("/src/lpTrace/index.html");
    await search(page, "A102511");
    await expect(page.locator(".lt-group")).toHaveClass(/lt-group--excess/);
    await expect(page.locator(".lt-group")).toContainText("LP fazlası 45.000");
    await expect(page.locator(".lt-lprow")).toHaveCount(12);
    await expect(page.locator(".lt-lprow").first()).toContainText("geri alınan girişte");
    await page.locator(".lt-lprow .lt-twisty").first().click();
    await expect(page.locator(".lt-lplines").first()).toContainText("geri alındı → 15412");
    await shot(page, "lot");
    await page.getByRole("button", { name: "Tüm LP'leri göster (90)" }).click();
    await expect(page.locator(".lt-lprow")).toHaveCount(90);
  });

  test("belge: geri alma ile boşalan LP'ler", async ({ page }) => {
    await page.goto("/src/lpTrace/index.html");
    await search(page, "109433");
    await expect(page.locator(".lt-summary h1")).toHaveText("Alış irsaliyesi 109433");
    await expect(page.locator(".lt-history li")).toHaveCount(30);
    await expect(page.getByText("45 LP · 45 geri alma ile boşaltıldı")).toBeVisible();
    await shot(page, "document");
  });

  test("dar ekran", async ({ page }) => {
    await page.setViewportSize({ width: 420, height: 900 });
    await page.goto("/src/lpTrace/index.html");
    await search(page, "LP001740");
    await expect(page.locator(".lt-hero__no")).toContainText("LP001740");
    await shot(page, "lp-narrow");
  });
});
