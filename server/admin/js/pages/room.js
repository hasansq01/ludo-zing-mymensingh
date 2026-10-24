// Room detail: D1 row, live Durable Object snapshot (members, settings, mini board, turn / dice / deadline),
// matches played here, kick and close. Refreshes every 3 s while the room is live.
import { h, replace, timeEl, fmtInt, parseJson, poll, tickTimes, shortId } from "../dom.js";
import { api, enc } from "../api.js";
import { icon } from "../icons.js";
import { createBoard, dieFace, GOAL } from "../board.js";
import {
  card, kv, badge, statusBadge, colorMark, COLORS, onlineDot, avatar, pidLink, copyBtn, openDialog, toast, toastErr,
  errorState, emptyState, skeletonBlock,
} from "../ui.js";
import { refreshButton, updatedLabel } from "./common.js";
import { matchColumns } from "./match_cells.js";
import { membersCell } from "./rooms.js";

const PHASE = { roll: "Rolling", choose: "Choosing a pawn", pair_ask: "Pair question", pick: "Single or pair", over: "Game over" };
const STEP_S = { roll: 15, choose: 20, pair_ask: 10, pick: 20 };

export default function roomPage(root, [codeRaw], ctx) {
  const code = String(codeRaw || "").toUpperCase();
  ctx.title("Room " + code, [["Rooms", "#/rooms"]]);
  const upd = updatedLabel(ctx, { live: false });
  const body = h("div", { class: "detail" }, skeletonBlock(3), h("div", { class: "grid-2-1" }, skeletonBlock(10), skeletonBlock(6)));
  root.appendChild(body);

  const board = createBoard({ label: "Board of room " + code });
  let built = null;
  let skew = 0;
  let deadline = 0;
  let phase = "";
  let poller = null;
  let lastRes = null;
  let failed = 0;
  let loading = false;
  let lastLoad = 0;

  async function load(manual = false) {
    if (loading && !manual) return;
    loading = true;
    lastLoad = Date.now();
    try {
      const t0 = Date.now();
      const res = await api.get("/rooms/" + enc(code));
      if (typeof res.now === "number") skew = res.now - Math.round((t0 + Date.now()) / 2);
      lastRes = res;
      failed = 0;
      render(res);
      upd.mark();
    } catch (err) {
      if (err.status === 401) return;
      failed++;
      if (!built) {
        replace(body, err.status === 404 ? emptyState("No room with this code", code + " is not in the database.", "rooms") : errorState(err, () => load(true)));
        return;
      }
      upd.stale();
      if (manual || failed === 1) toastErr(err, "Room");
    } finally {
      loading = false;
    }
  }

  function build() {
    const p = {
      heroBadges: h("div", { class: "hero-badges" }),
      heroMeta: h("div", { class: "hero-meta" }),
      closeBtn: h("button", { class: "btn btn-danger btn-sm", type: "button" }, icon("power", { size: 14 }), "Close room"),
      boardHost: h("div", { class: "board-wrap" }, board.el),
      boardOverlay: h("div", { class: "board-overlay", hidden: true }),
      turn: h("div", { class: "turn" }),
      seats: h("div", { class: "seats-list" }),
      members: h("div"),
      settings: h("div"),
      record: h("div"),
      matches: h("div"),
    };
    p.boardHost.appendChild(p.boardOverlay);
    p.closeBtn.addEventListener("click", closeRoom);
    const hero = h("section", { class: "hero hero-room" },
      h("div", { class: "room-code", "aria-label": "Room code " + code }, code, copyBtn(code, "Copy code")),
      h("div", { class: "hero-main" }, p.heroBadges, p.heroMeta),
      h("div", { class: "hero-actions" }, upd.el, refreshButton(() => load(true)), p.closeBtn));
    replace(body,
      hero,
      h("div", { class: "grid-room" },
        card("Board", h("div", { class: "board-card" }, p.boardHost, h("div", { class: "board-side" }, p.turn, p.seats)), { cls: "card-board", sub: "Live view of the match state on the server." }),
        h("div", { class: "stack" },
          card("Members", p.members),
          card("Settings", p.settings),
          card("Database record", p.record))),
      card("Matches in this room", p.matches, { cls: "card-flush" }));
    built = p;
  }

  function render(res) {
    if (!built) build();
    const p = built;
    const room = res.room || {};
    const live = res.live || null;
    const match = live?.match || null;
    const st = match?.state || null;
    const isLive = Boolean(live) && room.status !== "closed";
    upd.setLive(isLive);

    // hero
    replace(p.heroBadges, statusBadge(live?.status || room.status),
      isLive ? badge("Live", "ok") : badge("Not live", "muted"),
      live?.settings?.teams ? badge("Teams", "neutral") : null);
    replace(p.heroMeta,
      h("span", null, "Host ", h("strong", null, hostName(live, room)), " "),
      room.host_pid ? pidLink(room.host_pid) : null,
      h("span", null, "Created ", timeEl(room.created_at)),
      h("span", null, "Updated ", timeEl(room.updated_at)));
    p.closeBtn.disabled = room.status === "closed" && !live;

    // board
    board.update(st);
    if (!live) showOverlay("Not live", "The room's Durable Object no longer exists (deleted after inactivity or closed).");
    else if (!match) showOverlay(live.status === "over" ? "Match over" : "In the lobby", live.status === "over" ? "Waiting for the host to start a rematch." : "Waiting for the host to start the match.");
    else p.boardOverlay.hidden = true;
    renderTurn(match, st);
    renderSeats(match, st);

    // members
    const members = live?.members || [];
    if (!live) replace(p.members, h("p", { class: "muted pad" }, "No live snapshot. D1 last recorded ", membersCell(room), "."));
    else if (!members.length) replace(p.members, emptyState("Nobody here", "All members left.", "players"));
    else {
      replace(p.members, h("ul", { class: "mlist" }, members.map((m) => {
        const kick = h("button", { class: "btn btn-sm btn-ghost btn-ghost-danger", type: "button", "aria-label": "Kick " + (m.name || "member") }, icon("kick", { size: 14 }), "Kick");
        kick.addEventListener("click", () => kickMember(m, Boolean(match)));
        return h("li", { class: "mrow" },
          h("span", { class: "mrow-av" }, avatar(m.avatar, m.name, 32), h("span", { class: "mrow-dot" }, onlineDot(m.online))),
          h("div", { class: "mrow-main" },
            h("div", { class: "mrow-name" }, colorMark(m.color), h("span", null, m.name || "Player"),
              m.id === live.host ? h("span", { class: "tag tag-host", title: "Host" }, icon("crown", { size: 11 }), "host") : null),
            h("div", { class: "mrow-sub" }, m.pid ? pidLink(m.pid) : null, h("span", { class: "muted" }, " · member " + shortId(String(m.id ?? ""), 6)), h("span", { class: "muted" }, m.online ? " · online" : " · offline"))),
          kick);
      })));
    }

    // settings
    const sets = live?.settings || parseJson(room.settings, {}) || {};
    replace(p.settings, kv([
      ["Teams (2 v 2)", onOff(sets.teams)],
      ["Ask before pairing", onOff(sets.pair_ask)],
      ["Source", h("span", { class: "muted" }, live ? "live snapshot" : "database")],
    ]));

    // D1 record
    replace(p.record, kv([
      ["Status", statusBadge(room.status)],
      ["Members", membersCell(room)],
      ["Host", room.host_name || "–"],
      ["Created", timeEl(room.created_at)],
      ["Updated", timeEl(room.updated_at)],
      room.closed_reason ? ["Closed reason", room.closed_reason] : null,
    ]));

    // matches
    const ms = Array.isArray(res.matches) ? res.matches : [];
    const cols = matchColumns({ room: false });
    replace(p.matches, ms.length
      ? h("div", { class: "tbl-scroll" }, h("table", { class: "tbl" },
          h("thead", null, h("tr", null, cols.map((c) => h("th", { scope: "col", class: c.align === "right" ? "num" : "" }, c.label)))),
          h("tbody", null, ms.map((m) => h("tr", null, cols.map((c) => h("td", { class: (c.cls || "") + (c.align === "right" ? " num" : "") }, c.render(m))))))))
      : emptyState("No matches yet", "Matches started in this room show here.", "matches"));
    tickTimes(body);

    // poll while live
    if (isLive && !poller) poller = poll(() => load(), 3000);
    if (!isLive && poller) { poller.stop(); poller = null; }
  }

  function showOverlay(title, text) {
    replace(built.boardOverlay, h("div", { class: "overlay-card" }, h("strong", null, title), h("span", null, text)));
    built.boardOverlay.hidden = false;
  }

  function renderTurn(match, st) {
    const p = built;
    if (!match || !st) { replace(p.turn, h("p", { class: "muted" }, "No match in progress.")); deadline = 0; return; }
    const c = Number(st.turn);
    const seat = (match.seats || []).find((x) => x.color === c);
    const name = seat?.name || st.names?.[c] || COLORS[c];
    deadline = Number(match.deadline) || 0;
    phase = st.phase;
    const over = st.phase === "over";
    const cd = h("div", { class: "countdown" }, h("div", { class: "cd-top" }, h("span", { class: "cd-label" }, "Deadline"), h("span", { class: "cd-val", id: "cd-val" }, "–")),
      h("div", { class: "cd-bar", "aria-hidden": "true" }, h("span", { class: "cd-fill", id: "cd-fill" })));
    replace(p.turn,
      h("div", { class: "turn-who" },
        h("span", { class: "kicker" }, over ? "Winner" : "Turn"),
        h("div", { class: "turn-name" }, colorMark(over ? st.winner : c, { size: 14 }), h("strong", null, over ? winnerName(match, st) : name),
          !over && (seat?.bot || st.players?.[c] === "cpu") ? h("span", { class: "tag tag-bot" }, icon("bot", { size: 11 }), "bot") : null)),
      h("div", { class: "turn-grid" },
        h("div", { class: "turn-cell" }, h("span", { class: "kicker" }, "Dice"), dieFace(Number(st.dice) || 0, 36)),
        h("div", { class: "turn-cell" }, h("span", { class: "kicker" }, "Phase"), h("span", { class: "phase phase-" + st.phase }, PHASE[st.phase] || st.phase)),
        h("div", { class: "turn-cell" }, h("span", { class: "kicker" }, "Action"), h("span", { class: "big-num" }, "#" + fmtInt(match.n))),
        st.sixes ? h("div", { class: "turn-cell" }, h("span", { class: "kicker" }, "Sixes"), h("span", { class: "big-num" }, String(st.sixes))) : null),
      over ? null : cd);
    tick();
  }

  function winnerName(match, st) {
    const w = Number(st.winner);
    if (!(w >= 0)) return "–";
    const seat = (match.seats || []).find((x) => x.color === w);
    return seat?.name || st.names?.[w] || COLORS[w];
  }

  function renderSeats(match, st) {
    const p = built;
    if (!match || !st) { replace(p.seats); return; }
    const fin = Array.isArray(st.finished) ? st.finished : [];
    const rows = (match.seats || []).slice().sort((a, b) => a.color - b.color).map((seat) => {
      const c = seat.color;
      const toks = st.tok?.[c] || [];
      const home = toks.filter((t) => t >= GOAL).length;
      const prog = toks.reduce((a, t) => a + Math.max(0, t + 1), 0) / ((GOAL + 1) * 4);
      const place = fin.indexOf(c);
      const mode = st.players?.[c];
      return h("li", { class: "seat-row" + (st.turn === c && st.phase !== "over" ? " is-turn" : "") },
        colorMark(c, { size: 13 }),
        h("div", { class: "seat-main" },
          h("div", { class: "seat-name" }, h("span", null, seat.name || COLORS[c]),
            mode === "cpu" || seat.bot ? h("span", { class: "tag tag-bot" }, icon("bot", { size: 11 }), "bot") : null,
            seat.bot ? null : onlineDot(seat.online),
            place >= 0 ? h("span", { class: "tag tag-place" }, "#" + (place + 1)) : null),
          h("div", { class: "seat-prog", title: `${home} of 4 pawns home` },
            h("span", { class: "bar" }, h("span", { class: "bar-fill cm-bg-" + c, style: { width: Math.round(prog * 100) + "%" } })),
            h("span", { class: "muted num-sm" }, home + "/4 home"))));
    });
    replace(p.seats, h("span", { class: "kicker" }, "Seats"), h("ul", { class: "seat-ul" }, rows));
  }

  function tick() {
    const val = document.getElementById("cd-val");
    const fill = document.getElementById("cd-fill");
    if (!val || !fill) return;
    if (!deadline) { val.textContent = "–"; fill.style.width = "0%"; return; }
    const left = Math.max(0, deadline - (Date.now() + skew));
    const total = (STEP_S[phase] || 15) * 1000;
    val.textContent = left > 0 ? (left / 1000).toFixed(left < 10000 ? 1 : 0) + "s" : "due";
    // the step is due: fetch a little early instead of waiting for the next 3 s tick
    if (left <= 0 && poller && !document.hidden && Date.now() - lastLoad > 900) load();
    fill.style.width = Math.min(100, (left / total) * 100) + "%";
    val.classList.toggle("is-low", left < 5000);
    fill.classList.toggle("is-low", left < 5000);
  }
  const ticker = setInterval(tick, 200);

  function kickMember(m, inMatch) {
    openDialog({
      title: "Kick " + (m.name || "member") + "?",
      danger: true,
      confirmLabel: "Kick",
      body: [
        h("div", { class: "who who-box" }, avatar(m.avatar, m.name), h("div", { class: "who-text" }, h("strong", null, m.name || "Player"), h("span", { class: "who-sub mono" }, m.pid || ""))),
        h("p", null, inMatch
          ? "They are removed from room " + code + " and their socket is closed. Their seat becomes a bot for the rest of the match."
          : "They are removed from room " + code + " and their socket is closed. They can rejoin with the code unless banned."),
      ],
      onConfirm: () => api.post("/rooms/" + enc(code) + "/kick", { member_id: m.id }),
    }).then((ok) => { if (ok) { toast((m.name || "Member") + " kicked", "ok"); load(); } });
  }

  function closeRoom() {
    const reason = h("input", { class: "input", id: "close-reason", maxlength: 140, placeholder: "e.g. Reported for abuse", autocomplete: "off" });
    const confirmCode = h("input", { class: "input mono", id: "close-code", maxlength: 6, autocomplete: "off", spellcheck: "false", placeholder: code });
    const live = lastRes?.live;
    openDialog({
      title: "Close room " + code + "?",
      danger: true,
      confirmLabel: "Close room",
      body: [
        h("p", null, "Every connected player is disconnected and the room's storage is deleted.",
          live?.match ? " The match in progress ends as closed." : "", " This can't be undone."),
        h("label", { class: "label", for: "close-reason" }, "Reason ", h("span", { class: "muted" }, "(required, kept in the audit log)")),
        reason,
        h("label", { class: "label", for: "close-code" }, "Type ", h("code", null, code), " to confirm"),
        confirmCode,
      ],
      validate: () => (reason.value.trim().length < 3 ? "reason" : confirmCode.value.trim().toUpperCase() !== code ? "code" : ""),
      onConfirm: () => api.post("/rooms/" + enc(code) + "/close", { reason: reason.value.trim() }),
    }).then((ok) => { if (ok) { toast("Room " + code + " closed", "ok"); load(); } });
  }

  load();
  ctx.onCleanup(() => { clearInterval(ticker); poller?.stop(); });
}

function hostName(live, room) {
  if (live) {
    const m = (live.members || []).find((x) => x.id === live.host);
    if (m) return m.name || "Player";
  }
  return room.host_name || "–";
}

const onOff = (v) => (v ? h("span", { class: "on" }, icon("check", { size: 13 }), "On") : h("span", { class: "muted" }, "Off"));
