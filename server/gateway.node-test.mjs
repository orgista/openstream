import assert from "node:assert/strict";
import http from "node:http";
import test from "node:test";
import { createGatewayServer } from "./openstream-gateway.mjs";

const GATEWAY_SESSION_TOKEN = "test-session-token-that-is-long-enough-for-auth";
const OTHER_GATEWAY_SESSION_TOKEN = "other-session-token-that-is-long-enough-for-auth";

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve(server.address().port));
  });
}

function close(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => error ? reject(error) : resolve());
  });
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function gatewayRequest(port, path, {
  method = "GET",
  body,
  mutationHeader = true,
  origin = "http://127.0.0.1:5173",
  proxyMarker = false,
  nativeClient = null,
  sessionToken = GATEWAY_SESSION_TOKEN,
} = {}) {
  const encodedBody = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
  const headers = {
    Accept: "application/json",
    ...(origin ? { Origin: origin } : {}),
    ...(proxyMarker ? { "X-OpenStream-Proxy": "loopback" } : {}),
    ...(nativeClient ? { "X-OpenStream-Client": nativeClient } : {}),
    ...(sessionToken ? { "X-OpenStream-Session": sessionToken } : {}),
    ...(encodedBody ? { "Content-Type": "application/json", "Content-Length": encodedBody.length } : {}),
    ...(method === "POST" && mutationHeader ? { "X-OpenStream-Request": "1" } : {}),
  };
  return new Promise((resolve, reject) => {
    const request = http.request({ hostname: "127.0.0.1", port, path, method, headers }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const text = Buffer.concat(chunks).toString("utf8");
        const isJson = response.headers["content-type"]?.includes("application/json");
        resolve({ status: response.statusCode, headers: response.headers, body: text && isJson ? JSON.parse(text) : text || null });
      });
    });
    request.on("error", reject);
    if (encodedBody) request.write(encodedBody);
    request.end();
  });
}

function gatewayMediaRequest(port, path, range, { sessionToken = GATEWAY_SESSION_TOKEN } = {}) {
  return new Promise((resolve, reject) => {
    const request = http.request({
      hostname: "127.0.0.1",
      port,
      path,
      headers: {
        Origin: "http://127.0.0.1:5173",
        Range: range,
        ...(sessionToken ? { "X-OpenStream-Session": sessionToken } : {}),
      },
    }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => resolve({ status: response.statusCode, headers: response.headers, body: Buffer.concat(chunks) }));
    });
    request.on("error", reject);
    request.end();
  });
}

test("gateway refuses to start without a safe session token", () => {
  assert.throws(() => createGatewayServer({ sessionToken: null }), /OPENSTREAM_GATEWAY_TOKEN/);
  assert.throws(() => createGatewayServer({ sessionToken: `${"a".repeat(32)}\r\nInjected: true` }), /base64url/);
});

test("gateway admits authenticated Android and Apple native clients only", async () => {
  const gateway = createGatewayServer({ sessionToken: GATEWAY_SESSION_TOKEN, logger: null });
  const gatewayPort = await listen(gateway);
  try {
    for (const nativeClient of ["android", "apple"]) {
      const result = await gatewayRequest(gatewayPort, "/api/health", { origin: null, nativeClient });
      assert.equal(result.status, 200, nativeClient);
    }
    const unknown = await gatewayRequest(gatewayPort, "/api/health", {
      origin: null,
      nativeClient: "unknown",
    });
    assert.equal(unknown.status, 400);
  } finally {
    await close(gateway);
  }
});

