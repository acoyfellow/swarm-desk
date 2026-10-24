import { chromium } from "playwright-core";

const base = process.argv[2] ?? "http://localhost:8820";
const accessToken = process.env.ACCESS_TOKEN ?? "";
const outDir = process.argv[3] ?? ".real";

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, extraHTTPHeaders: accessToken ? { "cf-access-token": accessToken } : {} });
const page = await context.newPage();
await page.goto(base + "/");
await page.waitForTimeout(800);
await page.getByRole("button", { name: "Go" }).click();
await page.waitForFunction(() => /^done/.test(document.getElementById("status").textContent), null, { timeout: 90000 });
const stats = await page.evaluate(() => Object.fromEntries(["oAct", "oHuman", "oBlock", "oWrong", "mDone", "mCost", "mErr", "clock"].map((id) => [id, document.getElementById(id).textContent])));
const attackId = await page.evaluate(() => document.querySelector(".dot.blocked")?.dataset.id);
if (attackId) await page.click(`#d${attackId}`);
await page.screenshot({ path: `${outDir}/demo-desktop.png`, fullPage: true });

await page.getByRole("button", { name: "Hidden order" }).click();
await page.getByRole("button", { name: "Send to one agent" }).click();
await page.waitForFunction(() => document.querySelector("#tryOut .verdict"), null, { timeout: 30000 });
const tryVerdict = await page.evaluate(() => document.querySelector("#tryOut .verdict").innerText.replace(/\s+/g, " "));
await page.locator("#tryOut").scrollIntoViewIfNeeded();
await page.screenshot({ path: `${outDir}/demo-try.png` });

const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, extraHTTPHeaders: accessToken ? { "cf-access-token": accessToken } : {} });
const mobile = await phone.newPage();
await mobile.goto(base + "/");
await mobile.waitForTimeout(1500);
const overflow = await mobile.evaluate(() => document.documentElement.scrollWidth - innerWidth);
await mobile.screenshot({ path: `${outDir}/demo-phone.png`, fullPage: true });

console.log(JSON.stringify({ stats, attackId, tryVerdict, phoneOverflowPx: overflow }));
await browser.close();
