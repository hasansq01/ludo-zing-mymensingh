// Crashes: unexpected-exit reports sent by the game (ADMIN_API.md "Crashes"): counts by model / reason / version /
// GPU, a filterable list, and one report's detail (device, exit info, match, breadcrumbs, samples, the log tail).
import { h, replace, timeEl, fmtInt, absTime } from "../dom.js";
import { api, enc } from "../api.js";
import { dataTable } from "../table.js";
import { badge, card, kv, emptyState, errorState, skeletonBlock, accountLink, copyBtn } from "../ui.js";
import { pageHead, textFilter, filterBar, chipGroup } from "./common.js";
import { simpleTable } from "./account_cells.js";

const RANGES = [["7", "7 days"], ["30", "30 days"], ["90", "90 days"]];
const BAD = new Set(["crash", "crash_native", "anr", "low_memory", "initialization_failure", "excessive_resource_usage", "signaled"]);
const dash = (v) => (v === null || v === undefined || v === "" ? h("span", { class: "muted" }, "–") : String(v));
const mono = (v) => (v === null || v === undefined || v === "" ? h("span", { class: "muted" }, "–") : h("span", { class: "mono" }, String(v)));
const reasonBadge = (r) => badge(r || "unknown", BAD.has(r) ? "danger" : r === "unclean" ? "warn" : "neutral");
const num1 = (v) => (typeof v === "number" ? String(Math.round(v * 10) / 10) : "–");

export default function crashesPage(root, _params, ctx) {
  ctx.title("Crashes");
  const state = { version: ctx.query.get("version") || "", model: ctx.query.get("model") || "", reason: ctx.query.get("reason") || "", days: ctx.query.get("days") || "30" };
  if (!RANGES.some(([v]) => v === state.days)) state.days = "30";
  const summaryBox = h("div", null, h("div", { class: "grid-2" }, card("By model", skeletonBlock(4)), card("By reason", skeletonBlock(4))));
  const dl = { model: h("datalist", { id: "crash-models" }), version: h("datalist", { id: "crash-versions" }), reason: h("datalist", { id: "crash-reasons" }) };

  const sync = () => {
    ctx.setQuery({ version: state.version, model: state.model, reason: state.reason, days: state.days === "30" ? "" : state.days });
    table.setParams({ version: state.version || undefined, model: state.model || undefined, reason: state.reason || undefined });
  };
  const table = dataTable({
    caption: "Crash reports",
    dense: true,
    // the API pages by `before` (received_at) and answers {rows, next}
    load: async ({ limit, cursor, ...q }) => {
      const r = await api.get("/crashes", { ...q, limit, before: cursor });
      return { items: r.rows, next: r.next === null || r.next === undefined ? null : String(r.next) };
    },
    rowHref: (r) => "#/crashes/" + enc(r.id),
    empty: ["No crash reports", "Reports appear here when a game run ends unexpectedly (kept 90 days)."],
    columns: [
      { label: "Time", render: (r) => timeEl(r.received_at) },
      { label: "Reason", render: (r) => reasonBadge(r.reason) },
      { label: "Version", render: (r) => mono(r.app_version) },
      { label: "Device", cls: "col-main", render: (r) => dash(r.model) },
      { label: "Android", render: (r) => dash(r.android) },
      { label: "Screen", render: (r) => dash(r.screen) },
      { label: "Game", render: (r) => dash(r.game ? r.game + (r.mode ? " · " + r.mode : "") : "") },
      { label: "Peak MB", align: "right", render: (r) => (r.mem_peak_mb === null || r.mem_peak_mb === undefined ? "–" : fmtInt(Math.round(r.mem_peak_mb))) },
    ],
  });

  const pick = (key, label, placeholder, listId) => {
    const el = textFilter({ value: state[key], placeholder, label, mono: true, list: listId, onInput: (v) => { state[key] = v; sync(); } });
    el.classList.add("w-kind");
    return el;
  };
  const range = chipGroup({ value: state.days, options: RANGES, label: "Summary period", onChange: (v) => { state.days = v; loadSummary(); sync(); } });
  root.append(
    pageHead(null, "Reports from game runs that ended unexpectedly, newest first. Click a row for the full report.", [range]),
    summaryBox,
    filterBar(pick("version", "Filter by version", "Version, e.g. 0.2.0", "crash-versions"), pick("model", "Filter by device model", "Device model", "crash-models"),
      pick("reason", "Filter by exit reason", "Reason, e.g. low_memory", "crash-reasons"), dl.version, dl.model, dl.reason),
    h("section", { class: "card card-flush" }, table.el));

  // a count table; clicking a name filters the list by it
  function counts(title, key, rows, filterKey) {
    const total = rows.reduce((a, r) => a + r.n, 0) || 1;
    if (!rows.length) return card(title, emptyState("Nothing yet", "", "chart"));
    return card(title, simpleTable([
      { label: title.replace("By ", ""), render: (r) => {
        if (!filterKey) return h("span", null, r[key] || "(unknown)");
        const b = h("button", { type: "button", class: "btn btn-sm", title: "Filter the list" }, r[key] || "(unknown)");
        b.addEventListener("click", () => { state[filterKey] = r[key]; sync(); for (const inp of root.querySelectorAll("input[list]")) if (inp.getAttribute("list") === "crash-" + filterKey + "s") inp.value = r[key]; });
        return b;
      } },
      { label: "Reports", align: "right", render: (r) => fmtInt(r.n) },
      { label: "Share", align: "right", render: (r) => Math.round((r.n / total) * 100) + "%" },
    ], rows, { caption: title }), { cls: "card-flush" });
  }

  async function loadSummary() {
    try {
      const s = await api.get("/crashes/summary", { days: state.days });
      const fill = (el, key, rows) => { replace(el); for (const r of rows) if (r[key]) el.appendChild(h("option", { value: r[key] })); };
      fill(dl.model, "model", s.by_model); fill(dl.version, "version", s.by_version); fill(dl.reason, "reason", s.by_reason);
      replace(summaryBox,
        h("p", { class: "card-sub" }, `${fmtInt(s.total)} reports in the last ${s.days} days.`),
        h("div", { class: "grid-2" },
          counts("By model", "model", s.by_model, "model"),
          counts("By reason", "reason", s.by_reason, "reason"),
          counts("By version", "version", s.by_version, "version"),
          counts("By GPU", "gpu", s.by_gpu || [], null)));
    } catch (err) {
      if (err.status === 401) return;
      replace(summaryBox, errorState(err, loadSummary));
    }
  }
  loadSummary();
  sync();
}

