#!/usr/bin/env node
// Compares what the pages do in a browser on a real linkding and on this
// clone: the same clicks and keys on both, with what each page then shows
// recorded and compared. Runs after tool/html_parity.py, on its data.
//
//   NODE_PATH=$(npm root -g) node tool/browser_parity.js REF_BASE CLONE_BASE
//
// Needs Playwright for Node (`npm i -g playwright`) and its Chromium. Signs
// in as admin with LD_PARITY_PASSWORD (the password html_parity.py's last
// steps set). Exit status 1 when anything differs.
const { chromium } = require("playwright");

const PASSWORD = process.env.LD_PARITY_PASSWORD || "Parity-pass-2026";

async function signIn(page, base) {
  await page.goto(base + "/login/");
  await page.fill("#id_username", "admin");
  await page.fill("#id_password", PASSWORD);
  await Promise.all([
    page.waitForURL(/\/bookmarks$/),
    page.click("input[type=submit]"),
  ]);
  await page.waitForSelector("ld-search-autocomplete input");
}

// Waits for the next POST to be answered. linkding's development server
// keeps a live-reload request open, so the network is never idle.
function posted(page) {
  return page
    .waitForResponse((r) => r.request().method() === "POST", { timeout: 5000 })
    .catch(() => null);
}

const text = (s) => s.replace(/<!--[^>]*-->/g, "").replace(/\s+/g, " ").trim();

