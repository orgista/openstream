import assert from "node:assert/strict";
import test from "node:test";
import {
  assertAllowedOrigin,
  assertGatewayBindHost,
  assertLoopbackBindHost,
  isPrivateAddress,
  normalizeTarget,
  parseCanonicalRequestTarget,
  redact,
  validateResolvedAddresses,
} from "./security.mjs";

test("recognizes private and reserved network addresses", () => {
  for (const address of [
    "127.0.0.1",
    "10.0.0.2",
    "172.20.1.2",
    "192.168.1.2",
    "169.254.1.2",
    "::1",
    "fd00::1",
    "2001:db8::1",
    "::ffff:127.0.0.1",
    "::ffff:7f00:1",
    "0:0:0:0:0:ffff:c0a8:102",
    "[::FFFF:10.0.0.2]",
  ]) {
    assert.equal(isPrivateAddress(address), true, address);
  }
  assert.equal(isPrivateAddress("8.8.8.8"), false);
  assert.equal(isPrivateAddress("2606:4700:4700::1111"), false);
  assert.equal(isPrivateAddress("::ffff:8.8.8.8"), false);
  assert.equal(isPrivateAddress("::ffff:808:808"), false);
  assert.equal(isPrivateAddress("0:0:0:0:0:ffff:808:808"), false);
});

test("requires explicit private-network access and HTTPS for public services", () => {
  assert.throws(() => normalizeTarget("http://192.168.1.20:8989"), /Private-network/);
  assert.throws(() => normalizeTarget("https://[::ffff:7f00:1]:8989"), /Private-network/);
  assert.throws(() => normalizeTarget("https://[0:0:0:0:0:ffff:c0a8:102]:8989"), /Private-network/);
  assert.equal(normalizeTarget("http://192.168.1.20:8989", { allowPrivateNetwork: true }).host, "192.168.1.20:8989");
  assert.doesNotThrow(() => normalizeTarget("https://[::ffff:808:808]"));
  assert.throws(() => normalizeTarget("http://example.com"), /Plain HTTP/);
  assert.equal(normalizeTarget("https://example.com").protocol, "https:");
});

test("rejects embedded credentials and redacts URL secrets", () => {
  assert.throws(() => normalizeTarget("https://user:secret@example.com"), /Credentials/);
  assert.equal(redact("https://example.com/api?apikey=secret"), "https://example.com/api?apikey=[redacted]");
});

test("allows only configured browser origins", () => {
  const origins = new Set(["http://127.0.0.1:5173"]);
  assert.doesNotThrow(() => assertAllowedOrigin("http://127.0.0.1:5173", origins));
  assert.throws(() => assertAllowedOrigin("https://evil.example", origins), /not allowed/);
});

test("permits only loopback gateway bind addresses", () => {
  for (const host of ["localhost", "127.0.0.1", "::1", "[::1]"]) {
    assert.doesNotThrow(() => assertLoopbackBindHost(host));
  }
  for (const host of ["0.0.0.0", "192.168.1.10", "example.com"]) {
    assert.throws(() => assertLoopbackBindHost(host), /loopback/);
  }
});

test("LAN gateway bind requires an explicit private address mode", () => {
  assert.equal(assertGatewayBindHost("0.0.0.0", { allowLan: true }), "0.0.0.0");
  assert.equal(assertGatewayBindHost("192.168.1.20", { allowLan: true }), "192.168.1.20");
  assert.throws(() => assertGatewayBindHost("0.0.0.0"), /loopback/);
  assert.throws(() => assertGatewayBindHost("example.com", { allowLan: true }), /private LAN/);
});

test("requires every resolved address to be private before allowing cleartext HTTP", () => {
  const privateOnly = [{ address: "192.168.1.10", family: 4 }];
  const mixed = [...privateOnly, { address: "93.184.216.34", family: 4 }];
  assert.doesNotThrow(() => validateResolvedAddresses(new URL("http://media.local"), privateOnly, { allowPrivateNetwork: true }));
  assert.throws(
    () => validateResolvedAddresses(new URL("http://media.local"), mixed, { allowPrivateNetwork: true }),
    /Plain HTTP/,
  );
});

test("binds approved service policies to one origin and private address set", () => {
  const policy = {
    allowPrivateNetwork: true,
    approvedOrigin: "http://192.168.1.20:8989",
    approvedAddresses: [{ address: "192.168.1.20", family: 4 }],
  };
  assert.doesNotThrow(() => normalizeTarget("http://192.168.1.20:8989/api", policy));
  assert.throws(() => normalizeTarget("http://192.168.1.20:8990/api", policy), /outside.*authorization/i);
  assert.doesNotThrow(() => validateResolvedAddresses(
    new URL("http://192.168.1.20:8989"),
    [{ address: "192.168.1.20", family: 4 }],
    policy,
  ));
  assert.throws(() => validateResolvedAddresses(
    new URL("http://192.168.1.20:8989"),
    [{ address: "192.168.1.21", family: 4 }],
    policy,
  ), /address set changed/i);
});

test("accepts only canonical fixed-route request targets", () => {
  const options = { origin: "http://127.0.0.1:8787", prefix: "/api" };
  assert.equal(parseCanonicalRequestTarget("/api/connections?kind=stremio", options).pathname, "/api/connections");
  assert.equal(parseCanonicalRequestTarget("/unrelated", options), null);
  for (const target of [
    "/api/../api/connections",
    "/api/%2e%2e/api/connections",
    "/api//connections",
    "/api\\connections",
    "http://127.0.0.1:8787/api/connections",
  ]) {
    assert.throws(() => parseCanonicalRequestTarget(target, options), /canonical|origin-form/i, target);
  }
});
