// Usage: today's use of the Cloudflare Workers Free allowances (Workers, Durable Objects, D1) against the real limits,
// what is left, the reset countdown, today by hour, the last 7 days and a rough "games left" estimate
// (ADMIN_API.md "Usage"). The server caches Cloudflare's numbers for 5 minutes, so the page refreshes every minute.
import { h, replace, fmtInt, poll, relTime } from "../dom.js";
import { api } from "../api.js";
import { lineChart } from "../chart.js";
import { card, badge, emptyState, errorState, skeletonBlock, toastErr, helpTip } from "../ui.js";
import { icon } from "../icons.js";
import { pageHead, refreshButton, updatedLabel } from "./common.js";

const GROUPS = [
  ["workers", "Workers", "Requests that start the Worker."],
  ["do", "Durable Objects", "Game rooms and the quick-match queue."],
  ["d1", "D1 database", "Admin stats, accounts and leaderboards."],
];
const LEVEL_TONE = { ok: "ok", warning: "warn", danger: "danger" };
const LEVEL_TEXT = { ok: "OK", warning: "Warning", danger: "Almost out" };

const HOUR_FMT = new Intl.DateTimeFormat("en-GB", { hour: "2-digit", minute: "2-digit", timeZone: "UTC", hour12: false });
const HOUR_LONG = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "UTC", hour12: false });

function bytes(n) {
  n = Number(n) || 0;
  if (n < 1e3) return n + " B";
  if (n < 1e6) return (n / 1e3).toFixed(1).replace(/\.0$/, "") + " KB";
  if (n < 1e9) return (n / 1e6).toFixed(1).replace(/\.0$/, "") + " MB";
  return (n / 1e9).toFixed(2).replace(/0$/, "").replace(/\.0$/, "") + " GB";
}

/** A metric's number in its unit: 12,345 / 118.4 GB-s / 12.4 MB. */
function fmtVal(m, v) {
  if (m.unit === "bytes") return bytes(v);
  if (m.unit === "gbs") return fmtInt(Math.round(Number(v) * 10) / 10) + " GB-s";
  return fmtInt(v);
}

function countdown(resetAt) {
  const ms = Math.max(0, Date.parse(resetAt) - Date.now());
  const m = Math.floor(ms / 60e3);
  return Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0") + "m";
}

