import {
  performanceProfile,
  playbackLabels,
  rankRecommendations,
  resumePosition,
  selectSpatialTarget,
  selectVisibleCatalog,
} from "./core.mjs";

const STORAGE = {
  catalog: "openstream.tv.catalog",
  history: "openstream.tv.history",
  sources: "openstream.tv.sources",
};

const readJSON = (key, fallback) => {
  try {
    if (typeof localStorage === "undefined") return fallback;
    return JSON.parse(localStorage.getItem(key) || JSON.stringify(fallback));
  } catch {
    return fallback;
  }
};

const writeJSON = (key, value) => {
  try {
    if (typeof localStorage === "undefined") return;
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // A full or disabled store must never prevent playback.
  }
};

export const MAX_HISTORY_ITEMS = 50;

export function trimHistory(historyMap, maxItems = MAX_HISTORY_ITEMS) {
  if (!historyMap || typeof historyMap !== "object") return {};
  const keys = Object.keys(historyMap);
  if (keys.length <= maxItems) return historyMap;
  const entries = keys.map((key) => ({
    key,
    lastPlayed: Number(historyMap[key]?.lastPlayed) || 0,
  }));
  entries.sort((a, b) => a.lastPlayed - b.lastPlayed);
  const excess = entries.length - maxItems;
  for (let i = 0; i < excess; i++) {
    delete historyMap[entries[i].key];
  }
  return historyMap;
}

const history = trimHistory(readJSON(STORAGE.history, {}));
let catalog = normalizeCatalog(readJSON(STORAGE.catalog, []));
let sources = normalizeSources(readJSON(STORAGE.sources, []));
let section = catalog.length ? "discover" : "sources";
let active = null;
let lastSave = 0;

const cards = typeof document !== "undefined" ? document.querySelector("#continue-cards") : null;
const serverCards = typeof document !== "undefined" ? document.querySelector("#server-cards") : null;
const continueRail = typeof document !== "undefined" ? document.querySelector("#continue-rail") : null;
const serverRail = typeof document !== "undefined" ? document.querySelector("#server-rail") : null;
const video = typeof document !== "undefined" ? document.querySelector("#player") : null;
const playerShell = typeof document !== "undefined" ? document.querySelector("#player-shell") : null;
const formatIndicator = typeof document !== "undefined" ? document.querySelector("#format-indicator") : null;
const detailsSurface = typeof document !== "undefined" ? document.querySelector("#details-surface") : null;
const heroArt = typeof document !== "undefined" ? document.querySelector("#hero-art") : null;

if (typeof document !== "undefined") {
  document.documentElement.dataset.performance = performanceProfile({
    deviceMemory: typeof navigator !== "undefined" ? navigator.deviceMemory : undefined,
    hardwareConcurrency: typeof navigator !== "undefined" ? navigator.hardwareConcurrency : undefined,
    saveData: typeof navigator !== "undefined" ? navigator.connection?.saveData : undefined,
  });
}

function normalizeCatalog(items) {
  if (!Array.isArray(items)) return [];
  return items.map((item, index) => {
    if (!item || typeof item !== "object") return null;
    const mediaType = String(item.mediaType || item.type || item.kind || "video").toLowerCase();
    if (/book|audiobook|podcast|document/.test(mediaType)) return null;
    const title = cleanText(item.title || item.name);
    if (!title) return null;
    return {
      id: cleanText(item.id) || `configured-${index}`,
      title,
      year: cleanText(item.year),
      duration: cleanText(item.duration),
      quality: cleanText(item.quality),
      summary: cleanText(item.summary || item.description),
      sourceName: cleanText(item.sourceName || item.source),
      kind: mediaType === "channel" ? "live" : mediaType,
      uri: safeUri(item.uri || item.url),
      art: safeUri(item.art || item.backdrop || item.poster),
      dynamicRange: cleanText(item.dynamicRange),
      audio: cleanText(item.audio),
      popularity: Number(item.popularity) || 0,
      width: Number(item.width) || 0,
      height: Number(item.height) || 0,
    };
  }).filter(Boolean);
}

function normalizeSources(items) {
  if (!Array.isArray(items)) return [];
  return items.map((source) => ({
    name: cleanText(source?.name) || "Configured source",
    detail: cleanText(source?.detail) || "Managed by your paired OpenStream host",
    state: cleanText(source?.state) || "Connected",
  }));
}

