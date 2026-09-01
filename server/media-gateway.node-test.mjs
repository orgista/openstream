import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createLogger } from "./logger.mjs";
import { listNasDirectory, resolveWithinRoot, validateNasRoot } from "./nas.mjs";
import { createGatewayServer, parseNasMappings, resolveMappedSmbPath } from "./openstream-gateway.mjs";
import { buildTranscodeArgs, clampTranscodeProfile, probeTranscoder } from "./transcoder.mjs";

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

function gatewayRequest(port, requestPath, {
  method = "GET",
  body,
  sessionToken = GATEWAY_SESSION_TOKEN,
  range,
} = {}) {
  const encodedBody = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
  const headers = {
    Accept: "application/json",
    Origin: "http://127.0.0.1:5173",
    ...(sessionToken ? { "X-OpenStream-Session": sessionToken } : {}),
    ...(range ? { Range: range } : {}),
    ...(encodedBody ? { "Content-Type": "application/json", "Content-Length": encodedBody.length } : {}),
    ...(method === "POST" ? { "X-OpenStream-Request": "1" } : {}),
  };
  return new Promise((resolve, reject) => {
    const request = http.request({ hostname: "127.0.0.1", port, path: requestPath, method, headers }, (response) => {
      const chunks = [];
      response.on("data", (chunk) => chunks.push(chunk));
      response.on("end", () => {
        const raw = Buffer.concat(chunks);
        const isJson = response.headers["content-type"]?.includes("application/json");
        resolve({
          status: response.statusCode,
          headers: response.headers,
          body: isJson && raw.length ? JSON.parse(raw.toString("utf8")) : raw,
        });
      });
    });
    request.on("error", reject);
    if (encodedBody) request.write(encodedBody);
    request.end();
  });
}

async function makeNasFixture() {
  const root = await mkdtemp(path.join(os.tmpdir(), "openstream-nas-"));
  await mkdir(path.join(root, "Movies"));
  await writeFile(path.join(root, "Movies", "Family Trip (2026).mp4"), Buffer.from("0123456789abcdef"));
  await writeFile(path.join(root, "Movies", "notes.txt"), "not a video");
  await writeFile(path.join(root, "clip.mkv"), Buffer.alloc(32, 7));
  return root;
}

test("NAS path validation stays inside the connected root", async () => {
  const root = await validateNasRoot(await makeNasFixture());
  const inside = await resolveWithinRoot(root, "Movies");
  assert.ok(inside.startsWith(root));
  await assert.rejects(resolveWithinRoot(root, "../"), /invalid|escapes|ENOENT/i);
  await assert.rejects(resolveWithinRoot(root, "Movies/../../etc"), /escapes|ENOENT/i);
  await assert.rejects(resolveWithinRoot(root, "a\u0000b"), /invalid/i);

  const outside = await mkdtemp(path.join(os.tmpdir(), "openstream-outside-"));
  await writeFile(path.join(outside, "secret.mp4"), "secret");
  await symlink(path.join(outside, "secret.mp4"), path.join(root, "escape.mp4"));
  await assert.rejects(resolveWithinRoot(root, "escape.mp4"), /escapes/i);
  await rm(root, { recursive: true, force: true });
  await rm(outside, { recursive: true, force: true });
});

test("NAS listing returns only directories and video files", async () => {
  const root = await validateNasRoot(await makeNasFixture());
  const listing = await listNasDirectory(root, "");
  assert.deepEqual(listing.directories.map((entry) => entry.name), ["Movies"]);
  assert.deepEqual(listing.files.map((entry) => entry.name), ["clip.mkv"]);
  const movies = await listNasDirectory(root, "Movies");
  assert.deepEqual(movies.files.map((entry) => entry.name), ["Family Trip (2026).mp4"]);
  assert.equal(typeof movies.files[0].size, "number");
  await rm(root, { recursive: true, force: true });
});

