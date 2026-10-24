// Players: search (name or pid prefix), banned filter, cursor-paginated table.
import { h, timeEl, fmtInt, shortId } from "../dom.js";
import { api } from "../api.js";
import { dataTable } from "../table.js";
import { avatar, badge, copyBtn } from "../ui.js";
import { pageHead, searchBox, toggleChip, filterBar } from "./common.js";

export function winRate(wins, games) {
  const g = Number(games) || 0;
  const w = Number(wins) || 0;
  if (!g) return h("span", { class: "muted" }, "–");
  const p = Math.round((w / g) * 100);
  return h("span", { class: "rate" }, h("span", { class: "rate-bar", "aria-hidden": "true" }, h("span", { class: "rate-fill", style: { width: p + "%" } })), h("span", { class: "rate-num" }, p + "%"));
}

export default function playersPage(root, _params, ctx) {
  ctx.title("Players");
  const state = { q: ctx.query.get("q") || "", banned: ctx.query.get("banned") === "1" };
  const sync = () => { ctx.setQuery({ q: state.q, banned: state.banned }); table.setParams({ q: state.q, banned: state.banned ? 1 : undefined }); };

  const table = dataTable({
    caption: "Players",
    load: (p) => api.get("/players", p),
    rowHref: (p) => "#/players/" + encodeURIComponent(p.pid),
    empty: ["No players found", "Try another name or pid prefix, or clear the filters."],
    columns: [
      { label: "Player", cls: "col-main", render: (p) => h("div", { class: "who" }, avatar(p.avatar, p.name),
        h("div", { class: "who-text" }, h("a", { href: "#/players/" + encodeURIComponent(p.pid), class: "who-name" }, p.name || "Player"),
          h("span", { class: "who-sub mono" }, p.avatar || "no avatar"))) },
      { label: "PID", render: (p) => h("span", { class: "pid" }, h("span", { class: "mono", title: p.pid }, shortId(p.pid, 10)), copyBtn(p.pid, "Copy pid")) },
      { label: "Games", align: "right", render: (p) => fmtInt(p.matches) },
      { label: "Wins", align: "right", render: (p) => fmtInt(p.wins) },
      { label: "Win rate", cls: "col-rate", render: (p) => winRate(p.wins, p.matches) },
      { label: "Rooms", align: "right", render: (p) => fmtInt(p.rooms) },
      { label: "Last seen", render: (p) => timeEl(p.last_seen, { empty: "never" }) },
      { label: "Status", render: (p) => (Number(p.banned) ? h("span", { title: p.ban_reason || "" }, badge("Banned", "danger", "ban")) : h("span", { class: "muted" }, "Active")) },
    ],
  });

  root.append(
    pageHead(null, "Everyone who has joined a room. Most recently seen first."),
    filterBar(
      searchBox({ value: state.q, placeholder: "Search name or pid prefix", label: "Search players", width: "w-wide", onInput: (v) => { state.q = v; sync(); } }),
      toggleChip({ pressed: state.banned, text: "Banned only", tone: "danger", onChange: (v) => { state.banned = v; sync(); } })),
    h("section", { class: "card card-flush" }, table.el));
  sync();
}
