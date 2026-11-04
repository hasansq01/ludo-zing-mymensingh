// Accounts: search (name, account id prefix, device pid prefix, Google id, LZM- id), banned / Google filters, cursor paging.
import { h, timeEl, fmtInt } from "../dom.js";
import { api } from "../api.js";
import { dataTable } from "../table.js";
import { badge } from "../ui.js";
import { pageHead, searchBox, toggleChip, chipGroup, filterBar } from "./common.js";
import { accountWho, accountIdCell, googleBadge } from "./account_cells.js";

const LINKED = [["", "All"], ["1", "Google-linked"], ["0", "Guests"]];

export default function accountsPage(root, _params, ctx) {
  ctx.title("Accounts");
  const l0 = ctx.query.get("linked");
  const state = { q: ctx.query.get("q") || "", banned: ctx.query.get("banned") === "1", linked: l0 === "1" || l0 === "0" ? l0 : "" };
  const sync = () => {
    ctx.setQuery({ q: state.q, banned: state.banned, linked: state.linked });
    table.setParams({ q: state.q || undefined, banned: state.banned ? 1 : undefined, linked: state.linked || undefined });
  };

  const table = dataTable({
    caption: "Accounts",
    load: (p) => api.get("/accounts", p),
    rowHref: (a) => "#/accounts/" + encodeURIComponent(a.id),
    empty: ["No accounts found", "Try a name, an account id, a device pid, an LZM- id, or clear the filters."],
    columns: [
      { label: "Account", cls: "col-main", render: (a) => accountWho(a) },
      { label: "Account id", render: (a) => accountIdCell(a.id) },
      { label: "Sign-in", render: (a) => googleBadge(a) },
      { label: "Level", align: "right", render: (a) => fmtInt(a.level) },
      { label: "Coins", align: "right", render: (a) => fmtInt(a.coins) },
      { label: "Online wins", align: "right", render: (a) => fmtInt(a.online_wins) },
      { label: "Matches", align: "right", render: (a) => fmtInt(a.completed_matches) },
      { label: "Last seen", render: (a) => timeEl(a.last_seen, { empty: "never" }) },
      { label: "Status", render: (a) => (Number(a.banned) ? h("span", { title: a.ban_reason || "" }, badge("Banned", "danger", "ban")) : h("span", { class: "muted" }, "Active")) },
    ],
  });

  root.append(
    pageHead(null, "Online accounts (guest or Google-linked). Most recently seen first."),
    filterBar(
      searchBox({ value: state.q, placeholder: "Name, account id, pid, LZM- id", label: "Search accounts", width: "w-wide", onInput: (v) => { state.q = v; sync(); } }),
      chipGroup({ value: state.linked, options: LINKED, label: "Sign-in type", onChange: (v) => { state.linked = v; sync(); } }),
      toggleChip({ pressed: state.banned, text: "Banned only", tone: "danger", onChange: (v) => { state.banned = v; sync(); } })),
    h("section", { class: "card card-flush" }, table.el));
  sync();
}
