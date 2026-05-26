import { expect, test } from "@playwright/test";

test("pick board renders mock BC data and emits reassign", async ({ page }) => {
  await page.route("**/picks?**", async (route) => {
    await route.fulfill({
      contentType: "application/json",
      body: JSON.stringify({
        value: [
          { no: "PICK-S5-0001", sourceNo: "SHIP-1001", assignedUserId: "MOBILE", status: "Open", percentComplete: 10 },
          { no: "PICK-S5-0002", sourceNo: "SHIP-1002", assignedUserId: "ADA", status: "InProgress", percentComplete: 60 },
        ],
      }),
    });
  });

  await page.goto("/src/pickBoard/index.html");
  await expect(page.getByRole("heading", { name: "Pick Board" })).toBeVisible();
  await expect(page.getByText("PICK-S5-0001")).toBeVisible();
  await page.evaluate(() => {
    window.postMessage({ type: "setData", payload: { picks: [{ no: "PICK-S5-0099", sourceNo: "SHIP-1099", assignedUserId: "MOBILE", status: "Open", percentComplete: 0 }] } }, "*");
  });
  await expect(page.getByText("PICK-S5-0099")).toBeVisible();
});