function cleanText(value) {
  return String(value ?? "").trim().slice(0, 600);
}

function safeUri(value) {
  if (!value) return "";
  try {
    const parsed = new URL(String(value), location.href);
    return ["http:", "https:", "blob:"].includes(parsed.protocol) ? parsed.href : "";
  } catch {
    return "";
  }
}

function catalogForSection() {
  const available = selectVisibleCatalog(navigator.onLine, catalog, []);
  const filtered = section === "live"
    ? available.filter((item) => item.kind === "live")
    : section === "library"
      ? available.filter((item) => item.kind !== "live")
      : available;
  return rankRecommendations(filtered, history);
}

function progressFor(item) {
  const saved = history[item.id];
  if (!saved || !saved.duration) return 0;
  return Math.min(Math.max(saved.position / saved.duration, 0), 1);
}

function render() {
  const visible = catalogForSection();
  if (!active || !visible.some((item) => item.id === active.id)) active = visible[0] ?? null;

  const continueItems = visible.filter((item) => {
    const progress = progressFor(item);
    return progress > 0.03 && progress < 0.95;
  }).slice(0, 6);
  const continuedIds = new Set(continueItems.map((item) => item.id));
  const sourceItems = visible.filter((item) => !continuedIds.has(item.id)).slice(0, 6);

  cards.replaceChildren(...continueItems.map(card));
  serverCards.replaceChildren(...sourceItems.map(card));
  continueRail.classList.toggle("hidden", !continueItems.length);
  serverRail.classList.toggle("hidden", !sourceItems.length);
  updateHero(active);
  renderSources();
}

function card(item) {
  const button = document.createElement("button");
  button.className = "media-card focusable";
  button.type = "button";
  button.dataset.mediaId = item.id;
  button.setAttribute("aria-label", [item.title, item.quality, item.sourceName].filter(Boolean).join(", "));

  if (item.art) {
    const image = document.createElement("img");
    image.className = "card-art";
    image.src = item.art;
    image.alt = "";
    image.loading = "eager";
    image.addEventListener("error", () => image.remove(), { once: true });
    button.append(image);
  }

  const shade = document.createElement("span");
  shade.className = "card-shade";
  const copy = document.createElement("span");
  copy.className = "card-copy";
  const title = document.createElement("strong");
  title.className = "card-title";
  title.textContent = item.title;
  const detail = document.createElement("small");
  detail.className = "card-detail";
  detail.textContent = item.quality || item.duration;
  copy.append(title, detail);
  button.append(shade, copy);

  const progress = progressFor(item);
  if (progress > 0 && progress < 0.95) {
    const track = document.createElement("span");
    track.className = "progress-track";
    const fill = document.createElement("span");
    fill.className = "progress-fill";
    fill.style.width = `${Math.round(progress * 100)}%`;
    track.append(fill);
    button.append(track);
  }

  const footer = document.createElement("span");
  footer.className = "card-footer";
  const source = document.createElement("span");
  source.className = "card-source";
  source.textContent = item.sourceName || "OpenStream";
  const separator = document.createElement("span");
  separator.className = "card-separator";
  separator.textContent = "•";
  const kind = document.createElement("span");
  kind.textContent = item.kind === "live" ? "Live" : item.duration || "Video";
  footer.append(source, separator, kind);
  button.append(footer);
  button.addEventListener("click", () => select(item));
  return button;
}

function select(item) {
  active = item;
  updateHero(item);
  document.querySelector("#play").focus();
}

function updateHero(item) {
  const playable = Boolean(item?.uri);
  document.querySelector("#hero-title").textContent = item?.title ?? "Nothing to show yet";
  document.querySelector("#hero-meta").textContent = item
    ? [item.year, item.duration, item.quality].filter(Boolean).join(" · ")
    : "Add a video source to begin";
  document.querySelector("#hero-summary").textContent = item?.summary
    ?? "Pair OpenStream with your host, then manage libraries, add-ons, YouTube channels, and Live TV in Sources.";
  document.querySelector("#play").disabled = !playable;
  document.querySelector("#details").disabled = !item;
  document.querySelector(".hero").classList.toggle("no-art", !item?.art);

  if (item?.art) {
    heroArt.src = item.art;
    heroArt.classList.remove("hidden");
  } else {
    heroArt.removeAttribute("src");
    heroArt.classList.add("hidden");
  }
}

