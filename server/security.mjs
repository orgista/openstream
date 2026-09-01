import { lookup } from "node:dns/promises";
import { isIP } from "node:net";
import { readFileSync } from "node:fs";
import http from "node:http";
import https from "node:https";

const MAX_RESPONSE_BYTES = 2 * 1024 * 1024;
const PRIVATE_HOSTS = new Set(["localhost", "localhost.localdomain"]);
const LOOPBACK_BIND_HOSTS = new Set(["localhost", "127.0.0.1", "::1"]);

const GATEWAY_VERSION = (() => {
  try {
    return JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8")).version || "0.1";
  } catch {
    return "0.1";
  }
})();
// One outbound User-Agent for every gateway-originated request; version from package.json.
const GATEWAY_USER_AGENT = `OpenStream-Gateway/${GATEWAY_VERSION}`;

function addressIdentity({ address, family }) {
  return `${Number(family)}:${String(address).toLowerCase().replace(/^\[|\]$/g, "")}`;
}

function normalizedAddressIdentities(addresses) {
  return [...new Set(addresses.map(addressIdentity))].sort();
}

function parseIpv4(value) {
  const parts = value.split(".").map(Number);
  return parts.length === 4 && parts.every((part) => Number.isInteger(part) && part >= 0 && part <= 255)
    ? parts
    : undefined;
}

function parseIpv6Words(value) {
  let address = value;
  if (address.includes(".")) {
    const separator = address.lastIndexOf(":");
    if (separator < 0) return undefined;
    const ipv4 = parseIpv4(address.slice(separator + 1));
    if (!ipv4) return undefined;
    const [a, b, c, d] = ipv4;
    address = `${address.slice(0, separator)}:${((a << 8) | b).toString(16)}:${((c << 8) | d).toString(16)}`;
  }

  const halves = address.split("::");
  if (halves.length > 2) return undefined;
  const parseHalf = (half) => {
    if (!half) return [];
    const parts = half.split(":");
    if (parts.some((part) => !/^[0-9a-f]{1,4}$/.test(part))) return undefined;
    return parts.map((part) => Number.parseInt(part, 16));
  };
  const leading = parseHalf(halves[0]);
  const trailing = parseHalf(halves[1] ?? "");
  if (!leading || !trailing) return undefined;

  if (halves.length === 1) return leading.length === 8 ? leading : undefined;
  const omitted = 8 - leading.length - trailing.length;
  if (omitted < 1) return undefined;
  return [...leading, ...Array(omitted).fill(0), ...trailing];
}

function isPrivateIpv4([a, b, c]) {
  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 0 && c === 0) ||
    (a === 192 && b === 0 && c === 2) ||
    (a === 192 && b === 168) ||
    (a === 198 && (b === 18 || b === 19)) ||
    (a === 198 && b === 51 && c === 100) ||
    (a === 203 && b === 0 && c === 113) ||
    a >= 224
  );
}

export function isPrivateAddress(value) {
  const address = value.toLowerCase().replace(/^\[|\]$/g, "");
  const ipv4 = parseIpv4(address);
  if (ipv4) return isPrivateIpv4(ipv4);

  const ipv6 = parseIpv6Words(address);
  if (!ipv6) return false;
  const mappedIpv4 = ipv6.slice(0, 5).every((word) => word === 0) && ipv6[5] === 0xffff
    ? [ipv6[6] >> 8, ipv6[6] & 0xff, ipv6[7] >> 8, ipv6[7] & 0xff]
    : undefined;
  if (mappedIpv4) return isPrivateIpv4(mappedIpv4);

  const unspecified = ipv6.every((word) => word === 0);
  const loopback = ipv6.slice(0, 7).every((word) => word === 0) && ipv6[7] === 1;
  const first = ipv6[0];
  return unspecified || loopback || (first & 0xfe00) === 0xfc00 || (first & 0xffc0) === 0xfe80
    || (first === 0x2001 && ipv6[1] === 0x0db8);
}

export function assertLoopbackBindHost(value) {
  return assertGatewayBindHost(value, { allowLan: false });
}

export function assertGatewayBindHost(value, { allowLan = false } = {}) {
  const host = String(value).trim().toLowerCase().replace(/^\[|\]$/g, "");
  if (LOOPBACK_BIND_HOSTS.has(host)) {
    return host;
  }
  if (allowLan && isPrivateAddress(host)) {
    return host;
  }
  throw new Error(
    allowLan
      ? "The secure gateway may bind only to a loopback or private LAN address."
      : "The secure gateway may bind only to a loopback address.",
  );
}

