// Leaderboards: XP / online wins, weekly / all time (the same population as the public board).
import { h, replace, fmtInt, timeEl, tickTimes } from "../dom.js";
import { api } from "../api.js";
import { avatar, card, emptyState, errorState, skeletonBlock, accountLink, toastErr } from "../ui.js";
import { pageHead, chipGroup, selectFilter, textFilter, filterBar, refreshButton } from "./common.js";
import { simpleTable } from "./account_cells.js";

const BOARDS = [["xp", "XP"], ["wins", "Online wins"]];
const PERIODS = [["week", "Weekly"], ["all", "All time"]];
const LIMITS = [["50", "Top 50"], ["100", "Top 100"], ["200", "Top 200"]];
const WEEK_RE = /^\d{4}-W\d{2}$/;

export default function leaderboardsPage(root, _params, ctx) {
  ctx.title("Leaderboards");
  const q = ctx.query;
  const state = {
    board: q.get("board") === "wins" ? "wins" : "xp",
    period: q.get("period") === "all" ? "all" : "week",
    week: WEEK_RE.test(q.get("week") || "") ? q.get("week") : "",
    limit: LIMITS.some(([v]) => v === q.get("limit")) ? q.get("limit") : "50",
  };
  const out = h("div", null, skeletonBlock(6));
  let gen = 0;

  const weekIn = textFilter({ value: state.week, placeholder: "Week YYYY-Www (default: this week)", label: "Past week, e.g. 2026-W42", mono: true, onInput: (v) => { state.week = v; run(); } });
  weekIn.classList.add("w-week");
  weekIn.style.width = "230px";
  const weekBad = h("span", { class: "field-err", role: "alert", hidden: true }, "Use the form 2026-W42.");

  async function run() {
    ctx.setQuery({ board: state.board === "xp" ? "" : state.board, period: state.period === "week" ? "" : state.period, week: state.week, limit: state.limit === "50" ? "" : state.limit });
    weekIn.hidden = state.period !== "week";
    const bad = state.period === "week" && state.week !== "" && !WEEK_RE.test(state.week);
    weekBad.hidden = !bad;
    weekIn.setAttribute("aria-invalid", String(bad));
    if (bad) return;
    const my = ++gen;
    replace(out, skeletonBlock(6));
    try {
      const res = await api.get("/leaderboards", {
        board: state.board, period: state.period, limit: state.limit, week: state.period === "week" && state.week ? state.week : undefined,
      });
      if (my !== gen) return;
      render(res);
    } catch (err) {
      if (my !== gen || err.status === 401) return;
      replace(out, errorState(err, run));
      toastErr(err, "Leaderboard");
    }
  }

  function render(res) {
    const top = Array.isArray(res.top) ? res.top : [];
    const label = state.board === "xp" ? "XP" : "Online wins";
    const when = res.period === "week" ? "Week " + (res.week || "") : "All time";
    const table = top.length
      ? simpleTable([
        { label: "Rank", render: (r) => h("span", { class: "rank rank-" + r.rank }, String(r.rank)) },
        { label: "Player", cls: "col-main", render: (r) => h("div", { class: "who" }, avatar(r.avatar, r.name),
          h("div", { class: "who-text" }, h("a", { href: "#/accounts/" + encodeURIComponent(r.account_id), class: "who-name" }, r.name || "Player"),
            r.frame ? h("span", { class: "who-sub mono" }, "frame " + r.frame) : null)) },
        { label: "Level", align: "right", render: (r) => fmtInt(r.level) },
        { label: label, align: "right", render: (r) => h("strong", null, fmtInt(r.value)) },
        { label: "Updated", render: (r) => timeEl(r.updated_at) },
        { label: "Account", render: (r) => accountLink(r.account_id, "Open") },
      ], top, { caption: label + " leaderboard, " + when })
      : emptyState("Nobody on this board yet", "Accounts need at least 3 completed matches to be listed.", "trophy");
    replace(out, card(label + " · " + when, table, {
      cls: "card-flush",
      sub: `${fmtInt(res.total)} listed in total, showing the top ${top.length}. Accounts need at least 3 completed matches to be listed; banned and merged accounts are left out.`,
    }));
    tickTimes(out);
  }

  root.append(
    pageHead(null, "The public boards as players see them. Accounts need at least 3 completed matches to be listed.", [refreshButton(() => run())]),
    filterBar(
      chipGroup({ value: state.board, options: BOARDS, label: "Board", onChange: (v) => { state.board = v; run(); } }),
      chipGroup({ value: state.period, options: PERIODS, label: "Period", onChange: (v) => { state.period = v; run(); } }),
      weekIn, weekBad,
      selectFilter({ value: state.limit, options: LIMITS, label: "How many rows", onChange: (v) => { state.limit = v; run(); } })),
    out);
  run();
}