function renderSources() {
  const list = document.querySelector("#source-list");
  list.replaceChildren(...sources.map((source) => {
    const node = document.createElement("article");
    node.className = "source-card";
    const name = document.createElement("strong");
    name.textContent = source.name;
    const detail = document.createElement("span");
    detail.textContent = source.detail;
    const state = document.createElement("span");
    state.className = "source-state";
    state.textContent = source.state;
    node.append(name, detail, state);
    return node;
  }));

  if (!sources.length) {
    const empty = document.createElement("article");
    empty.className = "source-empty";
    const title = document.createElement("strong");
    title.textContent = "No sources connected";
    const copy = document.createElement("p");
    copy.textContent = "Connect this build to an OpenStream host through the TV integration. Only sources you configure will appear here.";
    empty.append(title, copy);
    list.replaceChildren(empty);
  }
}

function play(item) {
  if (!item?.uri) return;
  video.src = item.uri;
  document.querySelector("#player-title").textContent = item.title;
  document.querySelector("#player-source").textContent = item.sourceName || "Configured source";
  playerShell.classList.remove("hidden");
  playerShell.setAttribute("aria-hidden", "false");
  const saved = history[item.id];
  video.addEventListener("loadedmetadata", () => {
    video.currentTime = resumePosition(saved);
    video.play().catch(() => showToast("Press Play to start this video."));
  }, { once: true });

  const native4K = item.height >= 2160 || /4k|2160|uhd/i.test(item.quality);
  const labels = [...(native4K ? ["4K UHD"] : []), ...playbackLabels(item)];
  if (labels.length) {
    formatIndicator.textContent = labels.join("  •  ");
    formatIndicator.classList.remove("hidden");
    setTimeout(() => formatIndicator.classList.add("hidden"), 3500);
  }
  document.querySelector("#close-player").focus();
}

function closePlayer() {
  video.pause();
  saveProgress(true);
  playerShell.classList.add("hidden");
  playerShell.setAttribute("aria-hidden", "true");
  video.removeAttribute("src");
  video.load();
  document.querySelector("#play").focus();
}

function saveProgress(force = false) {
  if (!active || !video.duration || (!force && Date.now() - lastSave < 5000)) return;
  lastSave = Date.now();
  history[active.id] = {
    position: video.currentTime,
    duration: video.duration,
    lastPlayed: Date.now(),
    completed: video.currentTime >= video.duration * 0.95,
  };
  trimHistory(history);
  writeJSON(STORAGE.history, history);
}

function showDetails() {
  if (!active) return;
  document.querySelector("#details-title").textContent = active.title;
  document.querySelector("#details-meta").textContent = [active.year, active.duration, active.quality].filter(Boolean).join(" · ");
  document.querySelector("#details-copy").textContent = active.summary || "No description supplied by this source.";
  document.querySelector("#details-route").textContent = active.sourceName || "Configured source";
  detailsSurface.classList.remove("hidden");
  detailsSurface.setAttribute("aria-hidden", "false");
  document.querySelector("#close-details").focus();
}

function closeDetails() {
  detailsSurface.classList.add("hidden");
  detailsSurface.setAttribute("aria-hidden", "true");
  document.querySelector("#details").focus();
}

function showSection(nextSection, focusNav = false) {
  section = nextSection;
  const showingSources = section === "sources";
  document.querySelector("#app").dataset.section = section;
  document.querySelector("#media-view").classList.toggle("hidden", showingSources);
  document.querySelector("#sources-view").classList.toggle("hidden", !showingSources);
  document.querySelectorAll(".nav-item").forEach((item) => {
    const selected = item.dataset.section === section;
    item.classList.toggle("selected", selected);
    if (selected) item.setAttribute("aria-current", "page");
    else item.removeAttribute("aria-current");
  });
  render();
  if (focusNav) document.querySelector(`[data-section="${section}"]`)?.focus();
}

function updateNetwork() {
  const connected = navigator.onLine;
  document.querySelector("#connection-label").textContent = connected ? "Online" : "Offline";
  document.querySelector("#connection-status").classList.toggle("offline", !connected);
  render();
}