// ---------- one report ----------

export function crashDetailPage(root, [id], ctx) {
  ctx.title("Crash report", [["Crashes", "#/crashes"]]);
  const body = h("div", { class: "detail" }, skeletonBlock(3), skeletonBlock(6));
  root.appendChild(body);
  api.get("/crashes/" + enc(id)).then(
    (r) => replace(body, ...detail(r)),
    (err) => {
      if (err.status === 401) return;
      replace(body, err.status === 404 ? emptyState("No crash report with this id", id, "alert") : errorState(err, () => crashDetailPage(replace(root), [id], ctx)));
    });

  function detail(r) {
    const p = r.payload || {};
    const dev = p.device || {};
    const app = p.app || {};
    const ex = p.exit || null;
    const m = p.match || null;
    const samples = Array.isArray(p.samples) ? p.samples : [];
    const crumbs = Array.isArray(p.crumbs) ? p.crumbs : [];
    ctx.title((r.model || "Device") + " · " + (r.reason || "crash"), [["Crashes", "#/crashes"]]);
    const out = [];
    out.push(card("Report", kv([
      ["Received", h("span", null, absTime(r.received_at), " ", timeEl(r.received_at))],
      ["Id", h("span", { class: "pid" }, mono(r.id), copyBtn(r.id, "Copy id"))],
      ["Reason", reasonBadge(r.reason)],
      ["Trigger", mono(p.trigger)],
      ["Device id", mono(r.pid)],
      ["Session", mono(r.sid)],
      ["Account", r.account_id ? accountLink(r.account_id, r.account_id) : h("span", { class: "muted" }, "not signed in")],
      ["Run", h("span", null, p.started_at ? absTime(p.started_at) : "–", " to ", p.last_at ? absTime(p.last_at) : "–", p.ended ? " (ended)" : "")],
      ["Foreground at last sample", p.foreground === undefined ? "–" : p.foreground ? "yes" : "no"],
      ["Screen", dash(p.screen)],
    ])));
    out.push(h("div", { class: "grid-2" },
      card("Device and app", kv([
        ["App version", h("span", null, dash(app.name), app.code !== undefined ? " (code " + app.code + ")" : "")],
        ["Model", dash(dev.model)],
        ["OS", h("span", null, dash(dev.os), " ", dev.os_version || "", dev.sdk !== undefined ? " (SDK " + dev.sdk + ")" : "")],
        ["CPU cores", dash(dev.cpu_count)],
        ["RAM", dev.ram_gb !== undefined ? num1(dev.ram_gb) + " GB" : "–"],
        ["Tier", dash(dev.tier)],
        ["Screen", dash(dev.screen)],
        ["GPU", dash(dev.gpu)],
        ["GPU vendor", dash(dev.gpu_vendor)],
        ["GPU API", mono(dev.gpu_api)],
      ])),
      card("Match", m ? kv([
        ["Game", dash(m.game)], ["Mode", dash(m.mode)], ["Minutes in", m.minutes !== undefined ? num1(m.minutes) : "–"], ["Turns", dash(m.turns)],
      ]) : emptyState("No match running", "The app was not in a match at the last sample.", "info"))));
    out.push(card("Exit reason (Android)", ex ? h("div", { class: "stack" }, kv([
      ["Reason", reasonBadge(ex.reason)],
      ["Code / status", h("span", { class: "mono" }, (ex.code ?? "–") + " / " + (ex.status ?? "–"))],
      ["Importance", h("span", null, dash(ex.importance_name), ex.importance !== undefined ? " (" + ex.importance + ")" : "")],
      ["PSS", ex.pss_kb !== undefined ? fmtInt(Math.round(ex.pss_kb / 1024)) + " MB" : "–"],
      ["RSS", ex.rss_kb !== undefined ? fmtInt(Math.round(ex.rss_kb / 1024)) + " MB" : "–"],
      ["Exit time", ex.at ? absTime(ex.at) : "–"],
      ["Description", dash(ex.description)],
    ]), ex.trace ? h("pre", { class: "pre" }, ex.trace) : null)
      : emptyState("No exit info", "Android gave no exit reason (older versions, or the run was only marked unclean).", "info")));
    out.push(card("Breadcrumbs", crumbs.length
      ? simpleTable([
        { label: "t (s)", align: "right", render: (c) => fmtInt(c.t) },
        { label: "Event", render: (c) => h("span", { class: "tag" }, c.e || "–") },
        { label: "Detail", cls: "col-main", render: (c) => dash(c.d) },
      ], crumbs, { caption: "Breadcrumbs" })
      : emptyState("No breadcrumbs", "", "info"), { cls: "card-flush", sub: "Seconds since the run started." }));
    out.push(card("Samples", samples.length
      ? simpleTable([
        { label: "t (s)", align: "right", render: (s) => fmtInt(s.t) },
        { label: "Mem MB", align: "right", render: (s) => num1(s.mem) },
        { label: "Peak MB", align: "right", render: (s) => num1(s.mem_peak) },
        { label: "VMem MB", align: "right", render: (s) => num1(s.vmem) },
        { label: "FPS", align: "right", render: (s) => fmtInt(s.fps) },
        { label: "Objects", align: "right", render: (s) => fmtInt(s.objects) },
        { label: "Nodes", align: "right", render: (s) => fmtInt(s.nodes) },
        { label: "Screen", render: (s) => dash(s.screen) },
        { label: "FG", render: (s) => (s.fg === undefined ? "–" : s.fg ? "yes" : "no") },
      ], samples, { caption: "Samples" })
      : emptyState("No samples", "", "info"), { cls: "card-flush" }));
    out.push(card("Log tail", p.log ? h("pre", { class: "pre", style: { maxHeight: "480px" } }, p.log) : emptyState("No log", "", "info"),
      { sub: "The end of the previous run's godot.log (scrubbed of tokens and e-mail addresses)." }));
    return out;
  }
}