// Each scenario returns what the page showed, as plain data.
const scenarios = {
  async searchBox(page) {
    const out = {};
    out.rendered = await page.$eval("ld-search-autocomplete", (e) =>
      e.innerHTML.replace(/<!--[^>]*-->/g, "").replace(/\s+/g, " ").trim(),
    );
    await page.click("input[type=search]");
    await page.keyboard.type("#py");
    await page.waitForTimeout(800);
    out.menu = await page.$$eval("ld-search-autocomplete .menu.open li", (l) =>
      l.map((e) => e.textContent.trim()),
    );
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("Enter");
    out.value = await page.inputValue("input[type=search]");
    await page.keyboard.press("Escape");
    return out;
  },

  async dropdownAndConfirm(page) {
    const out = {};
    await page.click("nav .dropdown-toggle >> nth=0");
    out.opened = await page.$$eval("ld-dropdown.active", (d) => d.length);
    await page.keyboard.press("Escape");
    out.closed = await page.$$eval("ld-dropdown.active", (d) => d.length);
    await page.click("ul.bookmark-list li button[data-confirm] >> nth=0");
    await page.waitForTimeout(300);
    out.confirm = await page.$eval("ld-confirm-dropdown", (e) => ({
      classes: e.className,
      text: e.textContent.replace(/\s+/g, " ").trim(),
      position: e.querySelector(".menu").getAttribute("style"),
      focused: document.activeElement.textContent.trim(),
    }));
    await page.keyboard.press("Escape");
    out.confirmAfterEscape = await page.$$eval("ld-confirm-dropdown", (d) => d.length);
    return out;
  },

  async bulkEditSelection(page) {
    const out = {};
    await page.click(".bulk-edit-active-toggle");
    out.page = await page.$eval("ld-bookmark-page", (e) => e.className);
    out.executeBefore = await page.$eval("button[name='bulk_execute']", (b) => b.disabled);
    await page.check(".bulk-edit-checkbox.all input");
    out.executeAfter = await page.$eval("button[name='bulk_execute']", (b) => b.disabled);
    out.selectAcross = await page.$eval("label.select-across", (e) =>
      e.className + " | " + e.textContent.replace(/\s+/g, " ").trim(),
    );
    await page.uncheck(".bulk-edit-checkbox:not(.all) input >> nth=0");
    out.allAfterUncheck = await page.$eval(".bulk-edit-checkbox.all input", (b) => b.checked);
    return out;
  },

  async detailsModal(page, base) {
    const out = {};
    await page.click("ul.bookmark-list li a.view-action >> nth=0");
    await page.waitForSelector("ld-details-modal");
    out.url = page.url().replace(base, "");
    out.body = await page.$eval("body", (b) => b.className);
    out.focused = await page.evaluate(() => document.activeElement.className);
    await page.keyboard.press("Escape");
    await page.waitForTimeout(800);
    out.modals = await page.$$eval("ld-details-modal", (d) => d.length);
    out.urlAfterClose = page.url().replace(base, "");
    out.focusAfterClose = await page.evaluate(() => document.activeElement.className);
    out.bodyAfterClose = await page.$eval("body", (b) => b.className);
    return out;
  },

  async bookmarkForm(page, base) {
    const out = {};
    await page.goto(base + "/bookmarks/new");
    out.tagInput = await page.$eval("ld-tag-autocomplete", (e) => {
      const i = e.querySelector("input");
      return [i.id, i.name, i.className, i.placeholder, i.getAttribute("aria-describedby")];
    });
    await page.click("#id_tag_string");
    await page.keyboard.type("py");
    await page.waitForTimeout(500);
    out.menu = await page.$$eval("ld-tag-autocomplete .menu.open li", (l) =>
      l.map((e) => e.textContent.trim()),
    );
    await page.keyboard.press("Enter");
    out.value = await page.inputValue("#id_tag_string");
    out.clearHidden = await page.$eval("ld-clear-button[data-for=id_title]", (e) => e.style.display);
    await page.fill("#id_title", "abc");
    out.clearShown = await page.$eval("ld-clear-button[data-for=id_title]", (e) => e.style.display);
    await page.click("ld-clear-button[data-for=id_title]");
    out.cleared = await page.inputValue("#id_title");
    return out;
  },

  async shortcuts(page, base) {
    const out = {};
    await page.goto(base + "/bookmarks");
    await page.waitForSelector("ld-search-autocomplete input");
    await page.click("main h1");
    await page.keyboard.press("ArrowDown");
    await page.keyboard.press("ArrowDown");
    out.arrows = await page.evaluate(() => document.activeElement.closest("li")?.dataset.bookmarkId);
    await page.click("main h1");
    await page.keyboard.press("e");
    out.notes = await page.$eval(".bookmark-list", (e) => e.classList.contains("show-notes"));
    await page.keyboard.press("s");
    out.search = await page.evaluate(() => document.activeElement.type);
    return out;
  },

  async filterDrawer(page, base) {
    const out = {};
    await page.setViewportSize({ width: 600, height: 900 });
    await page.goto(base + "/bookmarks");
    await page.click("ld-filter-drawer-trigger");
    await page.waitForTimeout(500);
    out.drawer = await page.$eval("ld-filter-drawer", (e) =>
      e.className + " | " + [...e.querySelectorAll(".modal-body h3")].map((h) => h.textContent.trim()).join(","),
    );
    await page.keyboard.press("Escape");
    await page.waitForTimeout(800);
    out.sidePanel = await page.$eval(".side-panel", (e) =>
      e.children.length + " " + [...e.querySelectorAll("h2")].map((h) => h.textContent.trim()).join(","),
    );
    out.focused = await page.evaluate(() => document.activeElement.localName);
    await page.setViewportSize({ width: 1280, height: 900 });
    return out;
  },

  // The scenarios from here on change data, the same way on both.
  async listActions(page, base) {
    const out = {};
    await page.goto(base + "/bookmarks");
    await page.waitForSelector("ld-search-autocomplete input");
    const ids = () =>
      page.$$eval("ul.bookmark-list > li", (l) => l.slice(0, 5).map((e) => e.dataset.bookmarkId));
    // A full page load would lose this.
    await page.evaluate(() => { window.__parityMarker = "kept"; });
    out.before = await ids();
    await page.click("ul.bookmark-list > li >> nth=0 >> button[name=remove]");
    await Promise.all([posted(page), page.click("ld-confirm-dropdown button.btn-error")]);
    await page.waitForTimeout(700);
    out.afterRemove = await ids();
    const unread = await page.$("ul.bookmark-list > li button[name=mark_as_read]");
    if (unread) {
      await unread.click();
      await Promise.all([posted(page), page.click("ld-confirm-dropdown button.btn-error")]);
      await page.waitForTimeout(700);
    }
    out.unreadLeft = await page.$$eval("ul.bookmark-list > li button[name=mark_as_read]", (b) => b.length);
    out.marker = await page.evaluate(() => window.__parityMarker);
    return out;
  },

  async bulkTag(page, base) {
    const out = {};
    await page.goto(base + "/bookmarks");
    await page.waitForSelector("ld-search-autocomplete input");
    await page.evaluate(() => { window.__parityMarker = "kept"; });
    await page.click(".bulk-edit-active-toggle");
    const boxes = await page.$$(".bulk-edit-checkbox:not(.all) input");
    await boxes[0].check();
    await boxes[1].check();
    await page.selectOption("select[name='bulk_action']", "bulk_tag");
    out.action = await page.$eval("ld-bookmark-page", (e) => e.dataset.bulkAction);
    await page.click("ld-tag-autocomplete input[name=bulk_tag_string]");
    await page.keyboard.type("bulk");
    await page.waitForTimeout(400);
    out.menu = await page.$$eval("ld-tag-autocomplete .menu.open li", (l) => l.map((e) => e.textContent.trim()));
    await page.keyboard.press("Escape");
    await page.keyboard.type("x");
    await page.click("button[name='bulk_execute']");
    await Promise.all([
      posted(page),
      page.click("ld-confirm-dropdown button.btn-error", { timeout: 2000 }).catch(() => {}),
    ]);
    await page.waitForTimeout(700);
    out.tags = await page.$$eval("ul.bookmark-list > li", (l) =>
      l.slice(0, 2).map((e) => [...e.querySelectorAll(".tags a")].map((a) => a.textContent.trim()).join(" ")),
    );
    out.checked = await page.$$eval(".bulk-edit-checkbox input:checked", (b) => b.length);
    out.marker = await page.evaluate(() => window.__parityMarker);
    return out;
  },
};

