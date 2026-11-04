// Events: level chips, kind filter, expandable messages.
import { h, timeEl, absTime } from "../dom.js";
import { api } from "../api.js";
import { dataTable } from "../table.js";
import { levelBadge, codeLink, pidLink, kv } from "../ui.js";
import { pageHead, textFilter, chipGroup, filterBar } from "./common.js";

const LEVELS = [["", "All levels"], ["info", "Info", "info"], ["warn", "Warn", "warn"], ["error", "Error", "danger"]];

export default function eventsPage(root, _params, ctx) {
  ctx.title("Events");
  const lv = ctx.query.get("level") || "";
  const state = { level: LEVELS.some(([v]) => v === lv) ? lv : "", kind: ctx.query.get("kind") || "" };
  const kinds = new Set();
  const dl = h("datalist", { id: "event-kinds" });
  const sync = () => { ctx.setQuery(state); table.setParams({ level: state.level || undefined, kind: state.kind || undefined }); };
  const table = dataTable({
    caption: "Events",
    dense: true,
    load: (p) => api.get("/events", p),
    empty: ["No events", "Errors and warnings from the room server are logged here (kept 30 days)."],
    onData: (items) => {
      for (const e of items) if (e.kind && !kinds.has(e.kind)) { kinds.add(e.kind); dl.appendChild(h("option", { value: e.kind })); }
    },
    expand: (e) => h("div", { class: "ev-detail" },
      h("pre", { class: "pre" }, e.msg || "(no message)"),
      kv([["Event id", h("span", { class: "mono" }, String(e.id ?? "–"))], ["At", absTime(e.at)], ["Kind", h("span", { class: "mono" }, e.kind || "–")],
        ["Room", codeLink(e.code)], ["Player", e.pid ? pidLink(e.pid, e.pid) : "–"]])),
    columns: [
      { label: "Time", render: (e) => timeEl(e.at) },
      { label: "Level", render: (e) => levelBadge(e.level) },
      { label: "Kind", render: (e) => h("span", { class: "mono" }, e.kind || "–") },
      { label: "Room", render: (e) => codeLink(e.code) },
      { label: "Player", render: (e) => pidLink(e.pid) },
      { label: "Message", cls: "col-main", render: (e) => h("span", { class: "trunc trunc-wide", title: e.msg || "" }, e.msg || "") },
    ],
  });
  const kindIn = textFilter({ value: state.kind, placeholder: "Kind, e.g. storage_failed", label: "Filter by kind", mono: true, list: "event-kinds", onInput: (v) => { state.kind = v; sync(); } });
  kindIn.classList.add("w-kind");
  root.append(
    pageHead(null, "Server-side warnings, errors and notable info, newest first."),
    filterBar(chipGroup({ value: state.level, options: LEVELS, label: "Level", onChange: (v) => { state.level = v; sync(); } }), kindIn, dl),
    h("section", { class: "card card-flush" }, table.el));
  sync();
}
