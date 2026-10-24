// Status: live KPIs, today's numbers, 14-day chart, recent warnings / errors. Auto-refresh 15 s (paused when hidden).
import { h, clear, replace, poll, fmtInt, timeEl, tickTimes } from "../dom.js";
import { api } from "../api.js";
import { lineChart, sparkline } from "../chart.js";
import { card, levelBadge, codeLink, pidLink, emptyState, errorState, toastErr, skeletonBlock } from "../ui.js";
import { pageHead, tile, tileSkeleton, refreshButton, updatedLabel } from "./common.js";

export default function statusPage(root, _params, ctx) {
  ctx.title("Status");
  const upd = updatedLabel(ctx, { live: true, every: "15s" });
  const liveRow = h("div", { class: "tiles tiles-3" }, tileSkeleton(), tileSkeleton(), tileSkeleton());
  const todayRow = h("div", { class: "tiles tiles-4" }, tileSkeleton(), tileSkeleton(), tileSkeleton(), tileSkeleton());
  const chartBox = h("div", { class: "chart-box" }, skeletonBlock(6));
  const eventsBox = h("div", null, skeletonBlock(5));
  let chartKey = "";
  let chartEl = null;
  let failed = 0;

  root.append(
    pageHead(null, "Live activity on the room server and the last 14 days.", [upd.el, refreshButton(() => load(true))]),
    h("section", { class: "group", "aria-labelledby": "g-live" }, h("h3", { class: "group-title", id: "g-live" }, "Live now"), liveRow),
    h("section", { class: "group", "aria-labelledby": "g-today" }, h("h3", { class: "group-title", id: "g-today" }, "Today ", h("span", { class: "muted" }, "(UTC day)")), todayRow),
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
        clear(liveRow); clear(todayRow);
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
      tile({ label: "Rooms playing", value: Number(live.rooms_playing) || 0, ic: "matches", tone: "tile-accent", foot: h("a", { href: "#/rooms?status=playing", class: "tile-link" }, "View live rooms") }),
      tile({ label: "Members online", value: Number(live.members_online) || 0, ic: "players", foot: h("span", { class: "tile-sub" }, "Connected sockets in rooms") }));
    replace(todayRow,
      tile({ label: "Rooms created", value: Number(today.rooms) || 0, foot: foot("rooms", "Rooms created") }),
      tile({ label: "Matches", value: Number(today.matches) || 0, foot: foot("matches", "Matches") }),
      tile({ label: "Active players", value: Number(today.players_active) || 0, foot: foot("players_active", "Active players") }),
      tile({ label: "New players", value: Number(today.new_players) || 0, foot: h("span", { class: "tile-sub" }, "First seen today") }));

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

  load();
  const p = poll(() => load(), 15000);
  ctx.onCleanup(() => { p.stop(); chartEl?.destroy?.(); });
}
