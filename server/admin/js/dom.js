// DOM helpers. Everything is built with createElement / textContent: no innerHTML anywhere, so player-supplied
// strings (names, notes, reasons, event messages) can never become markup.

const SVG_NS = "http://www.w3.org/2000/svg";

function addKids(el, kids) {
  for (const k of kids) {
    if (k === null || k === undefined || k === false || k === true) continue;
    if (Array.isArray(k)) addKids(el, k);
    else if (k instanceof Node) el.appendChild(k);
    else el.appendChild(document.createTextNode(String(k)));
  }
}

const PROPS = new Set(["value", "checked", "disabled", "hidden", "selected", "indeterminate", "readOnly", "required"]);

function applyProps(el, props, isSvg) {
  if (!props) return;
  for (const [key, v] of Object.entries(props)) {
    if (v === null || v === undefined || v === false) continue;
    if (key === "class" || key === "className") {
      if (isSvg) el.setAttribute("class", v);
      else el.className = v;
    } else if (key === "text") {
      el.textContent = String(v);
    } else if (key === "style" && typeof v === "object") {
      for (const [sk, sv] of Object.entries(v)) {
        if (sv === null || sv === undefined) continue;
        if (sk.startsWith("--")) el.style.setProperty(sk, sv);
        else el.style[sk] = sv;
      }
    } else if (key === "dataset") {
      for (const [dk, dv] of Object.entries(v)) el.dataset[dk] = dv;
    } else if (key.startsWith("on") && typeof v === "function") {
      el.addEventListener(key.slice(2).toLowerCase(), v);
    } else if (!isSvg && PROPS.has(key)) {
      el[key] = v;
    } else {
      el.setAttribute(key, v === true ? "" : String(v));
    }
  }
}

/** h("div", {class: "x", onClick}, "text", child, [more]) */
export function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  applyProps(el, props, false);
  addKids(el, kids);
  return el;
}

/** SVG element with attributes. */
export function s(tag, attrs, ...kids) {
  const el = document.createElementNS(SVG_NS, tag);
  applyProps(el, attrs, true);
  addKids(el, kids);
  return el;
}

export function clear(el) {
  while (el.firstChild) el.removeChild(el.firstChild);
  return el;
}

export function replace(el, ...kids) {
  clear(el);
  addKids(el, kids);
  return el;
}

// ---------- formatting ----------

const NF = new Intl.NumberFormat("en-US");
export const fmtInt = (n) => (n === null || n === undefined || Number.isNaN(Number(n)) ? "–" : NF.format(Number(n)));

export function compact(n) {
  n = Number(n) || 0;
  if (Math.abs(n) < 10000) return NF.format(n);
  if (Math.abs(n) < 1e6) return (n / 1000).toFixed(n < 1e5 ? 1 : 0).replace(/\.0$/, "") + "K";
  return (n / 1e6).toFixed(1).replace(/\.0$/, "") + "M";
}

export function pct(a, b) {
  if (!b) return "–";
  return Math.round((a / b) * 100) + "%";
}

const DTF = new Intl.DateTimeFormat(undefined, {
  year: "numeric", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", second: "2-digit",
});
const DTF_SHORT = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });

export const absTime = (ts) => (ts ? DTF.format(new Date(Number(ts))) : "–");
export const shortTime = (ts) => (ts ? DTF_SHORT.format(new Date(Number(ts))) : "–");

export function relTime(ts, now = Date.now()) {
  if (!ts) return "never";
  const d = now - Number(ts);
  const a = Math.abs(d);
  const fut = d < 0;
  let out;
  if (a < 45e3) return fut ? "in a few s" : "just now";
  if (a < 3600e3) out = Math.round(a / 60e3) + "m";
  else if (a < 86400e3) out = Math.round(a / 3600e3) + "h";
  else if (a < 30 * 86400e3) out = Math.round(a / 86400e3) + "d";
  else return shortTime(ts);
  return fut ? "in " + out : out + " ago";
}

/** <time> showing a relative time, with the absolute time as tooltip; kept fresh by tickTimes(). */
export function timeEl(ts, opts = {}) {
  if (!ts) return h("span", { class: "muted" }, opts.empty ?? "–");
  const t = h("time", {
    datetime: new Date(Number(ts)).toISOString(),
    title: absTime(ts),
    class: "rel",
    dataset: { ts: String(ts) },
  }, relTime(ts));
  return t;
}

export function tickTimes(root = document) {
  const now = Date.now();
  for (const t of root.querySelectorAll("time.rel[data-ts]")) {
    const txt = relTime(Number(t.dataset.ts), now);
    if (t.textContent !== txt) t.textContent = txt;
  }
}

export function duration(ms) {
  if (ms === null || ms === undefined || ms < 0) return "–";
  const s = Math.round(ms / 1000);
  if (s < 60) return s + "s";
  const m = Math.floor(s / 60);
  if (m < 60) return m + "m " + String(s % 60).padStart(2, "0") + "s";
  return Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0") + "m";
}

export const shortId = (id, n = 8) => (!id ? "–" : id.length > n + 1 ? id.slice(0, n) + "…" : id);

/** JSON column that may arrive as a string (raw D1 row) or already parsed. */
export function parseJson(v, fallback) {
  if (v === null || v === undefined || v === "") return fallback;
  if (typeof v !== "string") return v;
  try { return JSON.parse(v); } catch { return fallback; }
}

export function debounce(fn, ms) {
  let t = 0;
  return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
}

// ---------- polling (pauses while the tab is hidden) ----------

export function poll(fn, ms, { immediate = false } = {}) {
  let timer = 0;
  let stopped = false;
  let busy = false;
  const run = async () => {
    if (stopped || busy) return;
    if (document.hidden) return;
    busy = true;
    try { await fn(); } catch { /* the callee reports */ } finally { busy = false; }
  };
  const start = () => { clearInterval(timer); timer = setInterval(run, ms); };
  const onVis = () => {
    if (stopped) return;
    if (document.hidden) clearInterval(timer);
    else { run(); start(); }
  };
  document.addEventListener("visibilitychange", onVis);
  start();
  if (immediate) run();
  return {
    stop() { stopped = true; clearInterval(timer); document.removeEventListener("visibilitychange", onVis); },
    now: run,
  };
}

// ---------- copy ----------

export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    const ta = h("textarea", { class: "sr-only", readOnly: true, value: text });
    document.body.appendChild(ta);
    ta.select();
    let ok = false;
    try { ok = document.execCommand("copy"); } catch { /* ignore */ }
    ta.remove();
    return ok;
  }
}
