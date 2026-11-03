// Admin API client (contract: server/ADMIN_API.md). Session cookie (same-origin), X-Admin: 1 on every write.

export const BASE = "/admin/api";

export class ApiError extends Error {
  constructor(status, code, msg) {
    super(msg || code || "HTTP " + status);
    this.status = status;
    this.code = code;
    this.msg = msg || "";
  }
}

const listeners = { unauth: new Set(), disabled: new Set() };
export const onApi = (ev, fn) => listeners[ev].add(fn);
const emit = (ev, data) => listeners[ev].forEach((fn) => fn(data));

// Bumped on every sign-in: a 401 from a request that started under an older session is not an "expired" signal.
let epoch = 0;
export const newSession = () => { epoch++; };

function qs(params) {
  if (!params) return "";
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) {
    if (v === null || v === undefined || v === "" || v === false) continue;
    u.set(k, v === true ? "1" : String(v));
  }
  const str = u.toString();
  return str ? "?" + str : "";
}

export async function request(method, path, { params, body, quietAuth = false } = {}) {
  const ep = epoch;
  const headers = { Accept: "application/json" };
  if (method !== "GET") headers["X-Admin"] = "1";
  if (body !== undefined) headers["Content-Type"] = "application/json";
  let res;
  try {
    res = await fetch(BASE + path + qs(params), {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: "same-origin",
      cache: "no-store",
    });
  } catch {
    throw new ApiError(0, "network", "Network error: the server did not answer.");
  }
  if (res.status === 204) return null;
  let data = null;
  const text = await res.text();
  if (text) {
    try { data = JSON.parse(text); } catch { data = null; }
  }
  if (!res.ok) {
    const err = new ApiError(res.status, data?.error || "http_" + res.status, data?.msg);
    if (res.status === 401 && !quietAuth && ep === epoch) emit("unauth", err);
    if (res.status === 503 && err.code === "admin_disabled") emit("disabled", err);
    throw err;
  }
  return data;
}

export const api = {
  get: (path, params, opts) => request("GET", path, { params, ...opts }),
  post: (path, body = {}) => request("POST", path, { body }),
  put: (path, body) => request("PUT", path, { body }),
  patch: (path, body) => request("PATCH", path, { body }),
};

export const enc = encodeURIComponent;