async function run(base) {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  const errors = [];
  const requests = [];
  page.on("pageerror", (e) => errors.push("pageerror: " + e.message));
  page.on("console", (m) => {
    if (m.type() === "error" || m.type() === "warning") errors.push(m.type() + ": " + m.text());
  });
  page.on("request", (r) => {
    if (r.method() === "POST" || r.headers()["turbo-frame"]) {
      requests.push([r.method(), r.url().replace(base, ""), r.headers()["accept"], r.headers()["turbo-frame"]].join(" "));
    }
  });
  await signIn(page, base);
  const results = {};
  for (const [name, scenario] of Object.entries(scenarios)) {
    try {
      results[name] = await scenario(page, base);
    } catch (e) {
      results[name] = { failed: e.message.split("\n")[0] };
    }
  }
  results.requests = requests;
  results.errors = errors;
  await browser.close();
  return results;
}

(async () => {
  const [refBase, cloneBase] = process.argv.slice(2);
  const ref = await run(refBase);
  const clone = await run(cloneBase);
  let failed = 0;
  for (const key of Object.keys({ ...ref, ...clone })) {
    const a = JSON.stringify(ref[key]);
    const b = JSON.stringify(clone[key]);
    if (a === b) {
      console.log(`ok  ${key}`);
    } else {
      failed++;
      console.log(`--- ${key}: differs\n    linkding: ${a}\n    clone:    ${b}`);
    }
  }
  const total = Object.keys({ ...ref, ...clone }).length;
  console.log(`\n${total - failed} of ${total} browser checks match`);
  process.exit(failed ? 1 : 0);
})();
