// Status: live KPIs, today's numbers, 14-day chart, recent warnings / errors. Auto-refresh 15 s (paused when hidden).
import { h, clear, replace, poll, fmtInt, timeEl, tickTimes } from "../dom.js";
import { api } from "../api.js";
import { lineChart, sparkline } from "../chart.js";
import { card, levelBadge, codeLink, pidLink, emptyState, errorState, toastErr, skeletonBlock, helpTip, PAUSED_HELP } from "../ui.js";
import { icon } from "../icons.js";
import { pageHead, tile, tileSkeleton, refreshButton, updatedLabel } from "./common.js";

export default function statusPage(root, _params, ctx) {
  ctx.title("Status");
  const upd = updatedLabel(ctx, { live: true, every: "15s" });
  const liveRow = h("div", { class: "tiles tiles-3" }, tileSkeleton(), tileSkeleton(), tileSkeleton());
  const todayRow = h("div", { class: "tiles tiles-4" }, tileSkeleton(), tileSkeleton(), tileSkeleton(), tileSkeleton());
  const acctRow = h("div", { class: "tiles tiles-6" }, [1, 2, 3, 4, 5, 6].map(() => tileSkeleton()));
  const acctGroup = h("section", { class: "group", "aria-labelledby": "g-acct" }, h("h3", { class: "group-title", id: "g-acct" }, "Accounts"), acctRow);
  const chartBox = h("div", { class: "chart-box" }, skeletonBlock(6));
  const eventsBox = h("div", null, skeletonBlock(5));
  let chartKey = "";
  let chartEl = null;
  let failed = 0;

  root.append(
    pageHead(null, "Live activity on the room server and the last 14 days.", [upd.el, refreshButton(() => load(true))]),
    h("section", { class: "group", "aria-labelledby": "g-live" }, h("h3", { class: "group-title", id: "g-live" }, "Live now"), liveRow),
    h("section", { class: "group", "aria-labelledby": "g-today" }, h("h3", { class: "group-title", id: "g-today" }, "Today ", h("span", { class: "muted" }, "(UTC day)")), todayRow),
    acctGroup,
    h("div", { class: "grid-2-1" },
      card("Last 14 days", chartBox, { sub: "Matches started and distinct active players per UTC day." }),
      card("Recent warnings and errors", eventsBox, { actions: h("a", { href: "#/events?level=warn", class: "btn btn-sm btn-ghost" }, "All events") })),
  );

  async function load(manual = false) {
    try {
      const o = await api.get("/overview");
      failed = 0;
      render(o);
      upd.mark();
    } catch (err) {
      if (err.status === 401) return;
      failed++;
      upd.stale();
      if (!chartKey) {
        replace(chartBox, errorState(err, () => load(true)));
        clear(liveRow); clear(todayRow); clear(acctRow);
        clear(eventsBox);
      }
      if (manual || failed === 1) toastErr(err, "Overview");
    }
  }

  function render(o) {
    const live = o.live || {};
    const today = o.today || {};
    const days = Array.isArray(o.days) ? o.days : [];
    ctx.setMaintenance(o.maintenance);
    const col = (k) => days.map((d) => Number(d[k]) || 0);
    const prev = (k) => (days.length > 1 ? Number(days[days.length - 2][k]) || 0 : null);
    const foot = (k, label) => {
      const vals = col(k);
      const p = prev(k);
      return [sparkline(vals, `${label}, last ${vals.length} days: ${vals.join(", ")}`), p === null ? null : h("span", { class: "tile-sub" }, "Yesterday " + fmtInt(p))];
    };
    replace(liveRow,
      tile({ label: "Rooms in lobby", value: Number(live.rooms_lobby) || 0, ic: "rooms", foot: h("span", { class: "tile-sub" }, "Waiting for the host to start") }),
      tile({ label: "Rooms playing", value: Number(live.rooms_playing) || 0, ic: "matches", tone: "tile-accent", foot: [
        h("a", { href: "#/rooms?status=playing", class: "tile-link" }, "View live rooms"),
        pausedNote(Number(live.rooms_paused) || 0)] }),
      tile({ label: "Members online", value: Number(live.members_online) || 0, ic: "players", foot: h("span", { class: "tile-sub" }, "Connected sockets in rooms") }));
    replace(todayRow,
      tile({ label: "Rooms created", value: Number(today.rooms) || 0, foot: foot("rooms", "Rooms created") }),
      tile({ label: "Matches", value: Number(today.matches) || 0, foot: foot("matches", "Matches") }),
      tile({ label: "Active players", value: Number(today.players_active) || 0, foot: foot("players_active", "Active players") }),
      tile({ label: "New players", value: Number(today.new_players) || 0, foot: h("span", { class: "tile-sub" }, "First seen today") }));

    const ac = o.accounts;
    acctGroup.hidden = !ac;
    if (ac) {
      replace(acctRow,
        tile({ label: "Accounts", value: Number(ac.total) || 0, ic: "accounts", foot: [
          h("a", { href: "#/accounts", class: "tile-link" }, "View accounts"),
          h("span", { class: "tile-sub" }, fmtInt(ac.banned) + " banned")] }),
        tile({ label: "Google-linked", value: Number(ac.linked) || 0, foot: h("a", { href: "#/accounts?linked=1", class: "tile-link" }, "View linked") }),
        tile({ label: "Guests", value: Number(ac.guests) || 0, foot: h("a", { href: "#/accounts?linked=0", class: "tile-link" }, "View guests") }),
        tile({ label: "New today", value: Number(ac.new_today) || 0, foot: h("span", { class: "tile-sub" }, "Created today (UTC)") }),
        tile({ label: "Coins in circulation", value: Number(ac.coins_in_circulation) || 0, ic: "coin", foot: h("span", { class: "tile-sub" }, "Sum of all balances") }),
        tile({ label: "Claims limited today", value: Number(ac.claims_limited_today) || 0, tone: Number(ac.claims_limited_today) ? "tile-warn" : "", foot: h("span", { class: "tile-sub" }, "Bangladesh day") }));
    }

    const key = JSON.stringify(days);
    if (key !== chartKey) {
      chartKey = key;
      chartEl?.destroy?.();
      if (!days.length) replace(chartBox, emptyState("No history yet", "Daily numbers appear after the first day of play.", "chart"));
      else {
        chartEl = lineChart({
          title: "Matches and active players per day, last 14 days",
          days: days.map((d) => d.day),
          series: [
            { key: "matches", name: "Matches", tone: 1, values: col("matches") },
            { key: "players_active", name: "Active players", tone: 2, values: col("players_active") },
          ],
          yLabel: "Count per day",
        });
        replace(chartBox, chartEl);
      }
    }

    const evs = Array.isArray(o.recent_events) ? o.recent_events : [];
    if (!evs.length) replace(eventsBox, emptyState("All quiet", "No warnings or errors recently.", "check"));
    else {
      replace(eventsBox, h("ul", { class: "evlist" }, evs.map((e) => h("li", { class: "ev ev-" + (e.level || "info") },
        h("div", { class: "ev-top" }, levelBadge(e.level), h("span", { class: "mono ev-kind" }, e.kind || "–"), h("span", { class: "spacer" }), timeEl(e.at)),
        h("p", { class: "ev-msg" }, e.msg || ""),
        e.code || e.pid ? h("div", { class: "ev-refs" }, e.code ? codeLink(e.code) : null, e.pid ? pidLink(e.pid) : null) : null))));
      tickTimes(eventsBox);
    }
  }

  /** "2 paused" (link to the Paused tab) + a tip: matches nobody is connected to are not counted as playing. */
  function pausedNote(n) {
    return h("span", { class: "tile-paused" + (n ? " has-paused" : "") },
      h("a", { href: "#/rooms?status=paused", "aria-label": `${fmtInt(n)} paused (nobody online): view paused rooms` },
        icon("moon", { size: 12 }), fmtInt(n) + " paused"),
      helpTip("Paused (nobody online), not counted above. " + PAUSED_HELP, "About paused rooms"));
  }

  load();
  const p = poll(() => load(), 15000);
  ctx.onCleanup(() => { p.stop(); chartEl?.destroy?.(); });
}
