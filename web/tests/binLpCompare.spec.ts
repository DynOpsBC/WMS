import { expect, test, type Page } from "@playwright/test";

// Göz ve LP Karşılaştırma (BC control add-in). Önizleme modu örnek veriyle
// çalışır; "BC modu" testi sahte Microsoft.Dynamics.NAV ile köprüyü sınar.
// BINLP_SHOT_DIR verilirse ekran görüntüleri oraya yazılır.
const shotDir = process.env.BINLP_SHOT_DIR;
if (process.env.PW_CHANNEL) test.use({ channel: process.env.PW_CHANNEL });

async function shot(page: Page, name: string) {
  if (shotDir) await page.screenshot({ path: `${shotDir}/binlp-${name}.png`, fullPage: true });
}

test.describe("Göz ve LP Karşılaştırma", () => {
  test.use({ viewport: { width: 1440, height: 900 } });

  test("özet çipleri, renkli satırlar ve geri alınan mal kabul düzeltmesi", async ({ page }) => {
    await page.goto("/src/binLpCompare/index.html");
    await expect(page.getByRole("heading", { name: "Göz ve LP Karşılaştırma" })).toBeVisible();
    const phantom = page.locator("tr.blc-row", { hasText: "K.K03.11" });
    await expect(phantom).toHaveClass(/tone-red/);
    await expect(phantom).toContainText("+45.000");
    await expect(page.locator(".blc-chip", { hasText: "LP fazla" })).toContainText("2");
    // Yalnız farklar: eşit ve nedensiz satır (K.K03.12) gizli.
    await expect(page.locator("tr.blc-row", { hasText: "K.K03.12" })).toHaveCount(0);
    await shot(page, "overview");

    await phantom.click();
    const repair = page.getByRole("button", { name: /Geri alınan mal kabul LP'lerini boşalt/ });
    await expect(repair).toBeVisible();
    await expect(page.getByText("LP0001907").first()).toBeVisible();
    await shot(page, "expanded-undone-receipt");

    await repair.click();
    await expect(page.getByRole("status")).toContainText("1 LP satırı boşaltıldı.");
    await expect(page.locator("tr.blc-row", { hasText: "K.K03.11" })).toHaveCount(0);
  });

  test("yetim atama satırı ve serbest bırakma", async ({ page }) => {
    await page.goto("/src/binLpCompare/index.html");
    const orphan = page.locator("tr.blc-row", { hasText: "RCV-01" });
    await expect(orphan).toContainText("Yetim atama");
    await orphan.click();
    await expect(page.getByText("Belge artık yok", { exact: true })).toBeVisible();
    await shot(page, "expanded-orphan");
    await page.getByRole("button", { name: "Yetim atamayı serbest bırak" }).click();
    await expect(page.getByRole("status")).toContainText("1 LP serbest bırakıldı.");
  });

  test("lot uyuşmazlığı ve başka göz nedenleri, durum çipi süzgeci", async ({ page }) => {
    await page.goto("/src/binLpCompare/index.html");
    await page.locator(".blc-chip", { hasText: "Önerilen düzeltme" }).click();
    await expect(page.locator("tr.blc-row")).toHaveCount(6);
    await page.locator("tr.blc-row", { hasText: "LT-0912" }).click();
    await expect(page.getByRole("heading", { name: "Lot uyuşmazlığı" })).toBeVisible();
    await shot(page, "expanded-lot-mismatch");
  });

  test("yalnız farklar kapalıyken eşit satırlar yeşil görünür", async ({ page }) => {
    await page.goto("/src/binLpCompare/index.html");
    await expect(page.locator("tr.blc-row").first()).toBeVisible();
    await page.getByText("Yalnız farklar").click();
    const equal = page.locator("tr.blc-row", { hasText: "K.K03.12" });
    await expect(equal).toHaveClass(/tone-green/);
    await shot(page, "all-rows");
  });

  test("lokasyon seçilmeden boş durum", async ({ page }) => {
    await page.goto("/src/binLpCompare/index.html?state=empty");
    await expect(page.getByRole("heading", { name: "Bir lokasyon seçin" })).toBeVisible();
    await shot(page, "needs-location");
  });

  test("dar ekran", async ({ page }) => {
    await page.setViewportSize({ width: 820, height: 1000 });
    await page.goto("/src/binLpCompare/index.html");
    await page.locator("tr.blc-row", { hasText: "K.K05.01" }).click();
    await expect(page.getByRole("heading", { name: "Başka gözde" })).toBeVisible();
    await shot(page, "narrow");
  });

  test("BC modu: ControlReady, SetData ve olaylar", async ({ page }) => {
    await page.addInitScript(() => {
      const calls: Array<{ name: string; args: unknown[] }> = [];
      (window as unknown as { __calls: typeof calls }).__calls = calls;
      (window as unknown as { Microsoft: unknown }).Microsoft = {
        Dynamics: { NAV: { InvokeExtensibilityMethod: (name: string, args: unknown[]) => calls.push({ name, args }) } },
      };
    });
    await page.goto("/src/binLpCompare/index.html");
    const calls = () => page.evaluate(() => (window as unknown as { __calls: Array<{ name: string; args: unknown[] }> }).__calls);
    await expect.poll(async () => (await calls()).map((c) => c.name)).toContain("ControlReady");

    await page.evaluate(() => {
      const w = window as unknown as { SetData: (json: string) => void };
      w.SetData(
        JSON.stringify({
          location: "WH1", onlyDiff: true, generatedAt: "2026-10-22T07:00:00Z", traceabilityAvailable: false,
          locations: [{ code: "WH1", name: "Depo 1" }], zones: [],
          summary: { rows: 1, lpOver: 1, lpTotal: 20, stockTotal: 10, lpSurplusQty: 10, bins: 1, lps: 1, orphanLps: 0, reasonRows: 0 },
          rows: [{ id: 1, bin: "A-01", item: "I1", description: "Madde", lot: "", uom: "PCS", stock: 10, lp: 20, diff: 10, lpCount: 1,
            status: "lpOver", reason: "none", lines: [{ lpNo: "LPX", lpStatus: "Built", qty: 2, uom: "BOX", qtyBase: 20, lineNo: 10000 }] }],
          truncated: false,
        }),
      );
    });
    const row = page.locator("tr.blc-row", { hasText: "A-01" });
    await expect(row).toContainText("+10");
    await row.click();
    await expect(page.getByRole("button", { name: "İzlenebilirlik" })).toHaveCount(0);
    await page.getByRole("button", { name: "LP'yi aç" }).first().click();
    await page.getByRole("button", { name: "Göz içeriğini aç" }).click();
    await page.getByRole("button", { name: "Excel'e aktar" }).click();
    await page.getByRole("button", { name: "Karşılaştır" }).click();
    await expect.poll(async () => (await calls()).map((c) => c.name)).toEqual(
      expect.arrayContaining(["OpenLp", "OpenBinContent", "ExportExcel", "Compare"]),
    );
    const all = await calls();
    expect(all.find((c) => c.name === "OpenLp")?.args).toEqual(["LPX"]);
    expect(all.find((c) => c.name === "OpenBinContent")?.args).toEqual(["WH1", "A-01", "I1", ""]);
    expect(JSON.parse(String(all.find((c) => c.name === "Compare")?.args[0]))).toMatchObject({ location: "WH1", onlyDiff: true });

    await page.evaluate(() =>
      (window as unknown as { NotifyResult: (json: string) => void }).NotifyResult(
        JSON.stringify({ kind: "error", message: "Filtre geçersiz" }),
      ),
    );
    await expect(page.getByRole("alert")).toContainText("Filtre geçersiz");
  });
});
