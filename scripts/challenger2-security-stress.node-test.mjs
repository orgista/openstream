import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { MAX_HISTORY_ITEMS, trimHistory } from "../native/smart-tv/shared/app.mjs";

test("Challenger 2: Smart TV CSP Strictness and Directive Enforcement", async () => {
  const htmlPath = new URL("../native/smart-tv/shared/index.html", import.meta.url);
  const html = await readFile(htmlPath, "utf8");

  const cspMatch = html.match(/<meta[^>]*http-equiv=["']Content-Security-Policy["'][^>]*content="([^"]+)"/i)
    || html.match(/<meta[^>]*content="([^"]+)"[^>]*http-equiv=["']Content-Security-Policy["']/i);
  assert.ok(cspMatch, "Content-Security-Policy meta tag must be present");
  const csp = cspMatch[1];

  // Parse directives
  const directives = Object.fromEntries(
    csp.split(";").map(d => d.trim()).filter(Boolean).map(d => {
      const [key, ...vals] = d.split(/\s+/);
      return [key.toLowerCase(), vals.join(" ")];
    })
  );

  // 1. default-src must be 'self'
  assert.equal(directives["default-src"], "'self'", "default-src must be 'self'");

  // 2. script-src must be 'self' and NOT include 'unsafe-eval' or 'unsafe-inline'
  assert.ok(directives["script-src"], "script-src directive must exist");
  assert.ok(directives["script-src"].includes("'self'"), "script-src must include 'self'");
  assert.ok(!directives["script-src"].includes("'unsafe-eval'"), "script-src must NOT allow 'unsafe-eval'");
  assert.ok(!directives["script-src"].includes("'unsafe-inline'"), "script-src must NOT allow 'unsafe-inline'");

  // 3. object-src must be 'none' (prevents Flash/Java/plugins)
  assert.equal(directives["object-src"], "'none'", "object-src must be 'none'");

  // 4. base-uri must be 'self' or 'none' (prevents base tag hijacking)
  assert.ok(directives["base-uri"] === "'self'" || directives["base-uri"] === "'none'", "base-uri must be restricted");

  // 5. media-src and connect-src must allow legitimate media endpoints while restricting others
  assert.ok(directives["media-src"].includes("http:") && directives["media-src"].includes("https:"));
  assert.ok(directives["connect-src"].includes("http:") && directives["connect-src"].includes("https:"));
});

test("Challenger 2: Smart TV History LRU Cap Under Rapid Overflow & Stress", () => {
  // Test 1: Empty history
  assert.deepEqual(trimHistory({}), {});
  assert.deepEqual(trimHistory(null), {});
  assert.deepEqual(trimHistory(undefined), {});

  // Test 2: Exactly 50 items (boundary condition)
  const exact50 = {};
  for (let i = 1; i <= 50; i++) {
    exact50[`item-${i}`] = { position: i, duration: 100, lastPlayed: 1000 + i };
  }
  trimHistory(exact50, 50);
  assert.equal(Object.keys(exact50).length, 50);

  // Test 3: 51 items (single item eviction boundary)
  const history51 = {};
  for (let i = 1; i <= 51; i++) {
    history51[`item-${i}`] = { position: i, duration: 100, lastPlayed: 1000 + i };
  }
  trimHistory(history51, 50);
  assert.equal(Object.keys(history51).length, 50);
  assert.equal("item-1" in history51, false, "item-1 (oldest) must be evicted");
  assert.equal("item-51" in history51, true, "item-51 (newest) must be retained");

  // Test 4: Rapid massive overflow with 2,000 items out of order
  const massiveHistory = {};
  const timestamps = [];
  for (let i = 0; i < 2000; i++) {
    // Generate pseudo-random timestamp
    const ts = (i * 37 + 101) % 100000;
    timestamps.push({ id: `item-${i}`, ts });
    massiveHistory[`item-${i}`] = { position: 10, duration: 100, lastPlayed: ts };
  }

  // Sort timestamps to know exactly which 50 should survive
  timestamps.sort((a, b) => a.ts - b.ts);
  const expectedEvicted = new Set(timestamps.slice(0, 1950).map(t => t.id));
  const expectedRetained = new Set(timestamps.slice(1950).map(t => t.id));

  trimHistory(massiveHistory, 50);
  assert.equal(Object.keys(massiveHistory).length, 50, "Must be capped at exactly 50 items");

  for (const id of expectedRetained) {
    assert.ok(id in massiveHistory, `Expected ${id} to be retained`);
  }
  for (const id of expectedEvicted) {
    assert.ok(!(id in massiveHistory), `Expected ${id} to be evicted`);
  }

  // Test 5: Corrupt timestamps / NaN / strings / zero / negative
  const corruptHistory = {
    nanItem: { position: 0, duration: 100, lastPlayed: NaN },
    nullItem: { position: 0, duration: 100, lastPlayed: null },
    undefItem: { position: 0, duration: 100, lastPlayed: undefined },
    negItem: { position: 0, duration: 100, lastPlayed: -500 },
    zeroItem: { position: 0, duration: 100, lastPlayed: 0 },
    stringItem: { position: 0, duration: 100, lastPlayed: "12345" },
    validItem1: { position: 0, duration: 100, lastPlayed: 50000 },
    validItem2: { position: 0, duration: 100, lastPlayed: 60000 },
  };
  // Trim to 3 items
  trimHistory(corruptHistory, 3);
  assert.equal(Object.keys(corruptHistory).length, 3);
  // Valid newest items should survive
  assert.ok("validItem1" in corruptHistory);
  assert.ok("validItem2" in corruptHistory);
  assert.ok("stringItem" in corruptHistory); // "12345" converted to 12345 > 0, NaN, -500
});
