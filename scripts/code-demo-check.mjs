import { chromium } from "playwright-core";

const base = process.argv[2] ?? "http://localhost:8820";
const outDir = process.argv[3] ?? ".real";
const headers = process.env.ACCESS_TOKEN ? { "cf-access-token": process.env.ACCESS_TOKEN } : {};

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, extraHTTPHeaders: headers });
const page = await context.newPage();
await page.goto(`${base}/code`);
await page.waitForTimeout(800);
await page.getByRole("button", { name: "Go: 16 agents" }).click();
await page.waitForTimeout(9000);
await page.screenshot({ path: `${outDir}/code-mid.png`, fullPage: true });
const working = await page.evaluate(() => document.querySelectorAll('.task[data-s="working"]').length);
await page.waitForFunction(() => /^done/.test(document.getElementById("status").textContent), null, { timeout: 600000 });
const stats = await page.evaluate(() => Object.fromEntries(["oShip", "oPerson", "oHidden", "oWrong", "mDone", "mTools", "mTests", "mCost", "clock"].map((id) => [id, document.getElementById(id).textContent])));
await page.click(".task[data-s='ship']");
await page.waitForTimeout(300);
await page.screenshot({ path: `${outDir}/code-done.png`, fullPage: true });

const phone = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, extraHTTPHeaders: headers });
const mobile = await phone.newPage();
await mobile.goto(`${base}/code`);
await mobile.waitForTimeout(1200);
const overflow = await mobile.evaluate(() => document.documentElement.scrollWidth - innerWidth);
await mobile.screenshot({ path: `${outDir}/code-phone.png`, fullPage: false });

console.log(JSON.stringify({ workingAt9s: working, stats, phoneOverflowPx: overflow }));
await browser.close();