export function parseCanonicalRequestTarget(value, { origin, prefix }) {
  if (typeof value !== "string" || typeof origin !== "string" || typeof prefix !== "string") {
    throw new Error("Request target validation is not configured correctly.");
  }
  if (!value.startsWith("/") || value.startsWith("//") || /[\u0000-\u001f\u007f]/.test(value) || value.includes("#")) {
    throw new Error("Request target must use an origin-form path.");
  }

  const queryIndex = value.indexOf("?");
  const rawPath = queryIndex === -1 ? value : value.slice(0, queryIndex);
  const parsed = new URL(value, origin);
  const rawInNamespace = rawPath === prefix || rawPath.startsWith(`${prefix}/`);
  const normalizedInNamespace = parsed.pathname === prefix || parsed.pathname.startsWith(`${prefix}/`);
  const prefixLookalike = rawPath.startsWith(prefix);
  if (!rawInNamespace && !normalizedInNamespace && !prefixLookalike) return null;

  const segments = rawPath.split("/");
  const hasAmbiguousSyntax = (
    !rawInNamespace ||
    rawPath.includes("\\") ||
    rawPath.includes("//") ||
    rawPath.includes("%") ||
    segments.some((segment) => segment === "." || segment === "..") ||
    parsed.pathname !== rawPath
  );
  if (hasAmbiguousSyntax) {
    throw new Error(`Request target must use the canonical ${prefix} route form.`);
  }
  return parsed;
}

export function redact(value) {
  return String(value)
    .replace(/([?&](?:apikey|api_key|token|access_token|key)=)[^&\s]+/gi, "$1[redacted]")
    .replace(/(authorization:\s*(?:bearer|basic)\s+)[^\s]+/gi, "$1[redacted]")
    .replace(/\/[^/:\s]+:[^@/\s]+@/g, "/[redacted]@[host]/");
}

export function normalizeTarget(value, policy = {}) {
  if (typeof value !== "string" || value.trim() === "") throw new Error("A service URL is required.");
  const url = new URL(value.trim());
  if (url.username || url.password) throw new Error("Credentials are not allowed in service URLs.");
  if (url.protocol !== "https:" && url.protocol !== "http:") throw new Error("Only HTTP and HTTPS services are supported.");

  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (policy.approvedOrigin && url.origin !== policy.approvedOrigin) {
    throw new Error("The service origin is outside this connection's authorization.");
  }
  const literalPrivate = PRIVATE_HOSTS.has(host) || (isIP(host) > 0 && isPrivateAddress(host));
  if (literalPrivate && !policy.allowPrivateNetwork) throw new Error("Private-network access was not enabled for this connection.");
  if (url.protocol === "http:" && !policy.allowPrivateNetwork) {
    throw new Error("Plain HTTP is allowed only for an explicitly enabled private-network service.");
  }

  url.hash = "";
  return url;
}

export async function resolveAndValidate(url, policy = {}) {
  const hostname = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  let addresses;
  if (isIP(hostname)) {
    addresses = [{ address: hostname, family: isIP(hostname) }];
  } else if (PRIVATE_HOSTS.has(hostname)) {
    addresses = [{ address: "127.0.0.1", family: 4 }];
  } else {
    addresses = await lookup(hostname, { all: true, verbatim: true });
  }
  if (addresses.length === 0) throw new Error("The service hostname did not resolve.");

  return validateResolvedAddresses(url, addresses, policy);
}

export function validateResolvedAddresses(url, addresses, policy = {}) {
  const hasPrivateAddress = addresses.some(({ address }) => isPrivateAddress(address));
  const allPrivateAddresses = addresses.every(({ address }) => isPrivateAddress(address));
  if (hasPrivateAddress && !policy.allowPrivateNetwork) {
    throw new Error("The service resolves to a private or reserved network address.");
  }
  if (url.protocol === "http:" && !(allPrivateAddresses && policy.allowPrivateNetwork)) {
    throw new Error("Plain HTTP is allowed only for an explicitly enabled private-network service.");
  }
  if (Array.isArray(policy.approvedAddresses)) {
    const approved = normalizedAddressIdentities(policy.approvedAddresses);
    const resolved = normalizedAddressIdentities(addresses);
    if (approved.length !== resolved.length || approved.some((value, index) => value !== resolved[index])) {
      throw new Error("The service address set changed and requires renewed authorization.");
    }
  }
  return addresses;
}

