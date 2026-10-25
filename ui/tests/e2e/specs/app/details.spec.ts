import { expect, test } from "@playwright/test";
import { TEST_APP_NAME } from "../constants";

test.describe("App Details Page", () => {
  const targetApp = TEST_APP_NAME;

  test.beforeEach(async ({ page }) => {
    await page.goto(`./app/${targetApp}`);
  });

  test("shows app title and description", async ({ page }) => {
    await expect(page.getByTestId("app-title")).toBeVisible();
    await expect(page.getByTestId("app-description")).toBeVisible();
  });

  test("shows resources section with links", async ({ page }) => {
    const resources = page.locator("#resources");
    await expect(resources).toBeVisible();

    const links = resources.locator("a");
    await expect(await links.count()).toBeGreaterThan(0);

    const recipeLink = resources.locator("a", { hasText: /Forge Recipe/i });
    await expect(recipeLink).toBeVisible();
    await expect(recipeLink).toHaveAttribute("href", new RegExp(`blob/.*/recipes/apps/${TEST_APP_NAME}/recipe.nix`));
  });

  test("shows screenshots with captions and links to the full images", async ({ page }) => {
    // mock-test in mock data has two screenshots
    const screenshots = page.getByTestId("app-screenshots");
    await expect(screenshots).toBeVisible();
    await expect(screenshots.locator("figcaption")).toHaveText(["Mock screenshot.", "Second mock screenshot."]);
    const path = `resources/apps/${TEST_APP_NAME}/screenshots`;
    for (const index of [0, 1]) {
      await expect(screenshots.locator("a").nth(index)).toHaveAttribute("href", `${path}/${index}.webp`);
      await expect(screenshots.locator("img").nth(index)).toHaveAttribute("src", `${path}/${index}-thumb.webp`);
    }
    await expect(screenshots.locator("img").first()).toHaveAttribute("alt", "Mock screenshot.");
  });

  test("shows buttons that scroll the screenshots", async ({ page }) => {
    const rowId = await page.getByTestId("app-screenshots").getAttribute("id");
    for (const name of ["Show the previous screenshots", "Show the next screenshots"]) {
      const button = page.getByRole("button", { name });
      await expect(button).toBeVisible();
      await expect(button).toHaveAttribute("aria-controls", rowId!);
      await button.click();
    }
  });

  test("shows NGI grants section if available", async ({ page }) => {
    // mock-test in mock data has grants
    const grants = page.locator("#grants");
    await expect(grants).toBeVisible();
    await expect(grants).toContainText(/NGI Grants/i);
  });

  test("navigation via resources anchor link", async ({ page }) => {
    const resourcesAnchor = page.locator("#resources .anchor-link");
    await resourcesAnchor.click();
    await expect(page).toHaveURL(new RegExp(`#resources$`));
  });
});
