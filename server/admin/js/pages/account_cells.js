// Cells shared by the v2 pages (Accounts, Account detail, Leaderboards).
import { h, fmtInt } from "../dom.js";
import { avatar, badge, accountLink, copyBtn } from "../ui.js";

/** Name + avatar (+ the game's public id underneath). */
export function accountWho(a, { href = true } = {}) {
  const name = a.name || "Player";
  return h("div", { class: "who" }, avatar(a.avatar, name),
    h("div", { class: "who-text" },
      href && a.id ? h("a", { href: "#/accounts/" + encodeURIComponent(a.id), class: "who-name" }, name) : h("span", { class: "who-name" }, name),
      h("span", { class: "who-sub mono" }, a.public_id || a.avatar || "no avatar")));
}

export const accountIdCell = (id) => h("span", { class: "pid" }, accountLink(id, id ? id.slice(0, 12) + "…" : ""), id ? copyBtn(id, "Copy account id") : null);

export const googleBadge = (a) => (a.linked || a.google_player_id
  ? badge("Google", "info", "link")
  : h("span", { class: "muted", title: "Guest account: not linked to Google Play Games" }, "Guest"));

export const bannedBadge = (a) => (Number(a.banned) ? h("span", { title: a.ban_reason || "" }, badge("Banned", "danger", "ban")) : null);

/** A plain (non-paginated) table from columns [{label, render, align, cls}] and rows. */
export function simpleTable(columns, rows, { caption = "", rowClass = null } = {}) {
  return h("div", { class: "tbl-scroll" }, h("table", { class: "tbl tbl-dense" },
    caption ? h("caption", { class: "sr-only" }, caption) : null,
    h("thead", null, h("tr", null, columns.map((c) => h("th", { scope: "col", class: (c.cls || "") + (c.align === "right" ? " num" : "") }, c.label)))),
    h("tbody", null, rows.map((r) => h("tr", { class: rowClass ? rowClass(r) || "" : "" },
      columns.map((c) => {
        let v;
        try { v = c.render(r); } catch { v = "–"; }
        return h("td", { class: (c.cls || "") + (c.align === "right" ? " num" : "") }, v);
      }))))));
}

export const pctText = (r) => (r === null || r === undefined ? "–" : Math.round(Number(r) * 100) + "%");
export const intOrDash = (n) => (n === null || n === undefined ? "–" : fmtInt(n));
