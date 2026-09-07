import { expect, test } from "@playwright/test";

// Exercise every workstation module with a controlled BC outage; no customer
// credentials or inventory writes are used by this regression suite.
for (const mode of ["empty", "offline"] as const) {
  test(`all menu modules remain usable with ${mode} BC responses`, async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (error) => errors.push(error.message));
    await page.addInitScript(() => localStorage.setItem("bcwms.token", "test-token-not-real"));
    await page.route("https://**/*", async (route) => {
      if (mode === "offline") return route.abort("internetdisconnected");
      return route.fulfill({ status: 200, contentType: "application/json", body: '{"value":[]}' });
    });
    await page.goto("/");
    const labels = await page.locator(".tiles .tile .label").allTextContents();
    expect(labels.length).toBe(17);
    for (const label of labels) {
      await page.locator(".tiles .tile").filter({ has: page.getByText(label, { exact: true }) }).click();
      await expect(page.getByRole("button", { name: "‹ Menü", exact: true })).toBeVisible();
      await expect(page.locator("main.content")).not.toBeEmpty();
      // Let each module's asynchronous initial request settle, then verify the
      // shell and back navigation survive rejected/empty data as well.
      await expect.poll(() => page.locator("main.content").innerText()).not.toBe("");
      await page.getByRole("button", { name: "‹ Menü", exact: true }).click();
      await expect(page.locator(".tiles .tile")).toHaveCount(17);
    }
    expect(errors).toEqual([]);
    await page.getByRole("button", { name: "Çıkış", exact: true }).click();
    await expect(page.locator(".tiles")).toHaveCount(0);
  });
}