function showToast(message) {
  const toast = document.querySelector("#toast");
  toast.textContent = message;
  toast.classList.remove("hidden");
  setTimeout(() => toast.classList.add("hidden"), 3500);
}

function handleDirectionalNavigation(event) {
  const directions = {
    ArrowLeft: "left",
    ArrowRight: "right",
    ArrowUp: "up",
    ArrowDown: "down",
  };
  const direction = directions[event.key];
  if (!direction) return false;
  const elements = [...document.querySelectorAll(".focusable:not(:disabled)")]
    .filter((element) => element.offsetParent !== null);
  const rectangles = elements.map((element) => {
    const bounds = element.getBoundingClientRect();
    return { left: bounds.left, top: bounds.top, width: bounds.width, height: bounds.height, element };
  });
  const currentElement = document.activeElement;
  const current = rectangles.find((rectangle) => rectangle.element === currentElement);
  const target = selectSpatialTarget(current, rectangles, direction);
  if (!target?.element) return false;
  target.element.focus();
  return true;
}

function handleBack() {
  if (!detailsSurface.classList.contains("hidden")) {
    closeDetails();
    return true;
  }
  if (!playerShell.classList.contains("hidden")) {
    closePlayer();
    return true;
  }
  if (section !== "discover" && catalog.length) {
    showSection("discover", true);
    return true;
  }
  return false;
}

globalThis.OpenStreamTV = {
  configure(next = {}) {
    if (Array.isArray(next.catalog)) {
      catalog = normalizeCatalog(next.catalog);
      const cachedMetadata = catalog.map(({ uri: _uri, ...item }) => item);
      writeJSON(STORAGE.catalog, cachedMetadata);
    }
    if (Array.isArray(next.sources)) {
      sources = normalizeSources(next.sources);
      writeJSON(STORAGE.sources, sources);
    }
    showSection(catalog.length ? "discover" : "sources");
    (catalog.length ? document.querySelector("#play") : document.querySelector('.nav-item[data-section="sources"]'))?.focus();
  },
  clear() {
    catalog = [];
    sources = [];
    for (const key of Object.keys(history)) delete history[key];
    writeJSON(STORAGE.catalog, []);
    writeJSON(STORAGE.sources, []);
    writeJSON(STORAGE.history, {});
    showSection("sources", true);
  },
  getState() {
    return {
      catalogSize: catalog.length,
      historySize: Object.keys(history).length,
      performance: typeof document !== "undefined" ? document.documentElement.dataset.performance : "standard",
      section,
    };
  },
};

if (typeof document !== "undefined") {
  document.querySelectorAll(".nav-item").forEach((button) => button.addEventListener("click", () => {
    showSection(button.dataset.section);
  }));
  document.querySelector("#play")?.addEventListener("click", () => play(active));
  document.querySelector("#details")?.addEventListener("click", showDetails);
  document.querySelector("#close-details")?.addEventListener("click", closeDetails);
  document.querySelector("#close-player")?.addEventListener("click", closePlayer);
  video?.addEventListener("timeupdate", () => saveProgress(false));
  video?.addEventListener("ended", closePlayer);
  video?.addEventListener("error", () => showToast("This TV could not play the selected stream."));
  if (typeof addEventListener !== "undefined") {
    addEventListener("online", updateNetwork);
    addEventListener("offline", updateNetwork);
    addEventListener("keydown", (event) => {
      const code = event.keyCode;
      if (handleDirectionalNavigation(event)) {
        event.preventDefault();
        return;
      }
      if (event.key === "Backspace" || event.key === "Escape" || code === 461) {
        if (handleBack()) event.preventDefault();
        return;
      }
      if (!playerShell?.classList.contains("hidden") && video) {
        if (event.key === "MediaPlayPause") video.paused ? video.play() : video.pause();
        else if (event.key === "MediaPlay" || code === 415) video.play();
        else if (event.key === "MediaPause" || code === 19) video.pause();
        else if (event.key === "MediaStop" || code === 413) closePlayer();
      }
    });
  }

  updateClock();
  setInterval(updateClock, 1000);
  updateNetwork();
  showSection(section);
  setTimeout(() => {
    (active ? document.querySelector("#play") : document.querySelector('.nav-item[data-section="sources"]'))?.focus();
  }, 0);
}
