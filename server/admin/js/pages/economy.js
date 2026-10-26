// Economy: coins and gems created / spent per Bangladesh day, the coin tables (entries, pot, fees, payouts to people,
// ghost win rate), re-rolls, rewarded ads and gem purchases (ADMIN_API.md "Economy").
import { h, replace, fmtInt, poll } from "../dom.js";
import { api } from "../api.js";
import { lineChart } from "../chart.js";
import { card, badge, emptyState, errorState, skeletonBlock, toastErr } from "../ui.js";
import { pageHead, tile, tileSkeleton, chipGroup, refreshButton, updatedLabel } from "./common.js";
import { simpleTable } from "./account_cells.js";

const RANGES = [["7", "7 days"], ["14", "14 days"], ["30", "30 days"]];
const TIERS = { t100: "100", t500: "500", t2k: "2,000", t10k: "10,000", t50k: "50,000" };
const TIER_ORDER = Object.keys(TIERS);
const AD_KINDS = { reroll: "Re-roll", refill: "Refill (broke)", double: "Double payout", gems: "Gems" };
const GHOST_LOW = 0.4;
const GHOST_HIGH = 0.6;

const tierName = (t) => TIERS[t] || t;
const tierRank = (t) => (TIER_ORDER.indexOf(t) < 0 ? 99 : TIER_ORDER.indexOf(t));
const pct1 = (r) => (r === null || r === undefined ? "–" : Math.round(Number(r) * 1000) / 10 + "%");

