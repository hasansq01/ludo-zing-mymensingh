// Account detail: profile, devices, ledger, claims, rewards, matches, note, Adjust coins, ban / unban with its source.
import { h, replace, timeEl, fmtInt, absTime, tickTimes, shortId } from "../dom.js";
import { api, enc } from "../api.js";
import { icon } from "../icons.js";
import { avatar, badge, card, copyBtn, kv, openDialog, toast, toastErr, errorState, skeletonBlock, emptyState, pidLink, delta } from "../ui.js";
import { tile } from "./common.js";
import { matchColumns } from "./match_cells.js";
import { simpleTable, googleBadge } from "./account_cells.js";

const NOTE_MAX = 500;
const REASON_MAX = 200;
const ADJUST_MAX = 1000000;

/** What a ban's source means (ADMIN_API.md "Ban sources"). */
function banSourceText(src) {
  if (!src) return "unknown source";
  if (src === "admin_account") return h("span", null, "banned here, from the Accounts page");
  if (src.startsWith("pid:")) return h("span", null, "caused by the ban of device ", pidLink(src.slice(4)), " on the Players page");
  return h("span", { class: "mono" }, src);
}

function jsonPeek(v) {
  if (v === null || v === undefined || (typeof v === "object" && !Object.keys(v).length)) return h("span", { class: "muted" }, "–");
  let txt;
  try { txt = JSON.stringify(v, null, 2); } catch { txt = String(v); }
  return h("details", { class: "json-peek" }, h("summary", null, "payload"), h("pre", null, txt));
}

