// Cells shared by every match table (Matches, player detail, room detail).
import { h, parseJson, duration, fmtInt, timeEl } from "../dom.js";
import { icon } from "../icons.js";
import { colorMark, COLORS, badge, resultBadge, codeLink, ghostTag } from "../ui.js";

export const matchPlayers = (m) => {
  const p = parseJson(m.players, []);
  return Array.isArray(p) ? p.slice().sort((a, b) => a.color - b.color) : [];
};

export function isWinner(m, color) {
  const w = Number(m.winner);
  if (!(w >= 0)) return false;
  return w === color || (Number(m.teams) ? (w + 2) % 4 === color : false);
}

export function playersCell(m) {
  const ps = matchPlayers(m);
  if (!ps.length) return h("span", { class: "muted" }, "–");
  return h("ul", { class: "mplayers" }, ps.map((p) => h("li", { class: isWinner(m, p.color) ? "is-win" : "" },
    colorMark(p.color),
    p.bot || p.ghost || !p.pid ? h("span", { class: "mp-name" }, p.name || COLORS[p.color]) : h("a", { href: "#/players/" + encodeURIComponent(p.pid), class: "mp-name link" }, p.name || "Player"),
    p.bot ? h("span", { class: "tag tag-bot", title: "Bot" }, icon("bot", { size: 11 }), "bot") : null,
    p.ghost ? ghostTag() : null)));
}

export function winnerCell(m) {
  const w = Number(m.winner);
  if (!(w >= 0 && w <= 3)) return h("span", { class: "muted" }, m.result === "playing" ? "in progress" : "–");
  const ps = matchPlayers(m);
  const names = ps.filter((p) => isWinner(m, p.color)).map((p) => p.name || COLORS[p.color]);
  return h("span", { class: "clabel" }, icon("crown", { size: 13, cls: "crown" }), colorMark(w), h("span", null, names.join(" + ") || COLORS[w]));
}

export function durationCell(m, now = Date.now()) {
  if (!m.started_at) return "–";
  if (!m.ended_at) return m.result === "playing" ? h("span", { class: "running" }, duration(now - m.started_at)) : h("span", { class: "muted" }, "–");
  return duration(m.ended_at - m.started_at);
}

export function modeTags(m) {
  return [Number(m.teams) ? h("span", { class: "tag" }, "Teams") : null, Number(m.pair_ask) ? h("span", { class: "tag" }, "Ask pair") : null];
}

/** Standard columns; opts.room = false hides the room column, opts.forPid adds an outcome column. */
export function matchColumns({ room = true, forPid = null } = {}) {
  const cols = [
    { label: "Started", render: (m) => timeEl(m.started_at) },
    room ? { label: "Room", render: (m) => codeLink(m.code) } : null,
    { label: "Players", cls: "col-main", render: (m) => h("div", { class: "mp-wrap" }, playersCell(m), h("div", { class: "mp-tags" }, modeTags(m))) },
    forPid ? { label: "Outcome", render: (m) => outcomeFor(m, forPid) } : { label: "Winner", render: winnerCell },
    { label: "Duration", align: "right", render: (m) => durationCell(m) },
    { label: "Actions", align: "right", render: (m) => (m.result === "playing" && !m.actions ? h("span", { class: "muted" }, "–") : fmtInt(m.actions)) },
    { label: "Result", render: (m) => resultBadge(m.result) },
  ];
  return cols.filter(Boolean);
}

export function outcomeFor(m, pid) {
  const me = matchPlayers(m).find((p) => p.pid === pid);
  if (m.result === "playing") return badge("playing", "ok");
  if (!me) return h("span", { class: "muted" }, "–");
  if (m.result !== "over") return h("span", { class: "muted" }, "no result");
  const fin = parseJson(m.finished, []);
  const place = Array.isArray(fin) ? fin.indexOf(me.color) : -1;
  if (isWinner(m, me.color)) return badge("Won", "ok", "crown");
  return h("span", { class: "muted" }, place >= 0 ? "Lost · #" + (place + 1) : "Lost");
}