test("SMB transcode mappings resolve only inside an explicit NAS root", async () => {
  const root = await makeNasFixture();
  const mappingsJson = JSON.stringify([
    { host: "192.168.1.87", share: "Media", rootPath: root },
  ]);
  const mappings = parseNasMappings(mappingsJson);
  try {
    const canonicalRoot = await validateNasRoot(root);
    const resolved = await resolveMappedSmbPath(
      "smb://192.168.1.87/Media/Movies/Family%20Trip%20(2026).mp4",
      mappings,
    );
    assert.equal(resolved, path.join(canonicalRoot, "Movies", "Family Trip (2026).mp4"));
    await assert.rejects(
      resolveMappedSmbPath("smb://192.168.1.87/Other/Movies/Family%20Trip%20(2026).mp4", mappings),
      /No OpenStream gateway NAS mapping/,
    );
    await assert.rejects(
      resolveMappedSmbPath("smb://192.168.1.87/Media/Movies/../..", mappings),
      /directory|file|escapes|ENOENT/i,
    );
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test("gateway serves NAS media with range support and owner binding", async () => {
  const root = await makeNasFixture();
  const server = createGatewayServer({ sessionToken: GATEWAY_SESSION_TOKEN, logger: null });
  const port = await listen(server);
  try {
    const connected = await gatewayRequest(port, "/api/connections", {
      method: "POST",
      body: { kind: "nas-folder", baseUrl: root, credential: "unused" },
    });
    assert.equal(connected.status, 200);
    assert.equal(connected.body.connection.state, "connected");
    const connectionId = connected.body.connection.id;

    const browse = await gatewayRequest(port, `/api/nas/browse?connectionId=${encodeURIComponent(connectionId)}&path=Movies`);
    assert.equal(browse.status, 200);
    assert.equal(browse.body.files[0].name, "Family Trip (2026).mp4");

    const traversal = await gatewayRequest(port, `/api/nas/browse?connectionId=${encodeURIComponent(connectionId)}&path=${encodeURIComponent("Movies/../..")}`);
    assert.equal(traversal.status, 400);

    const capability = await gatewayRequest(port, "/api/nas/media-capability", {
      method: "POST",
      body: { connectionId, path: "Movies/Family Trip (2026).mp4" },
    });
    assert.equal(capability.status, 201);
    const mediaPath = capability.body.mediaUrl.replace("/gateway/", "/api/");

    const media = await gatewayRequest(port, mediaPath, { range: "bytes=4-7" });
    assert.equal(media.status, 206);
    assert.equal(media.headers["content-range"], "bytes 4-7/16");
    assert.equal(media.body.toString("utf8"), "4567");

    const full = await gatewayRequest(port, mediaPath);
    assert.equal(full.status, 200);
    assert.equal(full.headers["content-type"], "video/mp4");
    assert.equal(full.body.length, 16);

    const foreign = await gatewayRequest(port, mediaPath, { sessionToken: OTHER_GATEWAY_SESSION_TOKEN });
    assert.equal(foreign.status, 401);
  } finally {
    await close(server);
    await rm(root, { recursive: true, force: true });
  }
});

test("transcode profile clamps to sane bounds and never upscales", () => {
  const clamped = clampTranscodeProfile({ maxWidth: 99999, maxHeight: -5, videoCodec: "hevc" });
  assert.equal(clamped.maxWidth, 8192);
  assert.equal(clamped.maxHeight, 240);
  assert.equal(clamped.videoCodec, "hevc");
  const defaults = clampTranscodeProfile({});
  assert.equal(defaults.maxWidth, 1920);
  assert.equal(defaults.maxHeight, 1080);
  assert.equal(defaults.videoCodec, "h264");

  const plan = buildTranscodeArgs({
    input: "/tmp/example.mkv",
    profile: { maxWidth: 3840, maxHeight: 2160 },
    encoders: { h264: "h264_videotoolbox", hevc: "hevc_videotoolbox", aac: "aac" },
  });
  assert.equal(plan.videoEncoder, "h264_videotoolbox");
  const scaleArg = plan.args[plan.args.indexOf("-vf") + 1];
  assert.match(scaleArg, /min\(iw\\,3840\)/);
  assert.match(scaleArg, /force_original_aspect_ratio=decrease/);
  assert.ok(plan.args.includes("frag_keyframe+empty_moov+default_base_moof"));

  const softwarePlan = buildTranscodeArgs({
    input: "/tmp/example.mkv",
    profile: { maxWidth: 1280, maxHeight: 720 },
    encoders: { h264: "libx264", aac: "aac" },
  });
  assert.equal(softwarePlan.videoEncoder, "libx264");
  assert.ok(softwarePlan.args.includes("-crf"));
});

test("transcode sessions only accept vault-issued gateway media", async () => {
  const root = await makeNasFixture();
  const server = createGatewayServer({ sessionToken: GATEWAY_SESSION_TOKEN, logger: null });
  const port = await listen(server);
  try {
    const probe = await probeTranscoder();
    const arbitrary = await gatewayRequest(port, "/api/transcode/sessions", {
      method: "POST",
      body: { mediaUrl: "https://example.com/video.mp4", profile: {} },
    });
    if (!probe.available) {
      assert.equal(arbitrary.status, 400);
      return;
    }
    assert.equal(arbitrary.status, 400);
    assert.match(arbitrary.body.error, /NAS and Stremio/);

    const connected = await gatewayRequest(port, "/api/connections", {
      method: "POST",
      body: { kind: "nas-folder", baseUrl: root, credential: "unused" },
    });
    const capability = await gatewayRequest(port, "/api/nas/media-capability", {
      method: "POST",
      body: { connectionId: connected.body.connection.id, path: "clip.mkv" },
    });
    const session = await gatewayRequest(port, "/api/transcode/sessions", {
      method: "POST",
      body: { mediaUrl: capability.body.mediaUrl, profile: { maxWidth: 1280, maxHeight: 720 } },
    });
    assert.equal(session.status, 201);
    assert.match(session.body.transcodeUrl, /^\/gateway\/transcode\/media\?transcodeId=/);

    const stolen = await gatewayRequest(port, "/api/transcode/sessions", {
      method: "POST",
      body: { mediaUrl: capability.body.mediaUrl, profile: {} },
      sessionToken: OTHER_GATEWAY_SESSION_TOKEN,
    });
    assert.equal(stolen.status, 401);
  } finally {
    await close(server);
    await rm(root, { recursive: true, force: true });
  }
});

test("transcode path never lets a redirecting upstream reach another address", async () => {
  const victimHits = [];
  const victim = http.createServer((request, response) => {
    victimHits.push(request.url);
    response.end("private");
  });
  const victimPort = await listen(victim);

  const upstreamCalls = [];
  let upstreamPort;
  const upstream = http.createServer((request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    upstreamCalls.push({ path: url.pathname, userAgent: request.headers["user-agent"] });
    response.setHeader("Content-Type", "application/json");
    if (url.pathname === "/manifest.json") {
      response.end(JSON.stringify({ id: "org.openstream.redirector", name: "Redirector", version: "1.0.0", resources: ["stream"] }));
      return;
    }
    if (url.pathname === "/stream/movie/tt1.json") {
      response.end(JSON.stringify({ streams: [{ name: "Redirecting", url: `http://127.0.0.1:${upstreamPort}/redirect.mp4` }] }));
      return;
    }
    if (url.pathname === "/redirect.mp4") {
      response.statusCode = 302;
      response.setHeader("Location", `http://127.0.0.1:${victimPort}/internal-secret`);
      response.end();
      return;
    }
    response.statusCode = 404;
    response.end(JSON.stringify({ error: "not found" }));
  });
  upstreamPort = await listen(upstream);

  const server = createGatewayServer({ sessionToken: GATEWAY_SESSION_TOKEN, logger: null });
  const port = await listen(server);
  try {
    const probe = await probeTranscoder();
    const connected = await gatewayRequest(port, "/api/connections", {
      method: "POST",
      body: { kind: "stremio", baseUrl: `http://127.0.0.1:${upstreamPort}`, allowPrivateNetwork: true },
    });
    assert.equal(connected.status, 200);
    const streams = await gatewayRequest(port, "/api/stremio/streams", {
      method: "POST",
      body: { connectionId: connected.body.connection.id, type: "movie", id: "tt1" },
    });
    assert.equal(streams.status, 200);
    const session = await gatewayRequest(port, "/api/transcode/sessions", {
      method: "POST",
      body: { mediaUrl: streams.body.streams[0].url, profile: { maxWidth: 1280, maxHeight: 720 } },
    });
    if (!probe.available) {
      assert.equal(session.status, 400);
      return;
    }
    assert.equal(session.status, 201);

    const media = await gatewayRequest(port, session.body.transcodeUrl.replace("/gateway/", "/api/"));
    assert.equal(media.status, 200);
    const redirectCall = upstreamCalls.find((call) => call.path === "/redirect.mp4");
    assert.ok(redirectCall, "the stream target must be fetched through the gateway relay");
    assert.match(redirectCall.userAgent ?? "", /OpenStream-Gateway/, "ffmpeg must never dial the remote itself");
    assert.deepEqual(victimHits, [], "a redirecting upstream must never reach another address via the transcode path");
  } finally {
    await close(server);
    await close(upstream);
    await close(victim);
  }
});

test("stremio media relay preserves legitimate upstream statuses like 416", async () => {
  let upstreamPort;
  const upstream = http.createServer((request, response) => {
    const url = new URL(request.url, "http://127.0.0.1");
    if (url.pathname === "/manifest.json") {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ id: "org.openstream.ranges", name: "Ranges", version: "1.0.0", resources: ["stream"] }));
      return;
    }
    if (url.pathname === "/stream/movie/tt2.json") {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ streams: [{ name: "Clip", url: `http://127.0.0.1:${upstreamPort}/clip.mp4` }] }));
      return;
    }
    if (url.pathname === "/clip.mp4") {
      response.statusCode = 416;
      response.setHeader("Content-Range", "bytes */16");
      response.end();
      return;
    }
    response.statusCode = 404;
    response.end();
  });
  upstreamPort = await listen(upstream);

  const server = createGatewayServer({ sessionToken: GATEWAY_SESSION_TOKEN, logger: null });
  const port = await listen(server);
  try {
    const connected = await gatewayRequest(port, "/api/connections", {
      method: "POST",
      body: { kind: "stremio", baseUrl: `http://127.0.0.1:${upstreamPort}`, allowPrivateNetwork: true },
    });
    assert.equal(connected.status, 200);
    const streams = await gatewayRequest(port, "/api/stremio/streams", {
      method: "POST",
      body: { connectionId: connected.body.connection.id, type: "movie", id: "tt2" },
    });
    assert.equal(streams.status, 200);
    const media = await gatewayRequest(port, streams.body.streams[0].url.replace("/gateway/", "/api/"), { range: "bytes=99-" });
    assert.equal(media.status, 416);
    assert.equal(media.headers["content-range"], "bytes */16");
  } finally {
    await close(server);
    await close(upstream);
  }
});

