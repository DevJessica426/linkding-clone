#!/usr/bin/env node
// Compares screenshots of the same pages on a real linkding and on this
// clone, pixel by pixel, at a desktop and a phone width. Writes each pair
// and a diff image (differing pixels in red) to OUT_DIR, and prints the
// share of pixels that differ; exit status 1 when any pixel does. Runs at
// the end of tool/web_parity.sh, on its data.
//
//   NODE_PATH=$(npm root -g) node tool/screenshot_parity.js \
//       REF_BASE CLONE_BASE OUT_DIR
//
// Differences in text that is different by nature (API token keys, the
// feed URL) are hidden before the screenshot on both sides.
const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

const PASSWORD = process.env.LD_PARITY_PASSWORD || "Parity-pass-2026";

const PAGES = [
  ["bookmarks", "/bookmarks"],
  ["bookmarks-page-2", "/bookmarks?page=2"],
  ["search", "/bookmarks?q=%23python"],
  ["archived", "/bookmarks/archived"],
  ["shared", "/bookmarks/shared"],
  ["details", "/bookmarks?details=1003"],
  ["new-bookmark", "/bookmarks/new"],
  ["tags", "/tags"],
  ["bundles", "/bundles"],
  ["new-bundle", "/bundles/new"],
  ["settings", "/settings/general"],
  ["integrations", "/settings/integrations"],
  ["change-password", "/change-password/"],
];

const VIEWPORTS = [
  ["desktop", { width: 1280, height: 900 }],
  ["phone", { width: 390, height: 844 }],
];

// Text that differs between any two installations.
const MASK = [
  "input[value^='http'][readonly]",
  "code",
  "td:nth-child(2)",
];

async function capture(browser, base, viewport) {
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  await page.goto(base + "/login/");
  await page.fill("#id_username", "admin");
  await page.fill("#id_password", PASSWORD);
  await Promise.all([page.waitForURL(/\/bookmarks$/), page.click("input[type=submit]")]);
  const shots = {};
  for (const [name, url] of PAGES) {
    await page.goto(base + url);
    await page.waitForTimeout(400);
    // No caret blinking or hover state in the picture.
    await page.mouse.move(0, 0);
    await page.evaluate(() => document.activeElement?.blur());
    await page.addStyleTag({ content: "*{caret-color:transparent!important;transition:none!important;animation:none!important}" });
    shots[name] = await page.screenshot({
      fullPage: true,
      mask: MASK.map((s) => page.locator(s)),
    });
  }
  await context.close();
  return shots;
}

// Compares two PNGs in the browser: the share of pixels whose colour
// differs noticeably, and a diff image.
async function compare(page, a, b) {
  return page.evaluate(
    async ([a, b]) => {
      const load = (data) =>
        new Promise((resolve) => {
          const img = new Image();
          img.onload = () => resolve(img);
          img.src = "data:image/png;base64," + data;
        });
      const [ia, ib] = [await load(a), await load(b)];
      const w = Math.max(ia.width, ib.width);
      const h = Math.max(ia.height, ib.height);
      const pixels = (img) => {
        const c = document.createElement("canvas");
        c.width = w;
        c.height = h;
        const ctx = c.getContext("2d");
        ctx.fillStyle = "#ff00ff";
        ctx.fillRect(0, 0, w, h);
        ctx.drawImage(img, 0, 0);
        return ctx.getImageData(0, 0, w, h);
      };
      const pa = pixels(ia).data;
      const pb = pixels(ib).data;
      const out = document.createElement("canvas");
      out.width = w;
      out.height = h;
      const octx = out.getContext("2d");
      const diff = octx.createImageData(w, h);
      let differing = 0;
      for (let i = 0; i < pa.length; i += 4) {
        const delta =
          Math.abs(pa[i] - pb[i]) + Math.abs(pa[i + 1] - pb[i + 1]) + Math.abs(pa[i + 2] - pb[i + 2]);
        if (delta > 48) {
          differing++;
          diff.data.set([255, 0, 0, 255], i);
        } else {
          const grey = (pa[i] + pa[i + 1] + pa[i + 2]) / 3;
          diff.data.set([grey, grey, grey, 64], i);
        }
      }
      octx.putImageData(diff, 0, 0);
      return {
        sizes: [ia.width + "x" + ia.height, ib.width + "x" + ib.height],
        differing,
        share: differing / (w * h),
        diff: out.toDataURL("image/png").split(",")[1],
      };
    },
    [a.toString("base64"), b.toString("base64")],
  );
}

(async () => {
  const [refBase, cloneBase, outDir] = process.argv.slice(2);
  fs.mkdirSync(outDir, { recursive: true });
  const browser = await chromium.launch();
  const scratch = await browser.newPage();
  let worst = 0;
  let differing = 0;
  for (const [label, viewport] of VIEWPORTS) {
    const ref = await capture(browser, refBase, viewport);
    const clone = await capture(browser, cloneBase, viewport);
    for (const [name] of PAGES) {
      const result = await compare(scratch, ref[name], clone[name]);
      const base = path.join(outDir, `${label}-${name}`);
      fs.writeFileSync(base + "-linkding.png", ref[name]);
      fs.writeFileSync(base + "-clone.png", clone[name]);
      fs.writeFileSync(base + "-diff.png", Buffer.from(result.diff, "base64"));
      worst = Math.max(worst, result.share);
      if (result.differing > 0 || result.sizes[0] !== result.sizes[1]) differing++;
      const size = result.sizes[0] === result.sizes[1] ? result.sizes[0] : result.sizes.join(" vs ");
      console.log(
        `${result.differing === 0 ? "same" : "diff"}  ${label.padEnd(7)} ${name.padEnd(16)} ` +
          `${(result.share * 100).toFixed(3).padStart(7)}% of pixels  ${size}`,
      );
    }
  }
  await browser.close();
  const total = PAGES.length * VIEWPORTS.length;
  console.log(
    `\n${total - differing} of ${total} screenshots match pixel for pixel ` +
      `(largest difference: ${(worst * 100).toFixed(3)}% of a page)`,
  );
  process.exit(differing ? 1 : 0);
})();