export async function authorizeTarget(value, policy = {}) {
  const url = normalizeTarget(value, policy);
  const addresses = await resolveAndValidate(url, policy);
  const pinsPrivateAddresses = addresses.some(({ address }) => isPrivateAddress(address));
  return {
    url,
    policy: {
      allowPrivateNetwork: policy.allowPrivateNetwork === true,
      approvedOrigin: url.origin,
      ...(pinsPrivateAddresses ? { approvedAddresses: addresses.map(({ address, family }) => ({ address, family })) } : {}),
    },
  };
}

function lookupFrom(addresses) {
  return (_hostname, options, callback) => {
    if (options?.all) {
      callback(null, addresses.map(({ address, family }) => ({ address, family })));
      return;
    }
    const selected = addresses[0];
    callback(null, selected.address, selected.family);
  };
}

export async function safeStreamRequest(urlValue, init = {}, policy = {}) {
  const url = normalizeTarget(urlValue, policy);
  const addresses = await resolveAndValidate(url, policy);
  const transport = url.protocol === "https:" ? https : http;
  const headers = {
    Accept: "*/*",
    "User-Agent": GATEWAY_USER_AGENT,
    ...init.headers,
  };

  return new Promise((resolve, reject) => {
    const request = transport.request(url, {
      method: init.method ?? "GET",
      headers,
      lookup: lookupFrom(addresses),
      servername: url.hostname,
      timeout: init.timeoutMs ?? 15_000,
    }, (response) => {
      clearTimeout(deadline);
      const status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        response.resume();
        reject(new Error("Service redirects are not followed by the secure gateway."));
        return;
      }
      resolve(response);
    });
    const deadline = setTimeout(
      () => request.destroy(new Error("Service response headers exceeded the gateway deadline.")),
      init.deadlineMs ?? 30_000,
    );
    request.on("timeout", () => request.destroy(new Error("Service request timed out.")));
    request.on("error", (error) => {
      clearTimeout(deadline);
      reject(new Error(redact(error.message)));
    });
    request.end();
  });
}

export async function safeRequest(urlValue, init = {}, policy = {}) {
  const url = normalizeTarget(urlValue, policy);
  const addresses = await resolveAndValidate(url, policy);
  const transport = url.protocol === "https:" ? https : http;
  const body = init.body == null ? undefined : Buffer.from(String(init.body));
  const headers = {
    Accept: "application/json",
    "User-Agent": GATEWAY_USER_AGENT,
    ...init.headers,
  };
  if (body && !headers["Content-Length"]) headers["Content-Length"] = String(body.length);

  return new Promise((resolve, reject) => {
    const request = transport.request(url, {
      method: init.method ?? "GET",
      headers,
      lookup: lookupFrom(addresses),
      servername: url.hostname,
      timeout: init.timeoutMs ?? 10_000,
    }, (response) => {
      const status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        response.resume();
        reject(new Error("Service redirects are not followed by the secure gateway."));
        return;
      }

      const chunks = [];
      let bytes = 0;
      response.on("data", (chunk) => {
        bytes += chunk.length;
        if (bytes > (init.maxBytes ?? MAX_RESPONSE_BYTES)) {
          request.destroy(new Error("Service response exceeded the gateway size limit."));
          return;
        }
        chunks.push(chunk);
      });
      response.on("end", () => {
        clearTimeout(deadline);
        const text = Buffer.concat(chunks).toString("utf8");
        if (status < 200 || status >= 300) {
          reject(new Error(`Service request failed with status ${status}.`));
          return;
        }
        resolve({ status, headers: response.headers, text });
      });
    });

    const deadline = setTimeout(
      () => request.destroy(new Error("Service request exceeded the gateway deadline.")),
      init.deadlineMs ?? 30_000,
    );
    request.on("timeout", () => request.destroy(new Error("Service request timed out.")));
    request.on("error", (error) => {
      clearTimeout(deadline);
      reject(new Error(redact(error.message)));
    });
    if (body) request.write(body);
    request.end();
  });
}

export async function safeRequestJson(url, init = {}, policy = {}) {
  const response = await safeRequest(url, init, policy);
  try {
    return JSON.parse(response.text || "null");
  } catch {
    throw new Error("Service returned invalid JSON.");
  }
}

export function assertAllowedOrigin(origin, allowedOrigins) {
  if (!origin || !allowedOrigins.has(origin)) throw new Error("Request origin is not allowed.");
}