test("gateway logger writes redacted JSONL entries and accepts client logs", async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), "openstream-logs-"));
  const logger = createLogger({ directory, mirrorToConsole: false });
  await logger.info("test", "connecting with ?apikey=super-secret-key done", { url: "https://user:pass@nas.local/x" });

  const server = createGatewayServer({ sessionToken: GATEWAY_SESSION_TOKEN, logger });
  const port = await listen(server);
  try {
    const accepted = await gatewayRequest(port, "/api/logs", {
      method: "POST",
      body: { entries: [{ level: "error", message: "client exploded", context: { screen: "player" } }] },
    });
    assert.equal(accepted.status, 202);
    assert.equal(accepted.body.accepted, 1);
  } finally {
    await close(server);
  }

  await new Promise((resolve) => setTimeout(resolve, 50));
  const files = await readdir(directory);
  assert.equal(files.length, 1);
  const lines = (await readFile(path.join(directory, files[0]), "utf8")).trim().split("\n").map((line) => JSON.parse(line));
  assert.ok(lines.length >= 2);
  assert.match(lines[0].message, /apikey=\[redacted\]/);
  assert.match(lines[0].context.url, /\[redacted\]@\[host\]/);
  const clientLine = lines.find((line) => line.source === "client");
  assert.equal(clientLine.level, "error");
  assert.equal(clientLine.message, "client exploded");
  await rm(directory, { recursive: true, force: true });
});