export default function economyPage(root, _params, ctx) {
  ctx.title("Economy");
  const r0 = ctx.query.get("days");
  const state = { days: RANGES.some(([v]) => v === r0) ? r0 : "14" };
  const upd = updatedLabel(ctx, { live: true, every: "60s" });
  const tilesBox = h("div", { class: "tiles tiles-4" }, [1, 2, 3, 4].map(() => tileSkeleton()));
  const chartsBox = h("div", { class: "grid-2" }, card("Coins", skeletonBlock(6)), card("Gems", skeletonBlock(6)));
  const tableBox = h("div", { class: "stack econ-gap" }, skeletonBlock(5));
  const moreBox = h("div", null);
  let charts = [];
  let failed = 0;
  let loaded = false;

  const range = chipGroup({ value: state.days, options: RANGES, label: "Period", onChange: (v) => { state.days = v; load(true); } });
  root.append(
    pageHead(null, "Coins and gems created and spent per Bangladesh day (UTC+6), from the ledger and the coin tables.", [range, upd.el, refreshButton(() => load(true))]),
    tilesBox, chartsBox, tableBox, moreBox);

  async function load(manual = false) {
    ctx.setQuery({ days: state.days === "14" ? "" : state.days });
    try {
      const d = await api.get("/economy", { days: state.days });
      failed = 0;
      loaded = true;
      render(d);
      upd.mark();
    } catch (err) {
      if (err.status === 401) return;
      failed++;
      upd.stale();
      if (!loaded) { replace(tilesBox); replace(chartsBox, errorState(err, () => load(true))); replace(tableBox); }
      if (manual || failed === 1) toastErr(err, "Economy");
    }
  }

  function destroyCharts() {
    charts.forEach((c) => c.destroy?.());
    charts = [];
  }

  function render(d) {
    destroyCharts();
    const t = d.totals || {};
    const net = (a, b) => Number(a || 0) - Number(b || 0);
    const sign = (n) => (n > 0 ? "+" : "") + fmtInt(n);
    replace(tilesBox,
      tile({ label: "Coins in circulation", value: Number(d.coins_in_circulation) || 0, ic: "coin", tone: "tile-accent", foot: h("span", { class: "tile-sub" }, "All accounts, now") }),
      tile({ label: "Gems in circulation", value: Number(d.gems_in_circulation) || 0, ic: "gem", foot: h("span", { class: "tile-sub" }, "All accounts, now") }),
      tile({ label: "Table fees", value: Number(t.fees) || 0, ic: "coin", foot: h("span", { class: "tile-sub" }, `Last ${d.days} days: coins taken out of every pot (10%)`) }),
      tile({ label: "Net coins in the period", value: sign(net(t.coins_created, t.coins_spent)), foot: h("span", { class: "tile-sub" }, `${fmtInt(t.coins_created)} created, ${fmtInt(t.coins_spent)} spent`) }));

    const days = (d.per_day || []).map((x) => x.day);
    const col = (k) => (d.per_day || []).map((x) => Number(x[k]) || 0);
    const pair = (title, label, created, spent, sub) => {
      if (!days.length || ![...created, ...spent].some((v) => v > 0)) {
        return card(title, emptyState("Nothing yet", "No " + label + " moved in this period.", "chart"), { sub });
      }
      const el = lineChart({
        title: `${label} created and spent per day, last ${d.days} days`,
        days,
        series: [
          { key: "created", name: "Created", tone: 1, values: created },
          { key: "spent", name: "Spent", tone: 2, values: spent },
        ],
        yLabel: label + " per day", xLabel: "Day (Bangladesh)", height: 220,
      });
      charts.push(el);
      return card(title, h("div", { class: "chart-box" }, el), { sub });
    };
    replace(chartsBox,
      pair("Coins created vs spent", "Coins", col("coins_created"), col("coins_spent"), "Created: payouts, rewards, sales. Spent: entries, shop."),
      pair("Gems created vs spent", "Gems", col("gems_created"), col("gems_spent"), "Created: purchases, level-ups, prizes, ads. Spent: re-rolls, shop, exchange."));

    replace(tableBox, tablesCard(t.tables || []), reasonCard(t.by_reason || []));
    replace(moreBox, h("div", { class: "grid-3" }, rerollCard(t.rerolls), adsCard(t.ads || {}), purchaseCard(t.purchases)));
  }

  function tablesCard(tables) {
    const rows = [...tables].sort((a, b) => tierRank(a.tier) - tierRank(b.tier));
    const body = rows.length
      ? simpleTable([
        { label: "Table", render: (r) => h("strong", null, tierName(r.tier)) },
        { label: "Entries", align: "right", render: (r) => fmtInt(r.entries) },
        { label: "Matches", align: "right", render: (r) => fmtInt(r.matches) },
        { label: "Pot", align: "right", render: (r) => fmtInt(r.pot) },
        { label: "Fees", align: "right", render: (r) => fmtInt(r.fee) },
        { label: "Payouts to people", align: "right", render: (r) => fmtInt(r.paid_humans) },
        { label: "Ghost win rate", align: "right", render: (r) => ghostCell(r) },
      ], rows, { caption: "Coin tables", rowClass: (r) => (outOfBand(r) ? "row-limited" : "") })
      : emptyState("No table matches in this period", "Coin-table matches appear here after the first game.", "table");
    return card("Coin tables", body, { cls: "card-flush", sub: `Ghost win rate outside ${GHOST_LOW * 100}-${GHOST_HIGH * 100}% is highlighted: payouts to a ghost go to no one, so the bots must be fair.` });
  }

  function outOfBand(r) {
    return r.ghost_win_rate !== null && r.ghost_win_rate !== undefined && r.matches > 0 && (r.ghost_win_rate < GHOST_LOW || r.ghost_win_rate > GHOST_HIGH);
  }

  function ghostCell(r) {
    if (r.ghost_win_rate === null || r.ghost_win_rate === undefined) return h("span", { class: "muted" }, "–");
    const txt = pct1(r.ghost_win_rate) + " (" + fmtInt(r.ghost_wins) + "/" + fmtInt(r.matches) + ")";
    return outOfBand(r) ? badge(txt, "warn", "alert") : h("span", null, txt);
  }

  function reasonCard(reasons) {
    const rows = reasons.filter((r) => r.coins_created || r.coins_spent || r.gems_created || r.gems_spent);
    return card("By ledger reason", rows.length
      ? simpleTable([
        { label: "Reason", render: (r) => h("span", { class: "tag" }, r.reason) },
        { label: "Coins created", align: "right", render: (r) => fmtInt(r.coins_created) },
        { label: "Coins spent", align: "right", render: (r) => fmtInt(r.coins_spent) },
        { label: "Gems created", align: "right", render: (r) => fmtInt(r.gems_created) },
        { label: "Gems spent", align: "right", render: (r) => fmtInt(r.gems_spent) },
      ], rows, { caption: "Ledger by reason" })
      : emptyState("No ledger rows", "", "table"),
    { cls: "card-flush", sub: "Over the period." });
  }

  const stat = (label, value, hint) => [h("dt", null, label), h("dd", null, fmtInt(value), hint ? h("span", { class: "muted" }, hint) : null)];

  function rerollCard(r) {
    r = r || { free: 0, gems: 0 };
    return card("Re-rolls", h("dl", { class: "kv" }, stat("Free re-rolls used", r.free), stat("Paid with gems", r.gems, "(5 gems each)"), stat("Gems spent on re-rolls", Number(r.gems) * 5)),
      { sub: "People only: ghost re-rolls are not stored." });
  }

  function adsCard(ads) {
    const kinds = Object.keys(AD_KINDS);
    const extra = Object.keys(ads).filter((k) => !kinds.includes(k));
    return card("Rewarded ads", h("dl", { class: "kv" }, [...kinds, ...extra].map((k) => stat(AD_KINDS[k] || k, ads[k] || 0))),
      { sub: "Granted rewards only." });
  }

  function purchaseCard(p) {
    p = p || { count: 0, gems: 0, voided: 0 };
    return card("Gem purchases", h("dl", { class: "kv" }, stat("Purchases", p.count), stat("Gems sold", p.gems), stat("Voided (refunded)", p.voided)),
      { sub: "Google Play, granted purchases." });
  }

  load();
  const p = poll(() => load(), 60000);
  ctx.onCleanup(() => { p.stop(); destroyCharts(); });
}
