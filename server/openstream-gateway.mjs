import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import http from "node:http";
import { fileURLToPath } from "node:url";
import { createLogger } from "./logger.mjs";
import { createTmdbMetadataService } from "./metadata.mjs";
import { createNetflixTop10Service } from "./netflix-top10.mjs";
import { listNasDirectory, resolveWithinRoot, streamNasFile, validateNasRoot } from "./nas.mjs";
import {
  authorizeTarget,
  assertGatewayBindHost,
  assertAllowedOrigin,
  isPrivateAddress,
  normalizeTarget,
  parseCanonicalRequestTarget,
  safeRequestJson,
  safeStreamRequest,
} from "./security.mjs";
import { probeTranscoder, startTranscode } from "./transcoder.mjs";

const allowLanGateway = process.env.OPENSTREAM_GATEWAY_ALLOW_LAN === "1";
const host = assertGatewayBindHost(process.env.OPENSTREAM_GATEWAY_HOST ?? "127.0.0.1", {
  allowLan: allowLanGateway,
});
const port = Number(process.env.OPENSTREAM_GATEWAY_PORT ?? 8787);
const urlHost = host.includes(":") ? `[${host}]` : host;
const allowedOrigins = new Set(
  (process.env.OPENSTREAM_ALLOWED_ORIGINS ?? "http://127.0.0.1:5173,http://localhost:5173")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
);
const connectionVault = new Map();
const oauthLaunches = new Map();
const oauthStates = new Map();
const streamVault = new Map();
const mediaVault = new Map();
const xrHandoffVault = new Map();
const nasVault = new Map();
const transcodeVault = new Map();
const transcodeInputVault = new Map();
const MAX_ARR_OPTIONS_PER_KIND = 128;
const MAX_ARR_PROFILE_NAME_LENGTH = 256;
const MAX_ARR_ROOT_PATH_LENGTH = 2048;
let rpcId = 0;

class GatewayHttpError extends Error {
  constructor(statusCode, message) {
    super(message);
    this.statusCode = statusCode;
  }
}

function createGatewaySession(sessionToken) {
  if (typeof sessionToken !== "string" || sessionToken.length < 32 || sessionToken.length > 512 || !/^[A-Za-z0-9_-]+$/.test(sessionToken)) {
    throw new Error("OPENSTREAM_GATEWAY_TOKEN must be a high-entropy base64url token of at least 32 characters.");
  }
  const digest = createHash("sha256").update(sessionToken).digest();
  return { digest, ownerId: digest.toString("base64url") };
}

function authenticateSession(request, session) {
  const supplied = typeof request.headers["x-openstream-session"] === "string"
    ? request.headers["x-openstream-session"]
    : "";
  const suppliedDigest = createHash("sha256").update(supplied).digest();
  if (!timingSafeEqual(suppliedDigest, session.digest)) {
    throw new GatewayHttpError(401, "The OpenStream gateway session is invalid or expired.");
  }
  return session.ownerId;
}

function activeTranscodeCapability(request, requestUrl) {
  if (request.method !== "GET" || requestUrl.pathname !== "/api/transcode/media") return undefined;
  const transcodeId = requestUrl.searchParams.get("transcodeId");
  if (typeof transcodeId !== "string" || !/^[A-Za-z0-9_-]{32,128}$/.test(transcodeId)) return undefined;
  const record = transcodeVault.get(transcodeId);
  if (!record) return undefined;
  if (Date.now() - record.createdAt > 12 * 60 * 60_000) {
    transcodeVault.delete(transcodeId);
    return undefined;
  }
  return record;
}

const connectionNames = {
  "google-drive": "Google Drive",
  stremio: "Stremio",
  sonarr: "Sonarr",
  radarr: "Radarr",
  sabnzbd: "SABnzbd",
  nzbget: "NZBGet",
  "nas-folder": "NAS folder",
};

function securityHeaders(origin) {
  return {
    ...(allowedOrigins.has(origin) ? { "Access-Control-Allow-Origin": origin, Vary: "Origin" } : {}),
    "Access-Control-Allow-Headers": "Content-Type, X-OpenStream-Request",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Cache-Control": "no-store",
    "Cross-Origin-Opener-Policy": "same-origin-allow-popups",
    "Cross-Origin-Resource-Policy": "same-site",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
  };
}

function sendJson(response, status, payload, origin) {
  response.writeHead(status, { ...securityHeaders(origin), "Content-Type": "application/json; charset=utf-8" });
  response.end(JSON.stringify(payload));
}

async function readJson(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > 64 * 1024) throw new Error("Request body exceeded the gateway size limit.");
    chunks.push(chunk);
  }
  const text = Buffer.concat(chunks).toString("utf8");
  return text ? JSON.parse(text) : {};
}

function requireString(value, label, max = 2048) {
  if (typeof value !== "string" || value.trim() === "") throw new Error(`${label} is required.`);
  if (value.length > max) throw new Error(`${label} is too long.`);
  return value.trim();
}

function optionalString(value, max) {
  if (typeof value !== "string") return undefined;
  const result = value.trim();
  return result ? result.slice(0, max) : undefined;
}

function pruneVault(vault, maximumEntries) {
  while (vault.size > maximumEntries) vault.delete(vault.keys().next().value);
}

export function parseNasMappings(value = process.env.OPENSTREAM_NAS_MAPPINGS ?? "[]") {
  const raw = typeof value === "string" && value.trim() ? JSON.parse(value) : [];
  if (!Array.isArray(raw)) throw new Error("OPENSTREAM_NAS_MAPPINGS must be a JSON array.");
  return raw.map((entry) => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      throw new Error("Each NAS mapping must be an object.");
    }
    const host = requireString(entry.host, "NAS mapping host", 255).toLowerCase();
    const share = requireString(entry.share, "NAS mapping share", 255);
    const rootPath = requireString(entry.rootPath, "NAS mapping root path", 4096);
    if (host.includes("@") || share.includes("/") || share.includes("\\") || share.includes("@")) {
      throw new Error("NAS mapping host/share is invalid.");
    }
    return { host, share, rootPath };
  });
}

