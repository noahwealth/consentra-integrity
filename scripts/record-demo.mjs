// Records the 90-second product demo against the LIVE site, with captions.
//   node scripts/record-demo.mjs https://web-sage-alpha-25.vercel.app
// Output: demo/raw.webm  →  ffmpeg → web/demo.mp4 (see bottom of file).
// One continuous take in one tab, so the video is a single file.
import { chromium } from "playwright";
import { mkdirSync, readdirSync, renameSync } from "node:fs";

const BASE = (process.argv[2] ?? "https://web-sage-alpha-25.vercel.app").replace(/\/$/, "");
const OUT = "demo";
mkdirSync(OUT, { recursive: true });

const browser = await chromium.launch({ headless: true });
const ctx = await browser.newContext({
  viewport: { width: 1280, height: 800 }, colorScheme: "light",
  recordVideo: { dir: OUT, size: { width: 1280, height: 800 } },
});
// Caption bar that survives navigations (text kept in sessionStorage).
await ctx.addInitScript(() => {
  const paint = () => {
    let el = document.getElementById("__cap");
    const t = sessionStorage.getItem("__cap") || "";
    if (!el) { el = document.createElement("div"); el.id = "__cap"; document.documentElement.appendChild(el);
      el.style.cssText = "position:fixed;left:50%;bottom:28px;transform:translateX(-50%);z-index:99999;max-width:900px;padding:12px 20px;border-radius:14px;background:rgba(17,17,24,.86);color:#fff;font:600 18px/1.35 -apple-system,BlinkMacSystemFont,'Segoe UI',Inter,sans-serif;text-align:center;box-shadow:0 10px 30px rgba(0,0,0,.3);transition:opacity .3s;pointer-events:none"; }
    el.textContent = t; el.style.opacity = t ? "1" : "0";
  };
  document.addEventListener("DOMContentLoaded", paint); setInterval(paint, 200);
});
const page = await ctx.newPage();
const cap = (t) => page.evaluate((t) => sessionStorage.setItem("__cap", t), t);
const wait = (ms) => page.waitForTimeout(ms);
const say = async (t, ms = 2600) => { await cap(t); await wait(ms); };
const smooth = (y) => page.evaluate((y) => window.scrollTo({ top: y, behavior: "smooth" }), y);

// 1 · Welcome
await page.goto(BASE + "/", { waitUntil: "networkidle" });
await say("Consentra — your health record, from every provider, in one passport.", 3200);
await say("Sign in with email, or explore with a fictional demo patient.", 2600);
await page.click("#btn-signin");
await page.waitForSelector("#view:not([hidden])", { timeout: 20000 });
await wait(800);

// 2 · Passport
await say("Noah's records live at three hospitals — London, Boston and Ithaca. They don't agree.", 3600);
await smooth(520); await say("Every provider's copy is kept as its own row. Nothing is merged.", 3000);
await smooth(0); await wait(600);

// 3 · Verify
await page.goto(BASE + "/#/scan"); await wait(900);
await say("Verify compares every copy, and checks each provider's data feed for gaps and delays.", 2400);
await page.click("#btn-scan");
await page.waitForFunction(() => !document.querySelector("#btn-scan")?.disabled || !document.querySelector("#btn-scan"), null, { timeout: 45000 }).catch(() => {});
await wait(2200);
await smooth(760); await say("Six findings. The most serious: a penicillin allergy one hospital doesn't know about.", 3600);

// 4 · Resolve
await page.goto(BASE + "/#/resolve"); await wait(1000);
await say("Each conflict side by side — with who recorded it, and when.", 2600);
const card = page.locator(".finding", { hasText: "Lisinopril" }).first();
await card.scrollIntoViewIfNeeded(); await wait(700);
await say("Boston has him on 20 mg. London on 10. He flags it for his doctor, with a note.", 2800);
await card.locator("textarea").fill("Boston raised my dose in October; London was never told.");
await wait(500);
await card.locator("button", { hasText: "Flag for provider review" }).click();
await wait(1800);

// 5 · Share
await page.goto(BASE + "/#/share"); await wait(1000);
await say("Share only what's needed, for as long as he chooses.", 2400);
await page.fill('input[type=text]', "Dr. Rivera, Mass General"); await wait(500);
await page.click("text=Create share");
await page.waitForSelector(".pass--qr a", { timeout: 15000 }); await wait(1200);
await say("A QR code or link — for one clinician, for 24 hours.", 2600);
const clinUrl = await page.getAttribute(".pass--qr a", "href");

// 6 · Clinician view
await page.goto(clinUrl); await wait(1600);
await say("The clinician sees verified records plainly — and anything in question, labeled.", 3200);
await smooth(700); await say("UK lab units appear with the US conversion beside them.", 2600);
const h = await page.evaluate(() => document.body.scrollHeight); await smooth(h); await wait(800);
await say("She needs labs too, so she asks. Nothing is shared without Noah's yes.", 2400);
await page.locator("#rq-cats label", { hasText: "Lab Results" }).click().catch(() => {});
await page.fill("#rq-who", "Dr. Rivera · Internal Medicine").catch(() => {});
await page.click("#rq-send").catch(() => {});
await wait(1500);

// 7 · Consent sheet → Allow
await page.goto(BASE + "/#/passport"); await wait(2500);
await page.waitForSelector(".sheet", { timeout: 15000 }).catch(() => {});
await say("Noah sees the request, keeps what he's comfortable with, and allows.", 2600);
await page.locator(".sheet .btn", { hasText: "Allow" }).click().catch(() => {});
await wait(1800);

// 8 · Activity
await page.goto(BASE + "/#/activity"); await wait(1200);
await say("Every share, view, request and decision is a receipt — chained, so it can't be quietly changed.", 3000);
await page.click("text=Verify receipts").catch(() => {}); await wait(2000);

// 9 · Revoke
await page.goto(BASE + "/#/share"); await wait(1200);
await page.locator(".btn--danger", { hasText: "Revoke" }).first().click().catch(() => {});
await wait(1200);
await page.goto(clinUrl); await wait(2000);
await say("Revoke — and the clinician's access ends. Immediately.", 3000);

// 10 · Close
await page.goto(BASE + "/#/passport"); await wait(900);
await say("Consentra. The trust layer for fragmented healthcare data.", 3600);
await cap(""); await wait(600);

await page.close(); await ctx.close(); await browser.close();
const f = readdirSync(OUT).filter((x) => x.endsWith(".webm")).sort().pop();
renameSync(`${OUT}/${f}`, `${OUT}/raw.webm`);
console.log(`recorded ${OUT}/raw.webm`);
// then:  ffmpeg -y -i demo/raw.webm -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart web/demo.mp4
