// Player detail: profile, stats, recent matches, admin note, ban / unban.
import { h, replace, timeEl, fmtInt, absTime, tickTimes } from "../dom.js";
import { api, enc } from "../api.js";
import { icon } from "../icons.js";
import { avatar, badge, card, copyBtn, kv, openDialog, toast, toastErr, errorState, skeletonBlock, emptyState } from "../ui.js";
import { tile } from "./common.js";
import { matchColumns } from "./match_cells.js";

const NOTE_MAX = 500;
const REASON_MAX = 200;

export default function playerPage(root, [pid], ctx) {
  ctx.title("Player", [["Players", "#/players"]]);
  const body = h("div", { class: "detail" }, skeletonBlock(3), skeletonBlock(6));
  root.appendChild(body);
  let player = null;

  async function load() {
    try {
      const res = await api.get("/players/" + enc(pid));
      player = res.player;
      render(res);
    } catch (err) {
      if (err.status === 401) return;
      replace(body, err.status === 404 ? emptyState("No player with this id", pid, "players") : errorState(err, load));
    }
  }

  function render({ player: p, matches = [] }) {
    const banned = Boolean(Number(p.banned));
    ctx.title(p.name || "Player", [["Players", "#/players"]]);
    const games = Number(p.matches) || 0;
    const wins = Number(p.wins) || 0;

    const hero = h("section", { class: "hero" },
      avatar(p.avatar, p.name, 56),
      h("div", { class: "hero-main" },
        h("div", { class: "hero-title" }, h("h2", null, p.name || "Player"), banned ? badge("Banned", "danger", "ban") : badge("Active", "ok")),
        h("div", { class: "hero-meta" },
          h("span", { class: "pid" }, h("span", { class: "mono" }, p.pid), copyBtn(p.pid, "Copy pid")),
          h("span", null, "Avatar ", h("span", { class: "mono" }, p.avatar || "–")),
          p.frame ? h("span", null, "Frame ", h("span", { class: "mono" }, p.frame)) : null)),
      h("div", { class: "hero-actions" },
        h("a", { class: "btn btn-sm", href: "#/matches?pid=" + enc(p.pid) }, icon("matches", { size: 14 }), "All matches")));

    const tiles = h("div", { class: "tiles tiles-4" },
      tile({ label: "Games played", value: games }),
      tile({ label: "Wins", value: wins }),
      tile({ label: "Win rate", value: games ? Math.round((wins / games) * 100) + "%" : "–" }),
      tile({ label: "Rooms joined", value: Number(p.rooms) || 0 }));

    const cols = matchColumns({ forPid: p.pid });
    const mt = matches.length
      ? h("div", { class: "tbl-scroll" }, h("table", { class: "tbl" },
          h("thead", null, h("tr", null, cols.map((c) => h("th", { scope: "col", class: c.align === "right" ? "num" : "" }, c.label)))),
          h("tbody", null, matches.map((m) => h("tr", null, cols.map((c) => h("td", { class: (c.cls || "") + (c.align === "right" ? " num" : "") }, c.render(m))))))))
      : emptyState("No matches yet", "Finished and live matches this player took part in show here.", "matches");

    replace(body,
      hero,
      tiles,
      h("div", { class: "grid-2-1" },
        card("Recent matches", mt, { cls: "card-flush", sub: "Last 20, newest first." }),
        h("div", { class: "stack" },
          card("Profile", kv([
            ["First seen", h("span", { title: absTime(p.first_seen) }, timeEl(p.first_seen))],
            ["Last seen", timeEl(p.last_seen)],
            ["Rooms joined", fmtInt(p.rooms)],
            banned ? ["Ban reason", h("span", { class: "danger-text" }, p.ban_reason || "No reason given")] : null,
          ])),
          noteCard(p),
          moderationCard(p, banned))));
    tickTimes(body);
  }

  function noteCard(p) {
    const saved = { v: p.note || "" };
    const ta = h("textarea", { class: "input textarea", rows: 4, maxlength: NOTE_MAX, value: saved.v, "aria-label": "Admin note", placeholder: "Private note for admins (never shown to the player)" });
    const count = h("span", { class: "counter" });
    const status = h("span", { class: "save-status", "aria-live": "polite" });
    const save = h("button", { class: "btn btn-sm btn-primary", type: "button", disabled: true }, "Save note");
    const revert = h("button", { class: "btn btn-sm btn-ghost", type: "button", disabled: true }, "Revert");
    const upd = () => {
      count.textContent = `${ta.value.length} / ${NOTE_MAX}`;
      const dirty = ta.value !== saved.v;
      save.disabled = !dirty;
      revert.disabled = !dirty;
      if (dirty) status.textContent = "Unsaved changes";
    };
    ta.addEventListener("input", upd);
    revert.addEventListener("click", () => { ta.value = saved.v; status.textContent = ""; upd(); });
    save.addEventListener("click", async () => {
      save.disabled = true;
      save.classList.add("is-busy");
      try {
        await api.patch("/players/" + enc(p.pid), { note: ta.value });
        saved.v = ta.value;
        status.textContent = "Saved";
        toast("Note saved", "ok", 2000);
      } catch (err) {
        toastErr(err, "Note");
      } finally {
        save.classList.remove("is-busy");
        upd();
        if (ta.value === saved.v) status.textContent = "Saved";
      }
    });
    upd();
    status.textContent = "";
    return card("Admin note", h("div", { class: "note" }, ta, h("div", { class: "note-foot" }, count, status, h("span", { class: "spacer" }), revert, save)), { sub: "Visible to admins only." });
  }

  function moderationCard(p, banned) {
    if (banned) {
      const btn = h("button", { class: "btn", type: "button" }, icon("check", { size: 15 }), "Unban player");
      btn.addEventListener("click", async () => {
        const ok = await openDialog({
          title: "Unban " + (p.name || "player") + "?",
          body: [h("p", null, "They can join and create rooms again right away."), p.ban_reason ? h("p", { class: "muted" }, "Ban reason: ", p.ban_reason) : null],
          confirmLabel: "Unban",
          onConfirm: () => api.post("/players/" + enc(p.pid) + "/unban"),
        });
        if (ok) { toast((p.name || "Player") + " unbanned", "ok"); load(); }
      });
      return card("Moderation", h("div", { class: "mod" }, h("p", null, "This player is banned: the server refuses their ", h("code", null, "hello"), " with ", h("code", null, "banned"), "."), btn));
    }
    const btn = h("button", { class: "btn btn-danger", type: "button" }, icon("ban", { size: 15 }), "Ban player");
    btn.addEventListener("click", async () => {
      const reason = h("textarea", { class: "input textarea", rows: 3, maxlength: REASON_MAX, id: "ban-reason", placeholder: "e.g. Abusive name, repeated reports", required: true });
      const count = h("span", { class: "counter" }, `0 / ${REASON_MAX}`);
      reason.addEventListener("input", () => { count.textContent = `${reason.value.length} / ${REASON_MAX}`; });
      const ok = await openDialog({
        title: "Ban " + (p.name || "player") + "?",
        danger: true,
        confirmLabel: "Ban player",
        body: [
          h("p", null, "The player is disconnected from any live room they are in (their seat becomes a bot) and can't join rooms until unbanned."),
          h("div", { class: "who who-box" }, avatar(p.avatar, p.name), h("div", { class: "who-text" }, h("strong", null, p.name || "Player"), h("span", { class: "who-sub mono" }, p.pid))),
          h("label", { class: "label", for: "ban-reason" }, "Reason ", h("span", { class: "muted" }, "(required, kept in the audit log)")),
          reason, h("div", { class: "field-foot" }, count),
        ],
        validate: () => (reason.value.trim().length < 3 ? "reason" : ""),
        onConfirm: () => api.post("/players/" + enc(p.pid) + "/ban", { reason: reason.value.trim() }),
      });
      if (ok) { toast((p.name || "Player") + " banned", "ok"); load(); }
    });
    return card("Moderation", h("div", { class: "mod" }, h("p", null, "Banning blocks this pid from every room. It can be undone."), btn), { cls: "card-danger" });
  }

  load();
  ctx.onCleanup(() => { player = null; });
}