export default function usagePage(root, _params, ctx) {
  ctx.title("Usage");
  const upd = updatedLabel(ctx, { live: true, every: "60s" });
  const body = h("div", null, skeletonBlock(8));
  let data = null;
  let failed = 0;
  let charts = [];
  const resetTxt = h("strong", null, "–");

  root.append(
    pageHead(null, "Cloudflare Workers Free plan: what the game server has used today (UTC day) and what is left.", [upd.el, refreshButton(() => load(true))]),
    body,
  );

  async function load(manual = false) {
    try {
      const d = await api.get("/usage");
      failed = 0;
      data = d;
      render(d);
      upd.mark();
    } catch (err) {
      if (err.status === 401) return;
      failed++;
      upd.stale();
      if (!data) replace(body, errorState(err, () => load(true)));
      if (manual || failed === 1) toastErr(err, "Usage");
    }
  }

  function destroyCharts() {
    charts.forEach((c) => c.destroy?.());
    charts = [];
  }

  function render(d) {
    destroyCharts();
    if (!d.configured) return replace(body, notConfigured(d));
    const kids = [];
    if (d.stale) {
      kids.push(h("div", { class: "callout callout-warn", role: "status" }, icon("alert", { size: 16 }),
        h("div", null, h("strong", null, "Showing the last good numbers. "), d.error_msg || "Cloudflare did not answer.")));
    }
    kids.push(summary(d));
    for (const [g, title, sub] of GROUPS) {
      const ms = d.metrics.filter((m) => m.group === g);
      if (ms.length) kids.push(h("section", { class: "group", "aria-labelledby": "g-" + g },
        h("h3", { class: "group-title", id: "g-" + g }, title, " ", h("span", { class: "muted" }, "· " + sub)),
        h("div", { class: "usage-grid" }, ms.map((m) => metricCard(m)))));
    }
    kids.push(h("div", { class: "grid-2-1" }, hourCard(d), historyCard(d)));
    kids.push(footer(d));
    replace(body, ...kids);
    paintCountdown();
  }

  function paintCountdown() {
    if (data?.reset_at) resetTxt.textContent = countdown(data.reset_at);
  }

  function summary(d) {
    const e = d.estimate || {};
    const lim = e.limiting ? d.metrics.find((m) => m.id === e.limiting) : null;
    const worst = d.metrics.filter((m) => m.period === "day").reduce((a, b) => (b.percent > a.percent ? b : a), { percent: -1 });
    return h("div", { class: "usage-summary" },
      h("div", { class: "tile" },
        h("div", { class: "tile-label" }, icon("clock", { size: 14 }), "Resets in"),
        h("div", { class: "tile-value" }, resetTxt),
        h("div", { class: "tile-foot" }, h("span", { class: "tile-sub" }, "Daily allowances reset at 00:00 UTC (" + new Date(d.reset_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) + " your time)"))),
      h("div", { class: "tile" },
        h("div", { class: "tile-label" }, icon("usage", { size: 14 }), "Most used today"),
        h("div", { class: "tile-value" }, worst.percent >= 0 ? worst.percent + "%" : "–"),
        h("div", { class: "tile-foot" }, h("span", { class: "tile-sub" }, worst.label || ""))),
      h("div", { class: "tile tile-accent" },
        h("div", { class: "tile-label" }, icon("matches", { size: 14 }), "Games left today (estimate)",
          helpTip("A rough guess, not a promise: what is left of each allowance divided by what one match has cost so far, then the tightest allowance wins. Other traffic (menus, accounts, pushes) is in the cost.", "About the estimate")),
        h("div", { class: "tile-value" }, e.games_left === null || e.games_left === undefined ? "–" : "~" + fmtInt(e.games_left)),
        h("div", { class: "tile-foot" }, h("span", { class: "tile-sub" }, estimateNote(e, lim)))));
  }

  function estimateNote(e, lim) {
    if (e.games_left === null || e.games_left === undefined) return "Needs at least one match to measure";
    return `At the cost of ${fmtInt(e.matches)} match${e.matches === 1 ? "" : "es"} (${e.basis === "today" ? "today" : "last 7 days"}); limited by ${lim ? lim.label.toLowerCase() : e.limiting}`;
  }

  function metricCard(m) {
    const total = m.period === "total";
    const bar = h("div", { class: "meter meter-" + m.level, role: "progressbar", "aria-label": m.label, "aria-valuemin": "0", "aria-valuemax": "100", "aria-valuenow": String(m.percent), "aria-valuetext": `${m.percent}% used` },
      h("div", { class: "meter-fill", style: { width: Math.max(m.percent > 0 ? 1 : 0, m.percent) + "%" } }));
    return h("section", { class: "card usage-card usage-" + m.level },
      h("div", { class: "card-body" },
        h("div", { class: "usage-top" },
          h("h4", { class: "usage-name" }, m.label),
          badge(m.percent + "% · " + LEVEL_TEXT[m.level], LEVEL_TONE[m.level], m.level === "ok" ? "check" : "alert")),
        h("div", { class: "usage-nums" },
          h("span", { class: "usage-used" }, fmtVal(m, m.used)),
          h("span", { class: "usage-limit" }, " / " + fmtVal(m, m.limit) + (total ? "" : " per day"))),
        bar,
        h("div", { class: "usage-left" },
          h("span", null, h("strong", null, fmtVal(m, m.left)), total ? " left" : " left today"),
          total ? h("span", { class: "muted" }, "does not reset") : null),
        m.mine !== undefined && m.mine !== m.used ? h("p", { class: "usage-extra" }, `This Worker: ${fmtVal(m, m.mine)}, the rest is other Workers on the account.`) : null,
        m.id === "d1_storage" && m.databases > 1 ? h("p", { class: "usage-extra" }, `${m.databases} databases, ${bytes(m.total_bytes)} in total (limit 5 GB).`) : null,
        h("p", { class: "usage-note" }, m.note)));
  }

  function hourCard(d) {
    const hv = d.hourly || { hours: [] };
    if (!hv.hours.length) return card("Today by hour", emptyState("No data yet", "Cloudflare shows today's first hour shortly after midnight UTC.", "chart"));
    const el = lineChart({
      title: "Workers requests and Durable Object requests per hour today (UTC)",
      days: hv.hours,
      series: [
        { key: "workers_requests", name: "Workers requests", tone: 1, values: hv.workers_requests },
        { key: "do_requests", name: "Durable Object requests", tone: 2, values: hv.do_requests },
      ],
      yLabel: "Requests per hour", xLabel: "Hour (UTC)", pointLabel: "Hour (UTC)",
      fmtShort: (x) => HOUR_FMT.format(new Date(x)), fmtLong: (x) => HOUR_LONG.format(new Date(x)) + " UTC",
    });
    charts.push(el);
    return card("Today by hour", h("div", { class: "chart-box" }, el), { sub: "Counts toward the 100,000 per day allowances." });
  }

  function historyCard(d) {
    const days = d.daily || [];
    if (!days.length) return card("Last 7 days", emptyState("No history", "", "chart"));
    const col = (k) => days.map((x) => Number(x[k]) || 0);
    const el = lineChart({
      title: "Workers requests and Durable Object requests per day, last 7 days",
      days: days.map((x) => x.day),
      series: [
        { key: "workers_requests", name: "Workers requests", tone: 1, values: col("workers_requests") },
        { key: "do_requests", name: "Durable Object requests", tone: 2, values: col("do_requests") },
      ],
      yLabel: "Requests per day", height: 220,
    });
    charts.push(el);
    return card("Last 7 days", h("div", { class: "chart-box" }, el), { sub: "Daily totals; the limit is 100,000 each." });
  }

  function footer(d) {
    const e = d.estimate || {};
    const per = Object.entries(e.per_game || {}).map(([id, v]) => {
      const m = d.metrics.find((x) => x.id === id);
      return h("li", null, m ? m.label : id, ": ", h("strong", null, fmtInt(v)), " per match");
    });
    return h("div", { class: "usage-foot" },
      per.length ? h("details", { class: "usage-details" }, h("summary", null, "Cost of one match (basis of the estimate)"), h("ul", null, per)) : null,
      h("details", { class: "usage-details" }, h("summary", null, "Per-request limits (not daily)"),
        h("ul", null, (d.info || []).map((i) => h("li", null, i.label, ": ", h("strong", null, i.value))))),
      h("p", { class: "usage-sampling" }, "Account " + d.account_id + " · Cloudflare data fetched ", h("time", { datetime: new Date(d.cached_at).toISOString() }, relTime(d.cached_at)), " (cached up to 5 min). ", d.sampling));
  }

  function notConfigured(d) {
    const st = d.setup || { steps: [] };
    return h("div", null,
      h("div", { class: "callout callout-warn", role: "status" }, icon("alert", { size: 16 }),
        h("div", null, h("strong", null, "Not configured. "), "The Usage page needs a Cloudflare API token to read this account's analytics. Until then it can only show the limits below.")),
      h("div", { class: "grid-2-1" },
        card("Set it up", h("ol", { class: "usage-steps" }, st.steps.map((t) => h("li", null, t))), {
          sub: "Secret " + (st.secret || "CF_API_TOKEN") + ", permission: " + (st.permission || "Account Analytics Read") + ".",
        }),
        card("Free-plan limits", h("dl", { class: "kv" }, d.metrics.map((m) => [h("dt", null, m.label), h("dd", null, fmtVal(m, m.limit) + (m.period === "day" ? " / day" : ""))])),
          { sub: "Resets at 00:00 UTC." })));
  }

  load();
  const p = poll(() => load(), 60000);
  const t = setInterval(paintCountdown, 30000);
  ctx.onCleanup(() => { p.stop(); clearInterval(t); destroyCharts(); });
}
