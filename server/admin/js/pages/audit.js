// Audit: admin_log rows (every state-changing admin call), newest first.
import { h, timeEl, absTime, parseJson } from "../dom.js";
import { api } from "../api.js";
import { dataTable } from "../table.js";
import { codeLink, pidLink, kv, badge } from "../ui.js";
import { pageHead } from "./common.js";

const TONE = { ban: "danger", close: "danger", kick: "warn", unban: "ok", login: "info", logout: "muted", config: "warn", note: "neutral", login_failed: "danger" };

function actionBadge(a) {
  const key = String(a || "").split(/[._:/ ]/).pop();
  const b = badge(a || "–", TONE[key] || TONE[a] || "neutral");
  b.classList.add("badge-raw");
  return b;
}

function targetCell(r) {
  const t = r.target || "";
  if (!t) return h("span", { class: "muted" }, "–");
  const [kind, rest] = t.includes(":") ? [t.slice(0, t.indexOf(":")), t.slice(t.indexOf(":") + 1)] : ["", t];
  const a = String(r.action || "");
  if (kind === "room" || (!kind && a.startsWith("room"))) return codeLink(rest);
  if (kind === "player" || (!kind && a.startsWith("player"))) return pidLink(rest);
  return h("span", { class: "mono" }, t);
}

function prettyDetail(d) {
  if (d === null || d === undefined || d === "") return "(no detail)";
  const j = parseJson(d, null);
  return j !== null && typeof j === "object" ? JSON.stringify(j, null, 2) : String(d);
}

export default function auditPage(root, _params, ctx) {
  ctx.title("Audit");
  const table = dataTable({
    caption: "Admin audit log",
    dense: true,
    load: (p) => api.get("/audit", p),
    empty: ["No admin actions yet", "Sign-ins, bans, kicks, closes and config changes are recorded here."],
    expand: (r) => h("div", { class: "ev-detail" }, h("pre", { class: "pre" }, prettyDetail(r.detail)),
      kv([["Log id", h("span", { class: "mono" }, String(r.id ?? "–"))], ["At", absTime(r.at)], ["IP", h("span", { class: "mono" }, r.ip || "–")]])),
    columns: [
      { label: "Time", render: (r) => timeEl(r.at) },
      { label: "Action", render: (r) => actionBadge(r.action) },
      { label: "Target", render: targetCell },
      { label: "IP", render: (r) => h("span", { class: "mono muted" }, r.ip || "–") },
      { label: "Detail", cls: "col-main", render: (r) => h("span", { class: "trunc trunc-wide mono-sm", title: typeof r.detail === "string" ? r.detail : JSON.stringify(r.detail ?? "") }, typeof r.detail === "string" ? r.detail : r.detail ? JSON.stringify(r.detail) : "") },
    ],
  });
  root.append(pageHead(null, "Every state-changing admin call, with the caller's IP. Newest first."), h("section", { class: "card card-flush" }, table.el));
  table.setParams({});
}