test("gateway exposes the cached Netflix Top 10 snapshot through the authenticated catalog route", async () => {
  const snapshot = {
    country: "US",
    source: "netflix-public-trending",
    cadence: "daily",
    refreshedAt: 1234,
    stale: false,
    lists: { overall: [{ rank: 1, title: "The Hawk" }], movies: [], series: [] },
  };
  const gateway = createGatewayServer({
    sessionToken: GATEWAY_SESSION_TOKEN,
    logger: null,
    metadataService: { getSnapshot: () => ({ enabled: false, movies: [] }) },
    netflixTop10Service: { getSnapshot: () => snapshot },
  });
  const gatewayPort = await listen(gateway);
  try {
    const response = await gatewayRequest(gatewayPort, "/api/catalog/netflix/top10");
    assert.equal(response.status, 200);
    assert.deepEqual(response.body, snapshot);
  } finally {
    await close(gateway);
  }
});

test("gateway enforces connector boundaries and server-side handoffs", async () => {
  const calls = [];
  let servicePort;
  let arrProfiles = [{ id: 4, name: "Remux" }];
  let arrRoots = [{ id: 2, path: "/media/movies", freeSpace: 500000000000 }];
  const service = http.createServer(async (request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    const body = await readBody(request);
    calls.push({ method: request.method, path: url.pathname, query: Object.fromEntries(url.searchParams), headers: request.headers, body });
    response.setHeader("Content-Type", "application/json");

    if (url.pathname === "/manifest.json") {
      response.end(JSON.stringify({ id: "org.openstream.test", name: "Test Add-on", version: "1.0.0", resources: ["stream"] }));
      return;
    }
    if (url.pathname === "/stream/movie/tt123.json") {
      response.end(JSON.stringify({ streams: [
        { name: "Local media", title: "Gateway proxy", url: `http://127.0.0.1:${servicePort}/media.mp4` },
        { name: "Hash", infoHash: "0123456789abcdef0123456789abcdef01234567", fileIdx: 0 },
        { name: "Unapproved private service", url: "http://127.0.0.1:1/admin" },
        { name: "Mapped private service", url: "https://[::ffff:7f00:1]:1/admin" },
        { name: "Unsafe", url: "javascript:alert(1)" },
      ] }));
      return;
    }
    if (url.pathname === "/media.mp4") {
      const payload = Buffer.from("demo-media");
      response.statusCode = request.headers.range ? 206 : 200;
      response.setHeader("Content-Type", "video/mp4");
      response.setHeader("Accept-Ranges", "bytes");
      response.setHeader("Content-Range", "bytes 0-3/10");
      response.end(request.headers.range ? payload.subarray(0, 4) : payload);
      return;
    }
    if (url.pathname === "/api/v3/system/status") {
      const isSonarr = request.headers["x-api-key"] === "sonarr-secret";
      response.end(JSON.stringify({
        appName: isSonarr ? "Sonarr" : "Radarr",
        instanceName: isSonarr ? "OpenStream Sonarr" : "OpenStream Radarr",
        version: "5.0.0",
      }));
      return;
    }
    if (url.pathname === "/api/v3/qualityprofile") {
      response.end(JSON.stringify(arrProfiles));
      return;
    }
    if (url.pathname === "/api/v3/rootfolder") {
      response.end(JSON.stringify(arrRoots));
      return;
    }
    if (url.pathname === "/api/v3/movie" && request.method === "POST") {
      response.end(JSON.stringify({ id: 44, title: "Northstar", monitored: true }));
      return;
    }
    if (url.pathname === "/api/v3/series" && request.method === "POST") {
      response.end(JSON.stringify({ id: 45, title: "Echoes of Mars", monitored: true }));
      return;
    }
    if (url.pathname === "/api" && url.searchParams.get("mode") === "version") {
      response.end(JSON.stringify({ version: "4.5.0" }));
      return;
    }
    if (url.pathname === "/api" && url.searchParams.get("mode") === "addurl") {
      response.end(JSON.stringify({ status: true, nzo_ids: ["SABnzbd_nzo_test"] }));
      return;
    }
    if (url.pathname === "/jsonrpc") {
      const rpc = JSON.parse(body);
      response.end(JSON.stringify({ jsonrpc: "2.0", id: rpc.id, result: rpc.method === "version" ? "24.4" : 91 }));
      return;
    }

    response.statusCode = 404;
    response.end(JSON.stringify({ error: "not found" }));
  });
  servicePort = await listen(service);
  const gateway = createGatewayServer({ sessionToken: GATEWAY_SESSION_TOKEN });
  const gatewayPort = await listen(gateway);
  const baseUrl = `http://127.0.0.1:${servicePort}`;

  try {
    const denied = await gatewayRequest(gatewayPort, "/api/connections", {
      method: "POST",
      body: { kind: "stremio", baseUrl, credential: "", allowPrivateNetwork: false },
    });
    assert.equal(denied.status, 400);
    assert.match(denied.body.error, /Private-network/);

    const stremio = await gatewayRequest(gatewayPort, "/api/connections", {
      method: "POST",
      body: { kind: "stremio", baseUrl, credential: "", allowPrivateNetwork: true },
    });
    assert.equal(stremio.status, 200);
    assert.equal(stremio.body.connection.state, "connected");
    const streamResult = await gatewayRequest(gatewayPort, "/api/stremio/streams", {
      method: "POST",
      body: { connectionId: stremio.body.connection.id, type: "movie", id: "tt123" },
    });
    assert.equal(streamResult.status, 200);
    assert.equal(streamResult.body.streams.length, 2);
    assert.equal(JSON.stringify(streamResult.body).includes("javascript:"), false);
    assert.equal(JSON.stringify(streamResult.body).includes("127.0.0.1:1"), false);
    assert.match(streamResult.body.streams[0].url, /^\/gateway\/stremio\/media\?/);
    assert.equal(streamResult.body.streams[0].url.includes("connectionId"), false);
    const media = await gatewayMediaRequest(
      gatewayPort,
      streamResult.body.streams[0].url.replace(/^\/gateway/, "/api"),
      "bytes=0-3",
    );
    assert.equal(media.status, 206);
    assert.equal(media.headers["content-type"], "video/mp4");
    assert.equal(media.body.toString("utf8"), "demo");

    const radarr = await gatewayRequest(gatewayPort, "/api/connections", {
      method: "POST",
      body: { kind: "radarr", baseUrl, credential: "radarr-secret", allowPrivateNetwork: true },
    });
    assert.equal(radarr.status, 200);
    assert.equal(JSON.stringify(radarr.body).includes("radarr-secret"), false);
    const options = await gatewayRequest(gatewayPort, `/api/arr/options?connectionId=${encodeURIComponent(radarr.body.connection.id)}`);
    assert.deepEqual(options.body.profiles, [{ id: 4, name: "Remux" }]);

    arrProfiles = Array.from({ length: 128 }, (_, id) => ({ id, name: `Profile ${id}` }));
    arrRoots = Array.from({ length: 128 }, (_, id) => ({ id, path: `/media/${id}`, freeSpace: id }));
    const boundedOptions = await gatewayRequest(gatewayPort, `/api/arr/options?connectionId=${encodeURIComponent(radarr.body.connection.id)}`);
    assert.equal(boundedOptions.status, 200);
    assert.equal(boundedOptions.body.profiles.length, 128);
    assert.equal(boundedOptions.body.roots.length, 128);

    arrProfiles = [...arrProfiles, { id: 129, name: "Too many" }];
    const oversizedOptions = await gatewayRequest(gatewayPort, `/api/arr/options?connectionId=${encodeURIComponent(radarr.body.connection.id)}`);
    assert.equal(oversizedOptions.status, 400);
    assert.match(oversizedOptions.body.error, /at most|limit|many/i);

    arrProfiles = [{ id: 4, name: "   " }];
    arrRoots = [{ id: 2, path: "/media/movies", freeSpace: 500000000000 }];
    const malformedOptions = await gatewayRequest(gatewayPort, `/api/arr/options?connectionId=${encodeURIComponent(radarr.body.connection.id)}`);
    assert.equal(malformedOptions.status, 400);
    assert.match(malformedOptions.body.error, /required|invalid/i);

    arrProfiles = [{ id: 4, name: "Remux" }];
    const arrRequest = await gatewayRequest(gatewayPort, "/api/arr/request", {
      method: "POST",
      body: {
        connectionId: radarr.body.connection.id,
        request: { title: "Northstar", year: 2025, tmdbId: 123, qualityProfileId: 4, rootFolderPath: "/media/movies" },
      },
    });
    assert.equal(arrRequest.body.result.id, 44);

    const sonarr = await gatewayRequest(gatewayPort, "/api/connections", {
      method: "POST",
      body: { kind: "sonarr", baseUrl, credential: "sonarr-secret", allowPrivateNetwork: true },
    });
    assert.equal(sonarr.status, 200);
    const sonarrRequest = await gatewayRequest(gatewayPort, "/api/arr/request", {
      method: "POST",
      body: {
        connectionId: sonarr.body.connection.id,
        request: { title: "Echoes of Mars", year: 2025, tvdbId: 456, qualityProfileId: 4, rootFolderPath: "/media/series" },
      },
    });
    assert.equal(sonarrRequest.body.result.id, 45);

    const sabnzbd = await gatewayRequest(gatewayPort, "/api/connections", {
      method: "POST",
      body: { kind: "sabnzbd", baseUrl, credential: "sab-secret", allowPrivateNetwork: true },
    });
    assert.equal(sabnzbd.status, 200);
    assert.equal(JSON.stringify(sabnzbd.body).includes("sab-secret"), false);
    const handoff = await gatewayRequest(gatewayPort, "/api/usenet/handoff", {
      method: "POST",
      body: { connectionId: sabnzbd.body.connection.id, nzbUrl: "https://provider.example/northstar.nzb", category: "movies" },
    });
    assert.equal(handoff.body.result.status, true);

    const nzbget = await gatewayRequest(gatewayPort, "/api/connections", {
      method: "POST",
      body: { kind: "nzbget", baseUrl, username: "openstream", credential: "nzb-password", allowPrivateNetwork: true },
    });
    assert.equal(nzbget.status, 200);
    assert.equal(JSON.stringify(nzbget.body).includes("nzb-password"), false);
    const nzbgetHandoff = await gatewayRequest(gatewayPort, "/api/usenet/handoff", {
      method: "POST",
      body: { connectionId: nzbget.body.connection.id, nzbUrl: "https://provider.example/episode.nzb", category: "series" },
    });
    assert.equal(nzbgetHandoff.body.result.result, 91);

    const drive = await gatewayRequest(gatewayPort, "/api/connections", {
      method: "POST",
      body: {
        kind: "google-drive",
        credential: "synthetic-google-client-id",
        appOrigin: "http://127.0.0.1:5173",
      },
    });
    assert.equal(drive.status, 200);
    const authorizationUrl = new URL(drive.body.authorizationUrl);
    const oauthStart = await gatewayRequest(gatewayPort, `${authorizationUrl.pathname}${authorizationUrl.search}`, {
      origin: null,
      sessionToken: null,
    });
    assert.equal(oauthStart.status, 302);
    assert.match(oauthStart.headers.location, /^https:\/\/accounts\.google\.com\/o\/oauth2\/v2\/auth\?/);
    assert.equal(new URL(oauthStart.headers.location).searchParams.get("code_challenge_method"), "S256");

    const driveMediaCapability = await gatewayRequest(gatewayPort, "/api/google-drive/media-capability", {
      method: "POST",
      body: { connectionId: drive.body.connection.id, fileId: "private-file" },
    });
    assert.equal(driveMediaCapability.status, 201);
    assert.match(driveMediaCapability.body.mediaUrl, /^\/gateway\/google-drive\/media\?mediaId=/);
    assert.equal(driveMediaCapability.body.mediaUrl.includes("private-file"), false);
    assert.equal(driveMediaCapability.body.mediaUrl.includes(drive.body.connection.id), false);

    const signedSource = "https://media.example/movie.mp4?token=synthetic-secret#private-fragment";
    const xrHandoff = await gatewayRequest(gatewayPort, "/api/xr/handoffs", {
      method: "POST",
      body: { source: signedSource, projection: "180", stereo: "sbs", dynamicRange: "Dolby Vision" },
    });
    assert.equal(xrHandoff.status, 201);
    assert.match(xrHandoff.body.viewerUrl, /^\/xr\/viewer#handoff=/);
    assert.equal(xrHandoff.body.viewerUrl.includes("synthetic-secret"), false);
    const handoffId = new URL(xrHandoff.body.viewerUrl, "http://127.0.0.1:5173").hash.slice("#handoff=".length);
    const redeemedHandoff = await gatewayRequest(gatewayPort, "/api/xr/handoffs/redeem", {
      method: "POST",
      body: { handoffId },
    });
    assert.equal(redeemedHandoff.status, 200);
    assert.equal(redeemedHandoff.body.source, signedSource);
    assert.equal(redeemedHandoff.body.projection, "180");
    assert.equal(redeemedHandoff.body.stereo, "sbs");
    const replayedHandoff = await gatewayRequest(gatewayPort, "/api/xr/handoffs/redeem", {
      method: "POST",
      body: { handoffId },
    });
    assert.equal(replayedHandoff.status, 400);

    const arrCall = calls.find((call) => call.path === "/api/v3/movie");
    assert.equal(arrCall.headers["x-api-key"], "radarr-secret");
    assert.equal(JSON.parse(arrCall.body).addOptions.searchForMovie, true);
    const sabCall = calls.find((call) => call.query.mode === "addurl");
    assert.equal(sabCall.query.name, "https://provider.example/northstar.nzb");
    assert.equal(sabCall.query.cat, "movies");
    const sonarrCall = calls.find((call) => call.path === "/api/v3/series");
    assert.equal(sonarrCall.headers["x-api-key"], "sonarr-secret");
    assert.equal(JSON.parse(sonarrCall.body).addOptions.searchForMissingEpisodes, true);
    const nzbgetCalls = calls.filter((call) => call.path === "/jsonrpc");
    assert.equal(nzbgetCalls.length, 2);
    assert.equal(nzbgetCalls[1].headers.authorization, `Basic ${Buffer.from("openstream:nzb-password").toString("base64")}`);
    assert.equal(JSON.parse(nzbgetCalls[1].body).method, "append");

    const callsBeforeAttacks = calls.length;
    const originlessAttack = { origin: null, proxyMarker: true, sessionToken: null };
    const protectedRequests = [
      { path: "/api/connections" },
      { path: `/api/arr/options?connectionId=${encodeURIComponent(radarr.body.connection.id)}` },
      {
        path: "/api/arr/request",
        method: "POST",
        body: {
          connectionId: radarr.body.connection.id,
          request: { title: "Attack", year: 2025, tmdbId: 999, qualityProfileId: 4, rootFolderPath: "/media/movies" },
        },
      },
      {
        path: "/api/arr/request",
        method: "POST",
        body: {
          connectionId: sonarr.body.connection.id,
          request: { title: "Attack", year: 2025, tvdbId: 999, qualityProfileId: 4, rootFolderPath: "/media/series" },
        },
      },
      {
        path: "/api/usenet/handoff",
        method: "POST",
        body: { connectionId: sabnzbd.body.connection.id, nzbUrl: "https://provider.example/attack.nzb" },
      },
      {
        path: "/api/usenet/handoff",
        method: "POST",
        body: { connectionId: nzbget.body.connection.id, nzbUrl: "https://provider.example/attack.nzb" },
      },
      {
        path: "/api/stremio/streams",
        method: "POST",
        body: { connectionId: stremio.body.connection.id, type: "movie", id: "tt123" },
      },
      {
        path: "/api/google-drive/media-capability",
        method: "POST",
        body: { connectionId: drive.body.connection.id, fileId: "private-file" },
      },
      {
        path: "/api/xr/handoffs",
        method: "POST",
        body: { source: signedSource, projection: "180", stereo: "sbs", dynamicRange: "Dolby Vision" },
      },
      { path: `/api/google-drive/files?connectionId=${encodeURIComponent(drive.body.connection.id)}` },
      { path: `/api/google-drive/media?connectionId=${encodeURIComponent(drive.body.connection.id)}&fileId=private-file` },
    ];

    for (const attack of protectedRequests) {
      const result = await gatewayRequest(gatewayPort, attack.path, { ...attack, ...originlessAttack });
      assert.equal(result.status, 401, `${attack.method ?? "GET"} ${attack.path} must require a gateway session`);
    }

    const forged = await gatewayRequest(gatewayPort, "/api/connections", {
      origin: null,
      proxyMarker: true,
      sessionToken: "forged-session-token-that-is-long-enough-to-compare",
    });
    assert.equal(forged.status, 401);

    const unauthenticatedMedia = await gatewayMediaRequest(
      gatewayPort,
      streamResult.body.streams[0].url.replace(/^\/gateway/, "/api"),
      "bytes=0-3",
      { sessionToken: null },
    );
    assert.equal(unauthenticatedMedia.status, 401);
    assert.equal(calls.length, callsBeforeAttacks, "rejected callers must not reach an upstream service");

    for (const ambiguousPath of [
      "/api/../api/connections",
      "/api/%2e%2e/api/connections",
      "/api//connections",
    ]) {
      const ambiguous = await gatewayRequest(gatewayPort, ambiguousPath);
      assert.equal(ambiguous.status, 400, ambiguousPath);
    }

    const ownerBoundHandoff = await gatewayRequest(gatewayPort, "/api/xr/handoffs", {
      method: "POST",
      body: { source: signedSource, projection: "180", stereo: "sbs", dynamicRange: "Dolby Vision" },
    });
    const ownerBoundHandoffId = new URL(
      ownerBoundHandoff.body.viewerUrl,
      "http://127.0.0.1:5173",
    ).hash.slice("#handoff=".length);

    const otherGateway = createGatewayServer({ sessionToken: OTHER_GATEWAY_SESSION_TOKEN });
    const otherGatewayPort = await listen(otherGateway);
    try {
      const otherConnections = await gatewayRequest(otherGatewayPort, "/api/connections", {
        sessionToken: OTHER_GATEWAY_SESSION_TOKEN,
      });
      assert.deepEqual(otherConnections.body.connections, []);
      const crossOwner = await gatewayRequest(
        otherGatewayPort,
        `/api/arr/options?connectionId=${encodeURIComponent(radarr.body.connection.id)}`,
        { sessionToken: OTHER_GATEWAY_SESSION_TOKEN },
      );
      assert.equal(crossOwner.status, 400);
      assert.match(crossOwner.body.error, /not available/i);
      const crossOwnerHandoff = await gatewayRequest(otherGatewayPort, "/api/xr/handoffs/redeem", {
        method: "POST",
        body: { handoffId: ownerBoundHandoffId },
        sessionToken: OTHER_GATEWAY_SESSION_TOKEN,
      });
      assert.equal(crossOwnerHandoff.status, 400);
      assert.equal(calls.length, callsBeforeAttacks, "another valid session must not spend the first session's authority");
    } finally {
      await close(otherGateway);
    }
    const ownerRedemption = await gatewayRequest(gatewayPort, "/api/xr/handoffs/redeem", {
      method: "POST",
      body: { handoffId: ownerBoundHandoffId },
    });
    assert.equal(ownerRedemption.status, 200);
  } finally {
    await close(gateway);
    await close(service);
  }
});
