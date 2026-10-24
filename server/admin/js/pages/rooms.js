// Rooms: status tabs, search by code / host, table. Quiet auto-refresh every 15 s on page 1.
import { h, timeEl, fmtInt, parseJson, poll } from "../dom.js";
import { api } from "../api.js";
import { dataTable } from "../table.js";
import { statusBadge, codeLink, pidLink } from "../ui.js";
import { pageHead, searchBox, tabs, filterBar } from "./common.js";

const STATUSES = [["lobby", "Lobby"], ["playing", "Playing"], ["over", "Over"], ["closed", "Closed"], ["all", "All"]];

export function settingsTags(settings) {
  const st = parseJson(settings, {}) || {};
  const tags = [];
  if (st.teams) tags.push(h("span", { class: "tag" }, "Teams"));
  if (st.pair_ask) tags.push(h("span", { class: "tag" }, "Ask pair"));
  return tags.length ? h("span", { class: "tags" }, tags) : h("span", { class: "muted" }, "Standard");
}

export function membersCell(r) {
  const n = Number(r.members) || 0;
  const on = Math.min(n, Number(r.online) || 0);
  const dots = [];
  for (let i = 0; i < 4; i++) dots.push(h("span", { class: "seat " + (i < on ? "seat-on" : i < n ? "seat-off" : "seat-empty"), "aria-hidden": "true" }));
  return h("span", { class: "members", title: `${on} online of ${n} members (max 4)` }, h("span", { class: "seats" }, dots),
    h("span", { class: "num-sm" }, fmtInt(on), h("span", { class: "muted" }, " / " + fmtInt(n))), h("span", { class: "sr-only" }, ` online of ${n}`));
}

export default function roomsPage(root, _params, ctx) {
  ctx.title("Rooms");
  const st0 = ctx.query.get("status");
  const state = { status: STATUSES.some(([v]) => v === st0) ? st0 : "all", q: ctx.query.get("q") || "" };
  const sync = () => {
    ctx.setQuery({ status: state.status === "all" ? "" : state.status, q: state.q });
    table.setParams({ status: state.status === "all" ? undefined : state.status, q: state.q || undefined });
  };
  const table = dataTable({
    caption: "Rooms",
    load: (p) => api.get("/rooms", p),
    rowHref: (r) => "#/rooms/" + encodeURIComponent(r.code),
    empty: ["No rooms match", "Rooms appear here as soon as someone creates one in the game."],
    columns: [
      { label: "Code", render: (r) => codeLink(r.code) },
      { label: "Status", render: (r) => statusBadge(r.status) },
      { label: "Host", cls: "col-main", render: (r) => h("div", { class: "host" }, h("span", null, r.host_name || "–"), r.host_pid ? pidLink(r.host_pid) : null) },
      { label: "Members", render: membersCell },
      { label: "Settings", render: (r) => settingsTags(r.settings) },
      { label: "Created", render: (r) => timeEl(r.created_at) },
      { label: "Updated", render: (r) => timeEl(r.updated_at) },
      { label: "Note", render: (r) => (r.closed_reason ? h("span", { class: "muted trunc", title: r.closed_reason }, r.closed_reason) : "") },
    ],
  });

  root.append(
    pageHead(null, "Friend rooms (one Durable Object each). Newest first."),
    filterBar(
      tabs({ value: state.status, options: STATUSES, label: "Room status", onChange: (v) => { state.status = v; sync(); } }),
      searchBox({ value: state.q, placeholder: "Code or host name", label: "Search rooms", onInput: (v) => { state.q = v; sync(); } })),
    h("section", { class: "card card-flush" }, table.el));
  sync();
  const p = poll(() => (table.page === 0 ? table.refresh() : null), 15000);
  ctx.onCleanup(() => p.stop());
}
