// Matches: filter by room code, player pid and result.
import { h } from "../dom.js";
import { api } from "../api.js";
import { dataTable } from "../table.js";
import { pageHead, textFilter, selectFilter, filterBar } from "./common.js";
import { matchColumns } from "./match_cells.js";

const RESULTS = [["", "Any result"], ["playing", "Playing"], ["over", "Finished"], ["abandoned", "Abandoned"], ["closed", "Closed"]];

export default function matchesPage(root, _params, ctx) {
  ctx.title("Matches");
  const state = { code: (ctx.query.get("code") || "").toUpperCase(), pid: ctx.query.get("pid") || "", result: ctx.query.get("result") || "" };
  const sync = () => {
    ctx.setQuery(state);
    table.setParams({ code: state.code || undefined, pid: state.pid || undefined, result: state.result || undefined });
    clearBtn.hidden = !(state.code || state.pid || state.result);
  };
  const table = dataTable({
    caption: "Matches",
    load: (p) => api.get("/matches", p),
    empty: ["No matches found", "Matches are recorded when a host starts a game."],
    columns: matchColumns(),
  });
  const codeIn = textFilter({ value: state.code, placeholder: "Room code", label: "Filter by room code", mono: true, onInput: (v) => { state.code = v.toUpperCase(); sync(); } });
  codeIn.maxLength = 6;
  codeIn.classList.add("w-code");
  const pidIn = textFilter({ value: state.pid, placeholder: "Player pid", label: "Filter by player pid", mono: true, onInput: (v) => { state.pid = v; sync(); } });
  const resSel = selectFilter({ value: state.result, options: RESULTS, label: "Filter by result", onChange: (v) => { state.result = v; sync(); } });
  const clearBtn = h("button", { class: "btn btn-sm btn-ghost", type: "button" }, "Clear filters");
  clearBtn.addEventListener("click", () => {
    state.code = ""; state.pid = ""; state.result = "";
    codeIn.value = ""; pidIn.value = ""; resSel.value = "";
    sync();
  });
  root.append(
    pageHead(null, "Every match started on the server. Newest first."),
    filterBar(codeIn, pidIn, resSel, clearBtn),
    h("section", { class: "card card-flush" }, table.el));
  sync();
}
