// Quick match: today's KPIs, a 14-day chart, and the per day / game / size table (ADMIN_API.md "quick").
import { h, replace, fmtInt, duration, poll } from "../dom.js";
import { api } from "../api.js";
import { lineChart } from "../chart.js";
import { card, emptyState, errorState, skeletonBlock, toastErr } from "../ui.js";
import { pageHead, tile, tileSkeleton, selectFilter, filterBar, refreshButton, updatedLabel } from "./common.js";
import { simpleTable, pctText } from "./account_cells.js";

const RANGES = [["7", "Last 7 days"], ["14", "Last 14 days"], ["30", "Last 30 days"], ["90", "Last 90 days"]];
const GAMES = { ludo: "Ludo", sl: "Snakes & Ladders" };
const gameName = (g) => GAMES[g] || g || "–";
const pctNum = (n, d) => (d > 0 ? Math.round((n / d) * 100) : 0);

/** Every UTC day from `from` for `days` days. */
function dayList(from, days) {
  const out = [];
  const t0 = Date.parse(from + "T00:00:00Z");
  for (let i = 0; i < days; i++) out.push(new Date(t0 + i * 86400e3).toISOString().slice(0, 10));
  return out;
}

export default function quickPage(root, _params, ctx) {
  ctx.title("Quick match");
  const r0 = ctx.query.get("days");
  const state = { days: RANGES.some(([v]) => v === r0) ? r0 : "14" };
  const upd = updatedLabel(ctx, { live: true, every: "30s" });
  const tilesBox = h("div", { class: "tiles tiles-5" }, [1, 2, 3, 4, 5].map(() => tileSkeleton()));
  const chartsBox = h("div", { class: "grid-2" }, card("Matched and queued", skeletonBlock(6)), card("Ghost-fill rate", skeletonBlock(6)));
  const tableBox = h("div", null, skeletonBlock(6));
  const totalsBox = h("div", null);
  const charts = [];
  let failed = 0;

  async function load(manual = false) {
    ctx.setQuery({ days: state.days === "14" ? "" : state.days });
    try {
      const res = await api.get("/quick", { days: state.days });
      failed = 0;
      render(res);
      upd.mark();
    } catch (err) {
      if (err.status === 401) return;
      failed++;
      upd.stale();
      if (!charts.length) { replace(tilesBox); replace(chartsBox, errorState(err, () => load(true))); replace(tableBox); }
      if (manual || failed === 1) toastErr(err, "Quick match");
    }
  }

  function render(res) {
    const rows = Array.isArray(res.rows) ? res.rows : [];
    const totals = Array.isArray(res.totals) ? res.totals : [];
    const days = dayList(res.from, Number(res.days) || Number(state.days));
    const today = days[days.length - 1];

    // KPI tiles: today (UTC) across every game and size
    const tr = rows.filter((r) => r.day === today);
    const sum = (k) => tr.reduce((a, r) => a + (Number(r[k]) || 0), 0);
    const queued = sum("queued"), matched = sum("matched"), ghost = sum("ghost_filled"), hw = sum("human_wins"), gw = sum("ghost_wins");
    const waitTotal = tr.reduce((a, r) => a + (Number(r.avg_wait_ms) || 0) * (Number(r.matched) || 0), 0);
    replace(tilesBox,
      tile({ label: "Queued today", value: queued, ic: "quick", foot: h("span", { class: "tile-sub" }, "Humans who joined the queue (UTC day)") }),
      tile({ label: "Matched today", value: matched, foot: h("span", { class: "tile-sub" }, "Humans placed in a match") }),
      tile({ label: "Ghost-filled", value: matched + ghost > 0 ? pctNum(ghost, matched + ghost) + "%" : "–", foot: h("span", { class: "tile-sub" }, fmtInt(ghost) + " ghost seats") }),
      tile({ label: "Average wait", value: matched > 0 ? duration(waitTotal / matched) : "–", foot: h("span", { class: "tile-sub" }, "Matched humans, today") }),
      tile({ label: "Human win rate vs ghosts", value: hw + gw > 0 ? pctNum(hw, hw + gw) + "%" : "–", foot: h("span", { class: "tile-sub" }, `${fmtInt(hw)} human, ${fmtInt(gw)} ghost wins`) }));

    // charts: per day over every game and size
    for (const c of charts.splice(0)) c.destroy?.();
    if (!rows.length) {
      replace(chartsBox, h("div", { class: "card", style: { gridColumn: "1 / -1" } }, emptyState("No quick matches yet", "Daily numbers appear after the first quick match.", "chart")));
    } else {
      const by = new Map(days.map((d) => [d, { queued: 0, matched: 0, ghost: 0 }]));
      for (const r of rows) {
        const b = by.get(r.day);
        if (!b) continue;
        b.queued += Number(r.queued) || 0; b.matched += Number(r.matched) || 0; b.ghost += Number(r.ghost_filled) || 0;
      }
      const col = (f) => days.map((d) => f(by.get(d)));
      const c1 = lineChart({
        title: "Humans matched and queued per day", days,
        series: [{ key: "matched", name: "Matched", tone: 1, values: col((b) => b.matched) }, { key: "queued", name: "Queued", tone: 2, values: col((b) => b.queued) }],
        yLabel: "Humans per day", height: 232,
      });
      const c2 = lineChart({
        title: "Ghost-fill rate per day (ghost seats as a share of all seats; 0 on days without matches)", days,
        series: [{ key: "rate", name: "Ghost seats %", tone: 1, values: col((b) => pctNum(b.ghost, b.matched + b.ghost)) }],
        yLabel: "% of seats", height: 232,
      });
      charts.push(c1, c2);
      replace(chartsBox, card("Matched and queued", c1, { sub: "Humans per UTC day, every game and size." }), card("Ghost-fill rate", c2, { sub: "Ghost seats as a share of all seats. Days without matches show 0." }));
    }

    // table: per day / game / size
    const cols = [
      { label: "Day (UTC)", render: (r) => (r.day === "total" ? h("strong", null, "Total") : h("span", { class: "mono" }, r.day)) },
      { label: "Game", render: (r) => gameName(r.game) },
      { label: "Size", align: "right", render: (r) => r.size + "-player" },
      { label: "Queued", align: "right", render: (r) => fmtInt(r.queued) },
      { label: "Matched", align: "right", render: (r) => fmtInt(r.matched) },
      { label: "Ghost-filled", align: "right", render: (r) => h("span", { title: fmtInt(r.ghost_filled) + " ghost seats" }, pctText(r.ghost_fill_rate)) },
      { label: "Avg wait", align: "right", render: (r) => (r.avg_wait_ms === null || r.avg_wait_ms === undefined ? "–" : duration(r.avg_wait_ms)) },
      { label: "Human win rate", align: "right", render: (r) => h("span", { title: `${fmtInt(r.human_wins)} human / ${fmtInt(r.ghost_wins)} ghost wins` }, pctText(r.human_win_rate)) },
    ];
    replace(tableBox, rows.length ? simpleTable(cols, rows, { caption: "Quick match per day, game and size" }) : emptyState("No rows in this range", "", "table"));
    replace(totalsBox, totals.length
      ? card("Totals for the period", simpleTable(cols, totals, { caption: "Totals per game and size", rowClass: () => "row-total" }), { cls: "card-flush", sub: res.days + " days from " + res.from + "." })
      : null);
  }

  root.append(
    pageHead(null, "Quick match queue and ghost seats. Ghost seats look like players in the game; only this console shows them.", [upd.el, refreshButton(() => load(true))]),
    filterBar(selectFilter({ value: state.days, options: RANGES, label: "Date range", onChange: (v) => { state.days = v; load(true); } })),
    h("section", { class: "group", "aria-labelledby": "g-qtoday" }, h("h3", { class: "group-title", id: "g-qtoday" }, "Today ", h("span", { class: "muted" }, "(UTC day, all games and sizes)")), tilesBox),
    chartsBox,
    card("Per day, game and size", tableBox, { cls: "card-flush", sub: "Newest first." }),
    h("div", { style: { marginTop: "16px" } }, totalsBox));
  load();
  const p = poll(() => load(), 30000);
  ctx.onCleanup(() => { p.stop(); for (const c of charts) c.destroy?.(); });
}