export default function accountPage(root, [id], ctx) {
  ctx.title("Account", [["Accounts", "#/accounts"]]);
  const body = h("div", { class: "detail" }, skeletonBlock(3), skeletonBlock(6));
  root.appendChild(body);
  let notice = null; // a one-off message after an action (e.g. pid bans that stay after an unban)

  async function load() {
    try {
      const res = await api.get("/accounts/" + enc(id));
      render(res);
    } catch (err) {
      if (err.status === 401) return;
      replace(body, err.status === 404 ? emptyState("No account with this id", id, "accounts") : errorState(err, load));
    }
  }

  function render({ account: a, devices = [], ledger = [], claims = [], grants = [], matches = [] }) {
    const banned = Boolean(Number(a.banned));
    const name = a.name || "Player";
    ctx.title(name, [["Accounts", "#/accounts"]]);
    const stats = a.stats || {};

    const hero = h("section", { class: "hero" },
      avatar(a.avatar, name, 56),
      h("div", { class: "hero-main" },
        h("div", { class: "hero-title" }, h("h2", null, name), banned ? badge("Banned", "danger", "ban") : badge("Active", "ok"), googleBadge(a),
          a.merged_into ? badge("Merged", "muted") : null),
        h("div", { class: "hero-meta" },
          h("span", { class: "pid" }, h("span", { class: "mono" }, a.id), copyBtn(a.id, "Copy account id")),
          a.public_id ? h("span", null, "Public id ", h("span", { class: "mono" }, a.public_id)) : null,
          a.avatar ? h("span", null, "Avatar ", h("span", { class: "mono" }, a.avatar)) : null)),
      h("div", { class: "hero-actions" }, adjustButton(a), adjustButton(a, "gems")));

    const tiles = h("div", { class: "tiles tiles-6" },
      tile({ label: "Level", value: Number(a.level) || 0, foot: h("span", { class: "tile-sub" }, fmtInt(a.xp) + " XP") }),
      tile({ label: "Coins", value: Number(a.coins) || 0, ic: "coin", tone: "tile-accent" }),
      tile({ label: "Gems", value: Number(a.gems) || 0, ic: "gem", foot: h("span", { class: "tile-sub" }, fmtInt(a.rerolls || 0) + " free re-roll" + (Number(a.rerolls) === 1 ? "" : "s")) }),
      tile({ label: "Online wins", value: Number(a.online_wins) || 0 }),
      tile({ label: "Completed matches", value: Number(a.completed_matches) || 0, foot: h("span", { class: "tile-sub" }, "Leaderboards need 3") }),
      tile({ label: "Devices", value: devices.length }));

    const ledgerCard = card("Recent ledger", ledger.length
      ? simpleTable([
        { label: "When", render: (r) => timeEl(r.at) },
        { label: "Coins", align: "right", render: (r) => delta(r.delta_coins) },
        { label: "Gems", align: "right", render: (r) => delta(r.delta_gems || 0) },
        { label: "XP", align: "right", render: (r) => delta(r.delta_xp) },
        { label: "Reason", render: (r) => h("span", { class: "tag" }, r.reason || "–") },
        { label: "Ref", cls: "ref", render: (r) => (r.ref ? h("span", { class: "mono trunc", title: r.ref }, r.ref) : h("span", { class: "muted" }, "–")) },
        { label: "Balance after", align: "right", render: (r) => fmtInt(r.balance_after) },
        { label: "Gems after", align: "right", render: (r) => (r.gems_after === null || r.gems_after === undefined ? "–" : fmtInt(r.gems_after)) },
      ], ledger, { caption: "Ledger" })
      : emptyState("No ledger rows", "Every coin / XP change of the account is recorded here.", "table"),
    { cls: "card-flush", sub: "Last 50, newest first. The coins and gems columns sum to the balances." });

    const claimsCard = card("Claims", claims.length
      ? simpleTable([
        { label: "When", render: (r) => timeEl(r.at) },
        { label: "Game", render: (r) => r.game || "–" },
        { label: "Mode", render: (r) => r.mode || "–" },
        { label: "Coins", align: "right", render: (r) => delta(r.coins) },
        { label: "XP", align: "right", render: (r) => delta(r.xp) },
        { label: "Result", render: (r) => (Number(r.limited) ? badge("Limited", "warn", "alert") : Number(r.granted) ? badge("Granted", "ok") : badge("Not granted", "muted")) },
        { label: "Reason", render: (r) => (r.reason ? h("span", { class: "muted" }, r.reason) : "") },
        { label: "Payload", render: (r) => jsonPeek(r.payload) },
      ], claims, { caption: "Claims", rowClass: (r) => (Number(r.limited) ? "row-limited" : "") })
      : emptyState("No claims", "Client reward claims (matches, achievements) appear here.", "check"),
    { cls: "card-flush", sub: "Last 50. Rows over the daily limit are highlighted." });

    const grantsCard = card("Match rewards", grants.length
      ? simpleTable([
        { label: "When", render: (r) => timeEl(r.at) },
        { label: "Match", render: (r) => h("span", { class: "mono", title: r.match_id }, shortId(String(r.match_id), 14)) },
        { label: "Game", render: (r) => r.game || "–" },
        { label: "Outcome", render: (r) => r.outcome || "–" },
        { label: "Coins", align: "right", render: (r) => delta(r.coins) },
        { label: "XP", align: "right", render: (r) => delta(r.xp) },
      ], grants, { caption: "Match rewards" })
      : emptyState("No match rewards", "", "matches"),
    { cls: "card-flush", sub: "Last 20 online matches that paid out." });

    const cols = matchColumns();
    const matchesCard = card("Recent matches", matches.length
      ? h("div", { class: "tbl-scroll" }, h("table", { class: "tbl" },
        h("thead", null, h("tr", null, cols.map((c) => h("th", { scope: "col", class: c.align === "right" ? "num" : "" }, c.label)))),
        h("tbody", null, matches.map((m) => h("tr", null, cols.map((c) => h("td", { class: (c.cls || "") + (c.align === "right" ? " num" : "") }, c.render(m))))))))
      : emptyState("No matches yet", "Matches played by this account or any of its devices.", "matches"),
    { cls: "card-flush", sub: "Last 20, newest first." });

    const devCard = card("Devices", devices.length
      ? h("ul", { class: "dev-list" }, devices.map((d) => h("li", null,
        pidLink(d.pid, shortId(d.pid, 14)), copyBtn(d.pid, "Copy pid"),
        h("span", { class: "muted" }, "first ", timeEl(d.first_seen)), h("span", { class: "muted" }, "last ", timeEl(d.last_seen)))))
      : h("p", { class: "muted" }, "No devices linked."),
    { sub: "Device ids (pids) that signed in to this account. Click one for its player page." });

    const profile = card("Profile", kv([
      ["Created", h("span", { title: absTime(a.created_at) }, timeEl(a.created_at))],
      ["Last seen", timeEl(a.last_seen)],
      ["Google name", a.google_name ? h("span", null, a.google_name) : h("span", { class: "muted" }, "–")],
      ["Google player id", a.google_player_id ? h("span", { class: "mono" }, a.google_player_id) : h("span", { class: "muted" }, "Guest")],
      ["Equipped", h("span", { class: "mono" }, Object.entries(a.equipped || {}).map(([k, v]) => k + ": " + v).join(" · ") || "–")],
      ["Stats", h("span", { class: "mono" }, Object.entries(stats).slice(0, 8).map(([k, v]) => k + " " + (typeof v === "object" ? "…" : v)).join(" · ") || "–")],
      a.imported ? ["Imported", "from a local profile"] : null,
      a.merged_into ? ["Merged into", h("a", { class: "mono link", href: "#/accounts/" + enc(a.merged_into) }, a.merged_into)] : null,
      ["Version", h("span", { class: "mono" }, String(a.version ?? "–"))],
    ]));

    replace(body,
      hero,
      notice ? h("div", { class: "callout callout-info", role: "status" }, icon("info", { size: 16 }), h("div", null, notice)) : null,
      tiles,
      h("div", { class: "grid-2-1" },
        h("div", { class: "stack" }, ledgerCard, claimsCard, grantsCard, matchesCard),
        h("div", { class: "stack" }, profile, devCard, noteCard(a), moderationCard(a, banned))),
      eraseSection(a));
    tickTimes(body);
  }

  // ---------- coins and gems ----------

  function adjustButton(a, kind = "coins") {
    const gems = kind === "gems";
    const noun = gems ? "gems" : "coins";
    const btn = h("button", { class: "btn btn-sm", type: "button" }, icon(gems ? "gem" : "coin", { size: 14 }), "Adjust " + noun);
    btn.addEventListener("click", async () => {
      const balance = Number(gems ? a.gems : a.coins) || 0;
      const input = h("input", { type: "number", class: "input mono", id: "adj-delta", step: "1", min: String(-ADJUST_MAX), max: String(ADJUST_MAX), placeholder: gems ? "e.g. 50 or -10" : "e.g. 500 or -200", inputmode: "numeric", "aria-describedby": "adj-help" });
      const reason = h("textarea", { class: "input textarea", rows: 3, maxlength: REASON_MAX, id: "adj-reason", placeholder: "e.g. Refund for a lost purchase (3–200 characters)", required: true });
      const count = h("span", { class: "counter" }, `0 / ${REASON_MAX}`);
      const sure = h("input", { type: "checkbox", id: "adj-sure" });
      const preview = h("div", { class: "adj-preview", "aria-live": "polite" });
      const parse = () => (input.value.trim() === "" ? NaN : Number(input.value));
      const paint = () => {
        const d = parse();
        const ok = Number.isInteger(d) && d !== 0;
        const next = balance + (ok ? d : 0);
        preview.classList.toggle("is-bad", ok && next < 0);
        replace(preview, h("span", null, "New balance"), h("strong", null, ok ? fmtInt(next) : "–"),
          h("span", { class: "muted" }, "(now " + fmtInt(balance) + ")"),
          ok ? delta(d) : null,
          ok && next < 0 ? h("span", null, "The server refuses a balance below 0.") : null);
        count.textContent = `${reason.value.length} / ${REASON_MAX}`;
        count.classList.toggle("is-over", reason.value.length > REASON_MAX);
      };
      input.addEventListener("input", paint);
      reason.addEventListener("input", paint);
      paint();
      const ok = await openDialog({
        title: "Adjust " + noun + " of " + (a.name || "player"),
        confirmLabel: "Apply adjustment",
        body: [
          h("p", null, "Adds a ledger row (reason ", h("code", null, "admin"), ") and an audit entry. This is a correction, not " + noun + " earned."),
          h("label", { class: "label", for: "adj-delta" }, "Change ", h("span", { class: "muted" }, "(+ adds, − removes, up to " + fmtInt(ADJUST_MAX) + ")")),
          input,
          h("p", { class: "help muted", id: "adj-help" }, "Whole number, not 0."),
          preview,
          h("label", { class: "label", for: "adj-reason" }, "Reason ", h("span", { class: "muted" }, "(required, 3–200 characters; kept in the ledger and audit log)")),
          reason, h("div", { class: "field-foot" }, count),
          h("label", { class: "check-row", for: "adj-sure" }, sure, h("span", null, "I confirm this changes the player's balance.")),
        ],
        validate: () => {
          const d = parse();
          if (!Number.isInteger(d) || d === 0 || Math.abs(d) > ADJUST_MAX) return "delta";
          const r = reason.value.trim().length;
          if (r < 3 || r > REASON_MAX) return "reason";
          return sure.checked ? "" : "confirm";
        },
        onConfirm: () => api.post("/accounts/" + enc(a.id) + "/" + noun, { delta: parse(), reason: reason.value.trim() }),
      });
      if (ok) { toast((gems ? "Gems" : "Coins") + " adjusted", "ok"); notice = null; load(); }
    });
    return btn;
  }

  // ---------- note ----------

  function noteCard(a) {
    const saved = { v: a.note || "" };
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
        await api.patch("/accounts/" + enc(a.id), { note: ta.value });
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

  // ---------- moderation ----------

  function moderationCard(a, banned) {
    const name = a.name || "player";
    if (banned) {
      const btn = h("button", { class: "btn", type: "button" }, icon("check", { size: 15 }), "Unban account");
      btn.addEventListener("click", async () => {
        const res = await openDialog({
          title: "Unban " + name + "?",
          body: [
            h("p", null, "The account can sign in again and its devices can join rooms again."),
            h("p", { class: "muted" }, "Only the device bans this account ban caused are lifted. Bans made on the Players page stay."),
            a.ban_reason ? h("p", { class: "muted" }, "Ban reason: ", a.ban_reason) : null,
          ],
          confirmLabel: "Unban",
          onConfirm: () => api.post("/accounts/" + enc(a.id) + "/unban"),
        });
        if (res) {
          const still = Array.isArray(res.still_banned_pids) ? res.still_banned_pids : [];
          notice = still.length
            ? [h("strong", null, "Account unbanned, but " + still.length + (still.length === 1 ? " device is" : " devices are") + " still banned from the Players page: "),
              still.map((p, i) => [i ? ", " : "", pidLink(p, shortId(p, 12))])]
            : null;
          toast(name + " unbanned", still.length ? "info" : "ok");
          load();
        }
      });
      return card("Moderation", h("div", { class: "mod" },
        h("p", null, "This account is banned: sessions are refused and its devices can't join rooms."),
        h("p", { class: "ban-src" }, "Source: ", banSourceText(a.ban_source)),
        a.ban_reason ? h("p", null, h("span", { class: "muted" }, "Reason: "), h("span", { class: "danger-text" }, a.ban_reason)) : null,
        btn), { cls: "card-danger" });
    }
    const btn = h("button", { class: "btn btn-danger", type: "button" }, icon("ban", { size: 15 }), "Ban account");
    btn.addEventListener("click", async () => {
      const reason = h("textarea", { class: "input textarea", rows: 3, maxlength: REASON_MAX, id: "ban-reason", placeholder: "e.g. Coin exploit, repeated cheating (3–200 characters)", required: true });
      const count = h("span", { class: "counter" }, `0 / ${REASON_MAX}`);
      reason.addEventListener("input", () => { count.textContent = `${reason.value.length} / ${REASON_MAX}`; });
      const res = await openDialog({
        title: "Ban " + name + "?",
        danger: true,
        confirmLabel: "Ban account",
        body: [
          h("p", null, "The account's sessions are refused, and every device of it is banned and kicked from the room it was last in."),
          h("div", { class: "who who-box" }, avatar(a.avatar, a.name), h("div", { class: "who-text" }, h("strong", null, a.name || "Player"), h("span", { class: "who-sub mono" }, a.id))),
          h("label", { class: "label", for: "ban-reason" }, "Reason ", h("span", { class: "muted" }, "(required, 3–200 characters; kept in the audit log)")),
          reason, h("div", { class: "field-foot" }, count),
        ],
        validate: () => { const n = reason.value.trim().length; return n < 3 || n > REASON_MAX ? "reason" : ""; },
        onConfirm: () => api.post("/accounts/" + enc(a.id) + "/ban", { reason: reason.value.trim() }),
      });
      if (res) { notice = null; toast(name + " banned" + (res.kicked ? " (" + res.kicked + " kicked)" : ""), "ok"); load(); }
    });
    return card("Moderation", h("div", { class: "mod" }, h("p", null, "Banning blocks the account and all of its devices. It can be undone."), btn), { cls: "card-danger" });
  }

  // ---------- erase (Google Play account deletion) ----------

  function eraseSection(a) {
    const name = a.name || "player";
    const pid = a.public_id || a.id;
    const btn = h("button", { class: "btn btn-danger", type: "button" }, icon("alert", { size: 15 }), "Erase account…");
    btn.addEventListener("click", async () => {
      const typed = h("input", { type: "text", class: "input mono", id: "erase-confirm", autocomplete: "off", autocapitalize: "characters", spellcheck: false, placeholder: pid });
      const reason = h("textarea", { class: "input textarea", rows: 3, maxlength: REASON_MAX, id: "erase-reason", placeholder: "e.g. Deletion request by email, 2026-10-26 (3–200 characters; no email addresses)", required: true });
      const count = h("span", { class: "counter" }, `0 / ${REASON_MAX}`);
      reason.addEventListener("input", () => { count.textContent = `${reason.value.length} / ${REASON_MAX}`; });
      const matches = () => { const t = typed.value.trim().toUpperCase(); return t === pid.toUpperCase() || typed.value.trim() === a.id; };
      const res = await openDialog({
        title: "Erase " + name + "?",
        danger: true,
        confirmLabel: "Erase account",
        body: [
          h("p", null, h("strong", null, "This cannot be undone."), " The player's sessions stop working and the same device starts over with a fresh account."),
          h("p", { class: "label" }, "Deleted"),
          h("ul", null,
            h("li", null, "The account: profile, name, avatar, coins, gems, stats, Google link"),
            h("li", null, "Its devices and the per-device player rows (including pid bans)"),
            h("li", null, "Push tokens, leaderboard scores, offline claims, bonus and prize records, pending ad rewards")),
          h("p", { class: "label" }, "Kept (only the account id, no personal data)"),
          h("ul", null,
            h("li", null, "Ledger, coin-table entries, match rewards, re-rolls, purchases and granted ad rewards: needed for refunds and accounting"),
            h("li", null, "Matches stay, with the player's name replaced by \"Deleted player\"")),
          h("div", { class: "who who-box" }, avatar(a.avatar, a.name), h("div", { class: "who-text" }, h("strong", null, name), h("span", { class: "who-sub mono" }, pid))),
          h("label", { class: "label", for: "erase-confirm" }, "Type the Player ID ", h("span", { class: "mono" }, pid), " to confirm"),
          typed,
          h("label", { class: "label", for: "erase-reason" }, "Reason ", h("span", { class: "muted" }, "(required, 3–200 characters; kept in the audit log)")),
          reason, h("div", { class: "field-foot" }, count),
        ],
        validate: () => { if (!matches()) return "confirm"; const n = reason.value.trim().length; return n < 3 || n > REASON_MAX ? "reason" : ""; },
        onConfirm: () => api.post("/accounts/" + enc(a.id) + "/erase", { confirm: typed.value.trim(), reason: reason.value.trim() }),
      });
      if (res) { toast("Account erased", "ok"); location.hash = "#/accounts"; }
    });
    return h("section", { class: "erase-zone" },
      h("p", { class: "muted" }, "Player asked for their account to be deleted (Google Play)? Erase it here."), btn);
  }

  load();
}