function decodeSmbPath(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function parseSmbRoute(value) {
  const text = requireString(value, "SMB media URI", 8192);
  const match = /^smb:\/\/([^/?#]+)\/([^/?#]+)(?:\/([^?#]*))?(?:[?#].*)?$/i.exec(text);
  if (!match) throw new Error("SMB media URI must look like smb://host/share/path.");
  const authority = match[1];
  if (authority.includes("@")) throw new Error("SMB media URI must not contain credentials.");
  const host = authority.replace(/:\d+$/, "").trim().toLowerCase();
  const share = decodeSmbPath(match[2]).trim();
  const relativePath = decodeSmbPath(match[3] ?? "").replace(/^\/+/, "");
  if (!host || !share || !relativePath || /[\u0000-\u001f]/.test(relativePath)) {
    throw new Error("SMB media URI is incomplete.");
  }
  return { host, share, relativePath };
}

export async function resolveMappedSmbPath(smbUri, mappings = parseNasMappings()) {
  const route = parseSmbRoute(smbUri);
  const mapping = mappings.find((candidate) =>
    candidate.host.toLowerCase() === route.host &&
    candidate.share.toLowerCase() === route.share.toLowerCase());
  if (!mapping) {
    throw new Error("No OpenStream gateway NAS mapping matches this SMB share.");
  }
  const root = await validateNasRoot(mapping.rootPath);
  return resolveWithinRoot(root, route.relativePath);
}

function hostHeaderAllowed(value, runtime) {
  if (runtime.allowedHosts.has(value)) return true;
  if (!runtime.allowLan) return false;
  if (typeof value !== "string" || !value) return false;
  const parsed = parseHostHeader(value);
  if (!parsed || parsed.port !== runtime.port) return false;
  return parsed.host === "localhost" || parsed.host === "localhost.localdomain" || isPrivateAddress(parsed.host);
}

function parseHostHeader(value) {
  const header = String(value).trim().toLowerCase();
  if (header.startsWith("[")) {
    const end = header.indexOf("]");
    if (end < 0) return undefined;
    const host = header.slice(1, end);
    const portText = header.slice(end + 1).replace(/^:/, "");
    const port = Number(portText);
    return Number.isInteger(port) ? { host, port } : undefined;
  }
  const separator = header.lastIndexOf(":");
  if (separator < 0) return undefined;
  const host = header.slice(0, separator);
  const port = Number(header.slice(separator + 1));
  return host && Number.isInteger(port) ? { host, port } : undefined;
}

async function issueStremioStream(record, value) {
  try {
    const candidate = normalizeTarget(value, {
      allowPrivateNetwork: record.allowPrivateNetwork === true,
    });
    const sameServiceOrigin = candidate.origin === record.targetPolicy.approvedOrigin;
    const authorization = await authorizeTarget(candidate.toString(), sameServiceOrigin
      ? connectionPolicy(record)
      : { allowPrivateNetwork: false });
    const streamId = randomBytes(24).toString("base64url");
    streamVault.set(streamId, {
      connectionId: record.id,
      ownerId: record.ownerId,
      target: authorization.url.toString(),
      targetPolicy: authorization.policy,
      createdAt: Date.now(),
    });
    pruneVault(streamVault, 500);
    return `/gateway/stremio/media?streamId=${encodeURIComponent(streamId)}`;
  } catch {
    return undefined;
  }
}

async function sanitizeStremioStream(record, value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const stream = {
    name: optionalString(value.name, 256),
    title: optionalString(value.title, 512),
    description: optionalString(value.description, 2048),
  };
  if (typeof value.url === "string") stream.url = await issueStremioStream(record, value.url);
  if (typeof value.externalUrl === "string") {
    try {
      const externalUrl = new URL(value.externalUrl);
      if (externalUrl.protocol === "https:" && !externalUrl.username && !externalUrl.password) stream.externalUrl = externalUrl.toString();
    } catch {
      // Ignore malformed external links from an untrusted add-on.
    }
  }
  if (typeof value.ytId === "string" && /^[A-Za-z0-9_-]{6,32}$/.test(value.ytId)) stream.ytId = value.ytId;
  if (typeof value.infoHash === "string" && /^(?:[A-Fa-f0-9]{40}|[A-Za-z2-7]{32})$/.test(value.infoHash)) {
    stream.infoHash = value.infoHash;
    if (Number.isInteger(value.fileIdx) && value.fileIdx >= 0 && value.fileIdx <= 1_000_000) stream.fileIdx = value.fileIdx;
  }
  return stream.url || stream.externalUrl || stream.ytId || stream.infoHash ? stream : undefined;
}

function validRange(request) {
  const range = request.headers.range;
  if (range && !/^bytes=\d*-\d*$/.test(range)) throw new Error("Media range request is invalid.");
  if (range === "bytes=-") throw new Error("Media range request is invalid.");
  return range;
}

function pipeStream(request, response, upstream, origin) {
  const headers = securityHeaders(origin);
  for (const name of ["accept-ranges", "content-length", "content-range", "content-type", "etag", "last-modified"]) {
    const value = upstream.headers[name];
    if (typeof value === "string") headers[name] = value;
  }
  response.writeHead(upstream.statusCode ?? 200, headers);
  upstream.pipe(response);
  request.on("close", () => upstream.destroy());
}

function connectionPolicy(draft) {
  return draft.targetPolicy ?? { allowPrivateNetwork: draft.allowPrivateNetwork === true };
}

function publicConnection(record) {
  return {
    id: record.id,
    kind: record.kind,
    name: record.name,
    detail: record.detail,
    state: record.state,
    lastChecked: record.lastChecked,
    capabilities: record.capabilities,
    managed: true,
  };
}

function endpoint(baseUrl, path) {
  const url = normalizeTarget(baseUrl, { allowPrivateNetwork: true });
  url.pathname = `${url.pathname.replace(/\/+$/, "")}${path}`;
  url.search = "";
  return url.toString();
}

function buildStremioManifestUrl(value) {
  const url = normalizeTarget(value, { allowPrivateNetwork: true });
  if (!url.pathname.endsWith("manifest.json")) url.pathname = `${url.pathname.replace(/\/+$/, "")}/manifest.json`;
  return url.toString();
}

async function testConnection(draft, ownerId) {
  const kind = requireString(draft.kind, "Connection type", 32);
  if (!Object.hasOwn(connectionNames, kind)) throw new Error("Unsupported connection type.");
  const id = randomUUID();
  const record = {
    id,
    ownerId,
    kind,
    name: connectionNames[kind],
    detail: "Configuration pending",
    state: "checking",
    lastChecked: "just now",
    capabilities: [],
    allowPrivateNetwork: draft.allowPrivateNetwork === true,
  };

  if (kind === "google-drive") {
    record.clientId = requireString(draft.credential, "Google OAuth client ID", 512);
    record.appOrigin = requireString(draft.appOrigin, "Application origin", 256);
    assertAllowedOrigin(record.appOrigin, allowedOrigins);
    record.state = "attention";
    record.detail = "Authorization required";
    record.capabilities = ["drive.file scope", "User-selected files", "Range requests"];
    connectionVault.set(id, record);
    const launchToken = randomBytes(32).toString("base64url");
    oauthLaunches.set(launchToken, { connectionId: id, ownerId, createdAt: Date.now() });
    pruneVault(oauthLaunches, 100);
    return {
      connection: publicConnection(record),
      authorizationUrl: `http://${urlHost}:${port}/api/oauth/google/start?launch=${encodeURIComponent(launchToken)}`,
    };
  }

  if (kind === "nas-folder") {
    record.rootPath = await validateNasRoot(requireString(draft.baseUrl, "NAS folder path", 4096));
    record.name = record.rootPath.split("/").filter(Boolean).pop() ?? "NAS folder";
    record.detail = record.rootPath;
    record.capabilities = ["Mounted share", "Range requests", "Local transcode"];
    record.state = "connected";
    connectionVault.set(id, record);
    return { connection: publicConnection(record) };
  }

  record.baseUrl = requireString(draft.baseUrl, "Server URL");
  const authorization = await authorizeTarget(record.baseUrl, {
    allowPrivateNetwork: draft.allowPrivateNetwork === true,
  });
  record.baseUrl = authorization.url.toString();
  record.targetPolicy = authorization.policy;
  const policy = connectionPolicy(record);

  if (kind === "stremio") {
    const manifestUrl = buildStremioManifestUrl(record.baseUrl);
    const manifest = await safeRequestJson(manifestUrl, {}, policy);
    requireString(manifest?.id, "Stremio manifest ID", 256);
    record.name = requireString(manifest?.name, "Stremio manifest name", 256);
    record.detail = `${record.name} - ${requireString(manifest?.version, "Stremio manifest version", 64)}`;
    record.capabilities = Array.isArray(manifest.resources)
      ? manifest.resources.map((resource) => typeof resource === "string" ? resource : resource?.name).filter(Boolean).slice(0, 20)
      : [];
    record.transportUrl = manifestUrl.replace(/\/manifest\.json$/, "");
  } else if (kind === "sonarr" || kind === "radarr") {
    record.apiKey = requireString(draft.credential, "ARR API key", 512);
    const status = await safeRequestJson(endpoint(record.baseUrl, "/api/v3/system/status"), {
      headers: { "X-Api-Key": record.apiKey },
    }, policy);
    record.detail = `${status.instanceName || status.appName || record.name} - ${requireString(status.version, "ARR version", 64)}`;
    record.capabilities = kind === "radarr"
      ? ["Movie lookup", "Quality profiles", "Search handoff"]
      : ["Series lookup", "Quality profiles", "Episode search"];
  } else if (kind === "sabnzbd") {
    record.apiKey = requireString(draft.credential, "SABnzbd API key", 512);
    const url = new URL(endpoint(record.baseUrl, "/api"));
    url.searchParams.set("mode", "version");
    url.searchParams.set("output", "json");
    url.searchParams.set("apikey", record.apiKey);
    const status = await safeRequestJson(url.toString(), {}, policy);
    record.detail = `SABnzbd - ${requireString(status.version, "SABnzbd version", 64)}`;
    record.capabilities = ["NZB handoff", "Queue", "History"];
  } else if (kind === "nzbget") {
    record.username = requireString(draft.username, "NZBGet username", 256);
    record.password = requireString(draft.credential, "NZBGet password", 1024);
    const token = Buffer.from(`${record.username}:${record.password}`).toString("base64");
    const status = await safeRequestJson(endpoint(record.baseUrl, "/jsonrpc"), {
      method: "POST",
      headers: { Authorization: `Basic ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method: "version", params: [] }),
    }, policy);
    if (status.error) throw new Error(status.error.message || "NZBGet rejected the request.");
    record.detail = `NZBGet - ${requireString(status.result, "NZBGet version", 64)}`;
    record.capabilities = ["NZB handoff", "Queue", "History"];
  }

  record.state = "connected";
  connectionVault.set(id, record);
  return { connection: publicConnection(record) };
}

function getConnection(id, expectedKinds, ownerId) {
  const record = connectionVault.get(requireString(id, "Connection ID", 128));
  if (!record || record.ownerId !== ownerId || !expectedKinds.includes(record.kind)) {
    throw new Error("The secure connection is not available in this gateway session.");
  }
  return record;
}

async function arrOptions(record) {
  const policy = connectionPolicy(record);
  const headers = { "X-Api-Key": record.apiKey };
  const [profiles, roots] = await Promise.all([
    safeRequestJson(endpoint(record.baseUrl, "/api/v3/qualityprofile"), { headers }, policy),
    safeRequestJson(endpoint(record.baseUrl, "/api/v3/rootfolder"), { headers }, policy),
  ]);

  if (!Array.isArray(profiles) || !Array.isArray(roots)) throw new Error("ARR option responses must be arrays.");
  if (profiles.length > MAX_ARR_OPTIONS_PER_KIND || roots.length > MAX_ARR_OPTIONS_PER_KIND) {
    throw new Error(`ARR option responses may contain at most ${MAX_ARR_OPTIONS_PER_KIND} profiles and root folders.`);
  }

  return {
    profiles: profiles.map((item) => {
      if (!item || typeof item !== "object" || Array.isArray(item) || !Number.isInteger(item.id) || item.id < 0) {
        throw new Error("ARR quality profile metadata is invalid.");
      }
      return {
        id: item.id,
        name: requireString(item.name, "ARR quality profile name", MAX_ARR_PROFILE_NAME_LENGTH),
      };
    }),
    roots: roots.map((item) => {
      if (!item || typeof item !== "object" || Array.isArray(item)) {
        throw new Error("ARR root folder metadata is invalid.");
      }
      const root = {
        path: requireString(item.path, "ARR root folder path", MAX_ARR_ROOT_PATH_LENGTH),
      };
      if (item.id != null) {
        if (!Number.isInteger(item.id) || item.id < 0) throw new Error("ARR root folder ID is invalid.");
        root.id = item.id;
      }
      if (item.freeSpace != null) {
        if (!Number.isFinite(item.freeSpace) || item.freeSpace < 0) throw new Error("ARR root folder free space is invalid.");
        root.freeSpace = item.freeSpace;
      }
      return root;
    }),
  };
}

async function sendArrRequest(record, request) {
  const headers = { "X-Api-Key": record.apiKey, "Content-Type": "application/json" };
  const common = {
    title: requireString(request.title, "Title", 512),
    year: Number(request.year),
    qualityProfileId: Number(request.qualityProfileId),
    rootFolderPath: requireString(request.rootFolderPath, "Root folder", 2048),
    monitored: request.monitored !== false,
  };
  if (!Number.isInteger(common.year) || !Number.isInteger(common.qualityProfileId)) throw new Error("ARR request metadata is invalid.");
  const body = record.kind === "radarr"
    ? { ...common, tmdbId: Number(request.tmdbId) || undefined, imdbId: request.imdbId || undefined, minimumAvailability: "released", addOptions: { searchForMovie: true } }
    : { ...common, tvdbId: Number(request.tvdbId) || undefined, imdbId: request.imdbId || undefined, seasonFolder: true, addOptions: { searchForMissingEpisodes: true, monitor: "all" } };
  const path = record.kind === "radarr" ? "/api/v3/movie" : "/api/v3/series";
  return safeRequestJson(endpoint(record.baseUrl, path), { method: "POST", headers, body: JSON.stringify(body) }, connectionPolicy(record));
}

async function handoffNzb(record, payload) {
  const nzbUrl = normalizeTarget(requireString(payload.nzbUrl, "NZB URL"));
  if (nzbUrl.protocol !== "https:") throw new Error("NZB handoff URLs must use HTTPS.");
  const category = typeof payload.category === "string" ? payload.category.slice(0, 128) : "";
  if (record.kind === "sabnzbd") {
    const url = new URL(endpoint(record.baseUrl, "/api"));
    url.searchParams.set("mode", "addurl");
    url.searchParams.set("output", "json");
    url.searchParams.set("apikey", record.apiKey);
    url.searchParams.set("name", nzbUrl.toString());
    if (category) url.searchParams.set("cat", category);
    return safeRequestJson(url.toString(), {}, connectionPolicy(record));
  }
  const token = Buffer.from(`${record.username}:${record.password}`).toString("base64");
  const result = await safeRequestJson(endpoint(record.baseUrl, "/jsonrpc"), {
    method: "POST",
    headers: { Authorization: `Basic ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method: "append", params: ["", nzbUrl.toString(), category, 0, false, false, "", 0, "SCORE", true, []] }),
  }, connectionPolicy(record));
  if (result.error) throw new Error(result.error.message || "NZBGet rejected the handoff.");
  return result;
}

function base64Url(bytes) {
  return Buffer.from(bytes).toString("base64url");
}

async function beginGoogleOAuth(requestUrl, response) {
  const launch = oauthLaunches.get(requestUrl.searchParams.get("launch"));
  if (!launch || Date.now() - launch.createdAt > 10 * 60_000) throw new Error("Google authorization request expired.");
  oauthLaunches.delete(requestUrl.searchParams.get("launch"));
  const record = getConnection(launch.connectionId, ["google-drive"], launch.ownerId);
  const state = base64Url(randomBytes(24));
  const verifier = base64Url(randomBytes(48));
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  oauthStates.set(state, { connectionId: record.id, ownerId: record.ownerId, verifier, createdAt: Date.now() });
  pruneVault(oauthStates, 100);
  const redirectUri = `http://${urlHost}:${port}/api/oauth/google/callback`;
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", record.clientId);
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", "https://www.googleapis.com/auth/drive.file");
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");
  url.searchParams.set("state", state);
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  response.writeHead(302, { Location: url.toString(), "Cache-Control": "no-store" });
  response.end();
}

async function finishGoogleOAuth(requestUrl, response) {
  const stateValue = requestUrl.searchParams.get("state");
  const state = oauthStates.get(stateValue);
  if (!state || Date.now() - state.createdAt > 10 * 60_000) throw new Error("Google OAuth state is invalid or expired.");
  oauthStates.delete(stateValue);
  if (requestUrl.searchParams.get("error")) throw new Error("Google authorization was cancelled.");
  const code = requireString(requestUrl.searchParams.get("code"), "Google authorization code", 4096);
  const record = getConnection(state.connectionId, ["google-drive"], state.ownerId);
  const redirectUri = `http://${urlHost}:${port}/api/oauth/google/callback`;
  const form = new URLSearchParams({
    client_id: record.clientId,
    code,
    code_verifier: state.verifier,
    grant_type: "authorization_code",
    redirect_uri: redirectUri,
  });
  const tokens = await safeRequestJson("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  record.accessToken = requireString(tokens.access_token, "Google access token", 8192);
  record.refreshToken = typeof tokens.refresh_token === "string" ? tokens.refresh_token : record.refreshToken;
  record.expiresAt = Date.now() + Number(tokens.expires_in ?? 3600) * 1000;
  record.state = "connected";
  record.detail = "Authorized for user-selected files";
  const nonce = randomBytes(18).toString("base64url");
  const payload = JSON.stringify({ type: "openstream-google-connected", connection: publicConnection(record) });
  const origin = JSON.stringify(record.appOrigin);
  const html = `<!doctype html><meta charset="utf-8"><title>OpenStream Google Drive</title><p>Google Drive is connected. This window can close.</p><script nonce="${nonce}">window.opener?.postMessage(${payload},${origin});window.close();</script>`;
  response.writeHead(200, {
    ...securityHeaders(record.appOrigin),
    "Content-Security-Policy": `default-src 'none'; style-src 'none'; script-src 'nonce-${nonce}'; base-uri 'none'; form-action 'none'`,
    "Content-Type": "text/html; charset=utf-8",
  });
  response.end(html);
}

async function refreshDriveAccessToken(record) {
  const form = new URLSearchParams({ client_id: record.clientId, refresh_token: record.refreshToken, grant_type: "refresh_token" });
  const tokens = await safeRequestJson("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  record.accessToken = requireString(tokens.access_token, "Google access token", 8192);
  record.expiresAt = Date.now() + Number(tokens.expires_in ?? 3600) * 1000;
  return record.accessToken;
}

async function driveAccessToken(record) {
  if (record.accessToken && record.expiresAt > Date.now() + 60_000) return record.accessToken;
  if (!record.refreshToken) throw new Error("Google Drive authorization has expired.");
  record.refreshInFlight ??= refreshDriveAccessToken(record).finally(() => {
    record.refreshInFlight = undefined;
  });
  return record.refreshInFlight;
}

function requireGoogleFileId(value) {
  const fileId = requireString(value, "Google Drive file ID", 256);
  if (!/^[A-Za-z0-9_-]+$/.test(fileId)) throw new Error("Google Drive file ID is invalid.");
  return fileId;
}

function issueGoogleMediaCapability(record, fileId) {
  const mediaId = randomBytes(24).toString("base64url");
  mediaVault.set(mediaId, {
    ownerId: record.ownerId,
    connectionId: record.id,
    fileId,
    createdAt: Date.now(),
  });
  pruneVault(mediaVault, 500);
  return `/gateway/google-drive/media?mediaId=${encodeURIComponent(mediaId)}`;
}

function issueNasMediaCapability(record, filePath) {
  const mediaId = randomBytes(24).toString("base64url");
  nasVault.set(mediaId, {
    ownerId: record.ownerId,
    connectionId: record.id,
    filePath,
    createdAt: Date.now(),
  });
  pruneVault(nasVault, 500);
  return `/gateway/nas/media?mediaId=${encodeURIComponent(mediaId)}`;
}

function resolveTranscodeInput(mediaUrl, ownerId) {
  let parsed;
  try {
    parsed = new URL(mediaUrl, "http://gateway.invalid");
  } catch {
    throw new Error("The transcode source is not a gateway media URL.");
  }
  if (parsed.pathname === "/gateway/nas/media" || parsed.pathname === "/api/nas/media") {
    const media = nasVault.get(parsed.searchParams.get("mediaId") ?? "");
    if (!media || media.ownerId !== ownerId) throw new Error("The transcode source is invalid or expired.");
    return { kind: "nas", input: media.filePath };
  }
  if (parsed.pathname === "/gateway/stremio/media" || parsed.pathname === "/api/stremio/media") {
    const stream = streamVault.get(parsed.searchParams.get("streamId") ?? "");
    if (!stream || stream.ownerId !== ownerId) throw new Error("The transcode source is invalid or expired.");
    return { kind: "stremio", input: stream.target, targetPolicy: stream.targetPolicy };
  }
  throw new Error("Only NAS and Stremio gateway media can be transcoded locally.");
}

async function resolveRequestedTranscodeInput(payload, ownerId) {
  const hasGatewayMedia = payload.mediaUrl !== undefined;
  const hasRemoteTarget = payload.remoteUrl !== undefined;
  if (hasGatewayMedia === hasRemoteTarget) {
    throw new Error("Provide exactly one gateway media URL or remote media URL.");
  }
  if (hasGatewayMedia) {
    return resolveTranscodeInput(requireString(payload.mediaUrl, "Media URL", 4096), ownerId);
  }

  // A directly resolved Apple candidate has no pre-existing connection
  // policy. Authorize it as public HTTPS only, then retain the authorization
  // policy so every relay fetch revalidates the same origin and network class.
  const authorization = await authorizeTarget(
    requireString(payload.remoteUrl, "Remote media URL", 8192),
    { allowPrivateNetwork: false },
  );
  return {
    kind: "remote",
    input: authorization.url.toString(),
    targetPolicy: authorization.policy,
  };
}

function normalizeXrMediaSource(value, origin) {
  const source = requireString(value, "XR media source", 8192);
  const url = new URL(source, origin);
  const sameOrigin = url.origin === origin;
  const loopback = url.hostname === "127.0.0.1" || url.hostname === "localhost" || url.hostname === "[::1]";
  if (!sameOrigin && url.protocol !== "https:" && !(url.protocol === "http:" && loopback)) {
    throw new Error("XR media URLs must use HTTPS or a loopback development address.");
  }
  if (url.username || url.password) throw new Error("Credentials are not accepted in XR media URLs.");
  return url.toString();
}

function issueXrHandoff(payload, ownerId, origin) {
  if (!origin) throw new Error("XR handoffs require the OpenStream browser origin.");
  const projection = ["180", "360", "wide"].includes(payload.projection) ? payload.projection : "180";
  const stereo = ["mono", "sbs", "tb"].includes(payload.stereo) ? payload.stereo : "mono";
  const dynamicRange = optionalString(payload.dynamicRange, 32)?.replace(/[^a-z0-9+ ._-]/gi, "") || "runtime check";
  const handoffId = randomBytes(24).toString("base64url");
  xrHandoffVault.set(handoffId, {
    ownerId,
    source: normalizeXrMediaSource(payload.source, origin),
    projection,
    stereo,
    dynamicRange,
    createdAt: Date.now(),
  });
  pruneVault(xrHandoffVault, 250);
  return `/xr/viewer#handoff=${encodeURIComponent(handoffId)}`;
}

function redeemXrHandoff(value, ownerId) {
  const handoffId = requireString(value, "XR handoff ID", 128);
  if (!/^[A-Za-z0-9_-]+$/.test(handoffId)) throw new Error("XR handoff ID is invalid.");
  const handoff = xrHandoffVault.get(handoffId);
  if (!handoff || handoff.ownerId !== ownerId) {
    throw new Error("The XR handoff is invalid, expired, or already used.");
  }
  xrHandoffVault.delete(handoffId);
  if (Date.now() - handoff.createdAt > 5 * 60_000) throw new Error("The XR handoff is invalid, expired, or already used.");
  return {
    source: handoff.source,
    projection: handoff.projection,
    stereo: handoff.stereo,
    dynamicRange: handoff.dynamicRange,
  };
}

async function routeRequest(request, response, session, logger, metadataService, netflixTop10Service, runtime) {
  const origin = request.headers.origin;
  const requestUrl = parseCanonicalRequestTarget(request.url ?? "/", {
    origin: runtime.origin,
    prefix: "/api",
  });
  if (!requestUrl) throw new GatewayHttpError(404, "Gateway route not found.");
  if (!hostHeaderAllowed(request.headers.host, runtime)) throw new Error("Invalid gateway host header.");
  if (request.method === "OPTIONS") {
    assertAllowedOrigin(origin, allowedOrigins);
    response.writeHead(204, securityHeaders(origin));
    response.end();
    return;
  }
  if (requestUrl.pathname === "/api/oauth/google/start" && request.method === "GET") return beginGoogleOAuth(requestUrl, response);
  if (requestUrl.pathname === "/api/oauth/google/callback" && request.method === "GET") return finishGoogleOAuth(requestUrl, response);
  if (requestUrl.pathname === "/api/transcode/input" && request.method === "GET") {
    // Internal loopback route for the local ffmpeg child: the single-purpose
    // token exists only in the transcoder's command line, never in a browser,
    // so remote bytes always flow through the gateway's safe fetch.
    const inputToken = requireString(requestUrl.searchParams.get("inputToken"), "Transcode input token", 128);
    const input = transcodeInputVault.get(inputToken);
    if (!input || Date.now() - input.createdAt > 12 * 60 * 60_000) {
      transcodeInputVault.delete(inputToken);
      throw new Error("The transcode input token is invalid or expired.");
    }
    const range = validRange(request);
    const upstream = await safeStreamRequest(input.target, {
      headers: range ? { Range: range } : undefined,
    }, input.targetPolicy);
    pipeStream(request, response, upstream, origin);
    return;
  }
  // The random transcode ID is a scoped, expiring bearer capability. This
  // lets native AVPlayer open only the prepared media route without exposing
  // the gateway-wide session token or relying on undocumented HTTP headers.
  const transcodeCapability = activeTranscodeCapability(request, requestUrl);
  const ownerId = transcodeCapability?.ownerId ?? authenticateSession(request, session);
  if (origin) assertAllowedOrigin(origin, allowedOrigins);
  else if (!transcodeCapability &&
    request.headers["x-openstream-proxy"] !== "loopback"
    && !new Set(["android", "apple"]).has(request.headers["x-openstream-client"])
  ) {
    throw new Error("Gateway requests must come from the OpenStream app origin.");
  }
  if (origin && request.method === "POST" && request.headers["x-openstream-request"] !== "1") {
    throw new Error("Gateway mutation requests require the OpenStream request header.");
  }

  if (requestUrl.pathname === "/api/health" && request.method === "GET") {
    const connections = [...connectionVault.values()].filter((record) => record.ownerId === ownerId).length;
    return sendJson(response, 200, { ok: true, connections }, origin);
  }
  if (requestUrl.pathname === "/api/connections" && request.method === "GET") {
    const connections = [...connectionVault.values()].filter((record) => record.ownerId === ownerId).map(publicConnection);
    return sendJson(response, 200, { connections }, origin);
  }
  if (requestUrl.pathname === "/api/connections" && request.method === "POST") {
    return sendJson(response, 200, await testConnection(await readJson(request), ownerId), origin);
  }
  if (requestUrl.pathname === "/api/metadata/recent" && request.method === "GET") {
    return sendJson(response, 200, metadataService.getSnapshot(), origin);
  }
  if (requestUrl.pathname === "/api/catalog/netflix/top10" && request.method === "GET") {
    return sendJson(response, 200, netflixTop10Service.getSnapshot(), origin);
  }

  if (requestUrl.pathname === "/api/arr/options" && request.method === "GET") {
    const record = getConnection(requestUrl.searchParams.get("connectionId"), ["sonarr", "radarr"], ownerId);
    return sendJson(response, 200, await arrOptions(record), origin);
  }
  if (requestUrl.pathname === "/api/arr/request" && request.method === "POST") {
    const payload = await readJson(request);
    const record = getConnection(payload.connectionId, ["sonarr", "radarr"], ownerId);
    return sendJson(response, 200, { result: await sendArrRequest(record, payload.request ?? {}) }, origin);
  }
  if (requestUrl.pathname === "/api/usenet/handoff" && request.method === "POST") {
    const payload = await readJson(request);
    const record = getConnection(payload.connectionId, ["sabnzbd", "nzbget"], ownerId);
    return sendJson(response, 200, { result: await handoffNzb(record, payload) }, origin);
  }
  if (requestUrl.pathname === "/api/stremio/streams" && request.method === "POST") {
    const payload = await readJson(request);
    const record = getConnection(payload.connectionId, ["stremio"], ownerId);
    const type = encodeURIComponent(requireString(payload.type, "Stremio type", 128));
    const id = encodeURIComponent(requireString(payload.id, "Stremio ID", 512));
    const streams = await safeRequestJson(`${record.transportUrl}/stream/${type}/${id}.json`, {}, connectionPolicy(record));
    const sanitized = Array.isArray(streams.streams)
      ? (await Promise.all(streams.streams.slice(0, 100).map((stream) => sanitizeStremioStream(record, stream)))).filter(Boolean)
      : [];
    return sendJson(response, 200, { streams: sanitized }, origin);
  }
  if (requestUrl.pathname === "/api/stremio/media" && request.method === "GET") {
    const streamId = requireString(requestUrl.searchParams.get("streamId"), "Stream ID", 128);
    const stream = streamVault.get(streamId);
    if (!stream || stream.ownerId !== ownerId) {
      throw new Error("The Stremio stream route is invalid or expired.");
    }
    if (Date.now() - stream.createdAt > 30 * 60_000) {
      streamVault.delete(streamId);
      throw new Error("The Stremio stream route is invalid or expired.");
    }
    // Re-validate that the owning Stremio connection still exists in this
    // session; the returned record is unused so it is not bound.
    getConnection(stream.connectionId, ["stremio"], ownerId);
    const range = validRange(request);
    const upstream = await safeStreamRequest(stream.target, {
      headers: range ? { Range: range } : undefined,
    }, stream.targetPolicy);
    pipeStream(request, response, upstream, origin);
    return;
  }
  if (requestUrl.pathname === "/api/xr/handoffs" && request.method === "POST") {
    const payload = await readJson(request);
    return sendJson(response, 201, { viewerUrl: issueXrHandoff(payload, ownerId, origin) }, origin);
  }
  if (requestUrl.pathname === "/api/xr/handoffs/redeem" && request.method === "POST") {
    const payload = await readJson(request);
    return sendJson(response, 200, redeemXrHandoff(payload.handoffId, ownerId), origin);
  }
  if (requestUrl.pathname === "/api/google-drive/files" && request.method === "GET") {
    const record = getConnection(requestUrl.searchParams.get("connectionId"), ["google-drive"], ownerId);
    const token = await driveAccessToken(record);
    const url = new URL("https://www.googleapis.com/drive/v3/files");
    url.searchParams.set("q", "trashed = false and mimeType contains 'video/'");
    url.searchParams.set("pageSize", "100");
    url.searchParams.set("orderBy", "modifiedTime desc");
    url.searchParams.set("fields", "nextPageToken,files(id,name,mimeType,size,modifiedTime,thumbnailLink,videoMediaMetadata)");
    const files = await safeRequestJson(url.toString(), { headers: { Authorization: `Bearer ${token}` } });
    return sendJson(response, 200, files, origin);
  }
  if (requestUrl.pathname === "/api/google-drive/media-capability" && request.method === "POST") {
    const payload = await readJson(request);
    const record = getConnection(payload.connectionId, ["google-drive"], ownerId);
    return sendJson(response, 201, {
      mediaUrl: issueGoogleMediaCapability(record, requireGoogleFileId(payload.fileId)),
    }, origin);
  }
  if (requestUrl.pathname === "/api/google-drive/media" && request.method === "GET") {
    const mediaId = requireString(requestUrl.searchParams.get("mediaId"), "Google Drive media capability", 128);
    const media = mediaVault.get(mediaId);
    if (!media || media.ownerId !== ownerId) {
      throw new Error("The Google Drive media route is invalid or expired.");
    }
    if (Date.now() - media.createdAt > 30 * 60_000) {
      mediaVault.delete(mediaId);
      throw new Error("The Google Drive media route is invalid or expired.");
    }
    const record = getConnection(media.connectionId, ["google-drive"], ownerId);
    const range = validRange(request);
    const token = await driveAccessToken(record);
    const upstream = await safeStreamRequest(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(media.fileId)}?alt=media`, {
      headers: { Authorization: `Bearer ${token}`, ...(range ? { Range: range } : {}) },
    });
    pipeStream(request, response, upstream, origin);
    return;
  }
  if (requestUrl.pathname === "/api/nas/browse" && request.method === "GET") {
    const record = getConnection(requestUrl.searchParams.get("connectionId"), ["nas-folder"], ownerId);
    return sendJson(response, 200, await listNasDirectory(record.rootPath, requestUrl.searchParams.get("path") ?? ""), origin);
  }
  if (requestUrl.pathname === "/api/nas/media-capability" && request.method === "POST") {
    const payload = await readJson(request);
    const record = getConnection(payload.connectionId, ["nas-folder"], ownerId);
    const filePath = await resolveWithinRoot(record.rootPath, requireString(payload.path, "NAS media path", 4096));
    return sendJson(response, 201, { mediaUrl: issueNasMediaCapability(record, filePath) }, origin);
  }
  if (requestUrl.pathname === "/api/nas/media" && request.method === "GET") {
    const mediaId = requireString(requestUrl.searchParams.get("mediaId"), "NAS media capability", 128);
    const media = nasVault.get(mediaId);
    if (!media || media.ownerId !== ownerId) throw new Error("The NAS media route is invalid or expired.");
    if (Date.now() - media.createdAt > 12 * 60 * 60_000) {
      nasVault.delete(mediaId);
      throw new Error("The NAS media route is invalid or expired.");
    }
    getConnection(media.connectionId, ["nas-folder"], ownerId);
    await streamNasFile(request, response, media.filePath, securityHeaders(origin));
    return;
  }
  if (requestUrl.pathname === "/api/transcode/capabilities" && request.method === "GET") {
    return sendJson(response, 200, await probeTranscoder(), origin);
  }
  if (requestUrl.pathname === "/api/transcode/smb-sessions" && request.method === "POST") {
    const payload = await readJson(request);
    const probe = await probeTranscoder();
    if (!probe.available) throw new Error("Local transcoding is unavailable: ffmpeg was not found on this machine.");
    const input = await resolveMappedSmbPath(requireString(payload.smbUri, "SMB media URI", 8192), runtime.nasMappings);
    const transcodeId = randomBytes(24).toString("base64url");
    transcodeVault.set(transcodeId, {
      ownerId,
      input,
      inputKind: "nas",
      profile: payload.profile && typeof payload.profile === "object" ? payload.profile : {},
      createdAt: Date.now(),
    });
    pruneVault(transcodeVault, 100);
    void logger?.info("transcode", "SMB mapped session created");
    return sendJson(response, 201, { transcodeUrl: `/gateway/transcode/media?transcodeId=${encodeURIComponent(transcodeId)}` }, origin);
  }
  if (requestUrl.pathname === "/api/transcode/sessions" && request.method === "POST") {
    const payload = await readJson(request);
    const resolved = await resolveRequestedTranscodeInput(payload, ownerId);
    const probe = await probeTranscoder();
    if (!probe.available) throw new Error("Local transcoding is unavailable: ffmpeg was not found on this machine.");
    const transcodeId = randomBytes(24).toString("base64url");
    transcodeVault.set(transcodeId, {
      ownerId,
      input: resolved.input,
      inputKind: resolved.kind,
      targetPolicy: resolved.targetPolicy,
      profile: payload.profile && typeof payload.profile === "object" ? payload.profile : {},
      createdAt: Date.now(),
    });
    pruneVault(transcodeVault, 100);
    void logger?.info("transcode", `session created for a ${resolved.kind} source`);
    return sendJson(response, 201, { transcodeUrl: `/gateway/transcode/media?transcodeId=${encodeURIComponent(transcodeId)}` }, origin);
  }
  if (requestUrl.pathname === "/api/transcode/media" && request.method === "GET") {
    const transcodeId = requireString(requestUrl.searchParams.get("transcodeId"), "Transcode session", 128);
    const sessionRecord = transcodeVault.get(transcodeId);
    if (!sessionRecord || sessionRecord.ownerId !== ownerId) throw new Error("The transcode session is invalid or expired.");
    if (Date.now() - sessionRecord.createdAt > 12 * 60 * 60_000) {
      transcodeVault.delete(transcodeId);
      throw new Error("The transcode session is invalid or expired.");
    }
    const probe = await probeTranscoder();
    if (!probe.available) throw new Error("Local transcoding is unavailable: ffmpeg was not found on this machine.");
    let input = sessionRecord.input;
    let inputToken;
    if (sessionRecord.inputKind === "stremio" || sessionRecord.inputKind === "remote") {
      // ffmpeg must never dial the remote itself (it follows redirects and does
      // its own DNS); hand it a single-purpose loopback URL that relays through
      // the gateway's SSRF-safe fetch and keeps Range support for seeking.
      inputToken = randomBytes(24).toString("base64url");
      transcodeInputVault.set(inputToken, {
        target: sessionRecord.input,
        targetPolicy: sessionRecord.targetPolicy,
        createdAt: Date.now(),
      });
      pruneVault(transcodeInputVault, 100);
      input = `${runtime.origin}/api/transcode/input?inputToken=${encodeURIComponent(inputToken)}`;
    }
    const { child, plan } = startTranscode({ input, profile: sessionRecord.profile, encoders: probe.encoders });
    response.writeHead(200, { ...securityHeaders(origin), "Content-Type": "video/mp4", "Cache-Control": "no-store" });
    let stderrTail = "";
    child.stderr.on("data", (chunk) => { stderrTail = (stderrTail + chunk.toString("utf8")).slice(-4096); });
    child.stdout.pipe(response);
    request.on("close", () => child.kill("SIGKILL"));
    child.on("close", (code, signal) => {
      if (inputToken) transcodeInputVault.delete(inputToken);
      // Remote ffmpeg diagnostics can echo its loopback relay URL, including
      // the scoped input capability query. Keep remote playback logs entirely
      // query-free; local NAS diagnostics cannot contain a relay URL.
      const context = code && !signal && sessionRecord.inputKind === "nas"
        ? { stderr: stderrTail }
        : undefined;
      void logger?.info("transcode", `ffmpeg exited code=${code ?? "none"} signal=${signal ?? "none"} encoder=${plan.videoEncoder} cap=${plan.clamped.maxWidth}x${plan.clamped.maxHeight}`, context);
      response.end();
    });
    child.on("error", (error) => {
      if (inputToken) transcodeInputVault.delete(inputToken);
      void logger?.error("transcode", `ffmpeg spawn failed: ${error.message}`);
      response.destroy();
    });
    void logger?.info("transcode", `started ${plan.videoEncoder} for a ${sessionRecord.inputKind} source capped at ${plan.clamped.maxWidth}x${plan.clamped.maxHeight}`);
    return;
  }
  if (requestUrl.pathname === "/api/logs" && request.method === "POST") {
    const payload = await readJson(request);
    const entries = Array.isArray(payload.entries) ? payload.entries.slice(0, 50) : [];
    for (const entry of entries) {
      const level = entry?.level === "error" ? "error" : entry?.level === "warn" ? "warn" : "info";
      void logger?.[level]("client", typeof entry?.message === "string" ? entry.message.slice(0, 2048) : "client log entry", entry?.context);
    }
    return sendJson(response, 202, { accepted: entries.length }, origin);
  }
  sendJson(response, 404, { error: "Gateway route not found." }, origin);
}

export function createGatewayServer({
  sessionToken = process.env.OPENSTREAM_GATEWAY_TOKEN,
  logger = createLogger({ mirrorToConsole: false }),
  metadataService = createTmdbMetadataService(),
  netflixTop10Service = createNetflixTop10Service(),
  nasMappings = process.env.OPENSTREAM_NAS_MAPPINGS ?? "[]",
  allowLan = allowLanGateway,
} = {}) {
  const session = createGatewaySession(sessionToken);
  const runtime = {
    allowedHosts: new Set(),
    origin: `http://${urlHost}:${port}`,
    port,
    allowLan,
    nasMappings: parseNasMappings(nasMappings),
  };
  const server = http.createServer((request, response) => {
    const startedAt = Date.now();
    const loggedPath = (request.url ?? "/").split("?")[0];
    response.on("finish", () => {
      void logger?.info("gateway", `${request.method} ${loggedPath} -> ${response.statusCode}`, { ms: Date.now() - startedAt });
    });
    void routeRequest(request, response, session, logger, metadataService, netflixTop10Service, runtime).catch((error) => {
      const origin = request.headers.origin;
      const message = error instanceof SyntaxError ? "Request JSON is invalid." : error.message || "Gateway request failed.";
      const statusCode = Number.isInteger(error.statusCode) ? error.statusCode : 400;
      void logger?.warn("gateway", `${request.method} ${loggedPath} failed: ${message}`);
      if (response.headersSent) {
        // A streaming body already started; the JSON error channel is gone.
        response.destroy();
        return;
      }
      sendJson(response, statusCode, { error: message }, origin);
    });
  });
  server.on("listening", () => {
    const address = server.address();
    if (!address || typeof address === "string") return;
    const boundHost = address.address.includes(":") ? `[${address.address}]` : address.address;
    const internalHost = boundHost === "0.0.0.0" || boundHost === "[::]" ? "127.0.0.1" : boundHost;
    runtime.origin = `http://${internalHost}:${address.port}`;
    runtime.port = address.port;
    runtime.allowedHosts = new Set([
      `${boundHost}:${address.port}`,
      `127.0.0.1:${address.port}`,
      `localhost:${address.port}`,
      `[::1]:${address.port}`,
    ]);
  });
  return server;
}

const isEntrypoint = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isEntrypoint) {
  const logger = createLogger();
  const metadataService = createTmdbMetadataService({
    onError: (error) => { void logger.warn("metadata", error.message); },
  });
  const netflixTop10Service = createNetflixTop10Service({
    onError: (error) => { void logger.warn("netflix-top10", error.message); },
  });
  const server = createGatewayServer({
    sessionToken: process.env.OPENSTREAM_GATEWAY_TOKEN,
    logger,
    metadataService,
    netflixTop10Service,
  });
  void Promise.allSettled([metadataService.start(), netflixTop10Service.start()]).finally(() => {
    server.listen(port, host, () => {
      console.log(`OpenStream secure gateway listening on http://${host}:${port}`);
      console.log(`OpenStream gateway logs: ${logger.directory}`);
    });
  });
  server.on("close", () => {
    metadataService.close();
    netflixTop10Service.close();
  });
}
