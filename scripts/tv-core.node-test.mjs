import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import {
  performanceProfile,
  playbackLabels,
  rankRecommendations,
  resumePosition,
  selectSpatialTarget,
  selectVisibleCatalog,
} from "../native/smart-tv/shared/core.mjs";
import { MAX_HISTORY_ITEMS, trimHistory } from "../native/smart-tv/shared/app.mjs";

test("TV playback labels only report detected premium formats", () => {
  assert.deepEqual(playbackLabels({ dynamicRange: "Dolby Vision", audio: "EAC3 JOC Atmos" }), ["DOLBY VISION", "DOLBY ATMOS"]);
  assert.deepEqual(playbackLabels({ dynamicRange: "SDR", audio: "AAC" }), []);
});

test("TV catalog automatically reduces to offline content", () => {
  const online = [{ id: "remote" }];
  const local = [{ id: "local", offlineAvailable: true }, { id: "partial", offlineAvailable: false }];
  assert.deepEqual(selectVisibleCatalog(false, online, local).map((item) => item.id), ["local"]);
});

test("TV recommendations prioritize resumable content and resume thresholds", () => {
  const ranked = rankRecommendations(
    [{ id: "new", popularity: 30 }, { id: "resume", popularity: 10 }],
    { resume: { position: 240, duration: 600 } },
  );
  assert.equal(ranked[0].id, "resume");
  assert.equal(resumePosition({ position: 120, duration: 600 }), 120);
  assert.equal(resumePosition({ position: 590, duration: 600 }), 0);
});

test("TV performance profile stays conservative when device hints are absent", () => {
  assert.equal(performanceProfile({}), "standard");
  assert.equal(performanceProfile({ deviceMemory: 1, hardwareConcurrency: 2, saveData: false }), "reduced");
  assert.equal(performanceProfile({ deviceMemory: 4, hardwareConcurrency: 4, saveData: false }), "full");
  assert.equal(performanceProfile({ deviceMemory: 8, hardwareConcurrency: 8, saveData: true }), "reduced");
});

test("TV spatial navigation favors the nearest aligned target", () => {
  const current = { id: "play", left: 70, top: 350, width: 180, height: 64 };
  const targets = [
    { id: "details", left: 270, top: 350, width: 180, height: 64 },
    { id: "first-card", left: 70, top: 480, width: 280, height: 170 },
    { id: "second-card", left: 370, top: 480, width: 280, height: 170 },
  ];

  assert.equal(selectSpatialTarget(current, targets, "right")?.id, "details");
  assert.equal(selectSpatialTarget(current, targets, "down")?.id, "first-card");
});

test("Smart TV shared HTML defines strict Content Security Policy", async () => {
  const htmlPath = new URL("../native/smart-tv/shared/index.html", import.meta.url);
  const html = await readFile(htmlPath, "utf8");

  assert.match(html, /http-equiv=["']Content-Security-Policy["']/i);
  const cspMatch = html.match(/<meta[^>]*http-equiv=["']Content-Security-Policy["'][^>]*content="([^"]+)"/i)
    || html.match(/<meta[^>]*content="([^"]+)"[^>]*http-equiv=["']Content-Security-Policy["']/i);
  assert.ok(cspMatch, "CSP meta tag must contain a content attribute");
  const policy = cspMatch[1];

  assert.match(policy, /default-src\s+'self'/);
  assert.match(policy, /script-src\s+'self'/);
  assert.match(policy, /object-src\s+'none'/);
  assert.match(policy, /media-src/);
  assert.match(policy, /connect-src/);
});

test("Smart TV persistent history enforces LRU cap of 50 items", () => {
  assert.equal(MAX_HISTORY_ITEMS, 50);

  // Less than limit stays intact
  const smallHistory = {
    item1: { position: 10, duration: 100, lastPlayed: 1000 },
    item2: { position: 20, duration: 100, lastPlayed: 2000 },
  };
  trimHistory(smallHistory, 50);
  assert.equal(Object.keys(smallHistory).length, 2);

  // Over limit evicts oldest entries
  const oversizedHistory = {};
  for (let i = 1; i <= 65; i++) {
    oversizedHistory[`item-${i}`] = {
      position: i,
      duration: 1000,
      lastPlayed: 10_000 + i * 100, // item-1 is oldest, item-65 is newest
    };
  }
  assert.equal(Object.keys(oversizedHistory).length, 65);

  trimHistory(oversizedHistory, 50);
  const remainingKeys = Object.keys(oversizedHistory);
  assert.equal(remainingKeys.length, 50);

  // Oldest 15 items (item-1 to item-15) must be evicted
  for (let i = 1; i <= 15; i++) {
    assert.equal(`item-${i}` in oversizedHistory, false, `item-${i} should have been evicted`);
  }
  // Newest 50 items (item-16 to item-65) must remain
  for (let i = 16; i <= 65; i++) {
    assert.equal(`item-${i}` in oversizedHistory, true, `item-${i} should be retained`);
  }

  // Edge cases: empty or non-object history
  assert.deepEqual(trimHistory({}), {});
  assert.deepEqual(trimHistory(null), {});
});
