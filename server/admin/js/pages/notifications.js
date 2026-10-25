// Notifications: compose and schedule a push campaign, test it on one account, campaign stats and the 14-day
// event-push counters (NOTIFICATIONS.md "N-SRV" → "Admin API"). Everything stays visible while push is off.
import { h, replace, fmtInt, debounce, timeEl, parseJson, poll } from "../dom.js";
import { api, enc } from "../api.js";
import { icon } from "../icons.js";
import { lineChart } from "../chart.js";
import { card, badge, openDialog, toast, toastErr, errorState, emptyState, skeletonBlock } from "../ui.js";
import { pageHead, tile, tileSkeleton, chipGroup, refreshButton, updatedLabel } from "./common.js";
import { simpleTable } from "./account_cells.js";

const TITLE_MAX = 60;
const BODY_MAX = 180;
const BD_OFFSET_S = 6 * 3600; // Bangladesh time is UTC+6 all year (no daylight saving)

// The deep links the game understands (NOTIFICATIONS.md "Ids and texts").
const LINKS = [
  ["", "Open the game (home)"],
  ["daily", "Daily reward"],
  ["spin", "Free spin"],
  ["free", "Free coins"],
  ["shop", "Shop"],
  ["shop-item", "A shop item"],
  ["room", "A friend room"],
  ["leaderboard", "Leaderboard"],
];
const LINK_NAME = { "": "Home", home: "Home", daily: "Daily reward", spin: "Free spin", free: "Free coins", shop: "Shop", leaderboard: "Leaderboard" };
const SHOP_KINDS = [["room", "Room"], ["scene", "Scene"], ["dice", "Dice"], ["emotes", "Emote pack"], ["avatar", "Avatar"], ["frame", "Frame"], ["plate", "Name plate"], ["badge", "Badge"], ["coins", "Coins"]];

const STATUS_TONE = { draft: "muted", scheduled: "info", sending: "warn", sent: "ok", canceled: "muted", failed: "danger" };
const EVENT_KINDS = { turn: "Your turn", joined: "Friend joined", rematch: "Rematch", weekly: "Weekly result" };

const toMs = (t) => (t ? (Number(t) < 1e11 ? Number(t) * 1000 : Number(t)) : 0); // the API may use seconds or ms
const pad = (n) => String(n).padStart(2, "0");

/** "2026-10-26 09:00" in Bangladesh time. */
function bdText(ms) {
  const d = new Date(ms + BD_OFFSET_S * 1000);
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
}

/** The value of a datetime-local input (read as Bangladesh time) → unix seconds, or null. */
function bdToUnix(v) {
  const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(v || "");
  if (!m) return null;
  return Math.floor(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]) / 1000) - BD_OFFSET_S;
}

/** Next full hour from now, 1 h ahead, as a datetime-local value in Bangladesh time. */
const defaultWhen = () => bdText(Math.ceil((Date.now() + 3600e3) / 3600e3) * 3600e3).replace(" ", "T");

function audienceText(aud) {
  const a = parseJson(aud, null);
  if (!a || a.kind !== "segment") return "Everyone";
  const parts = [];
  if (a.inactive_days) parts.push(`away ${a.inactive_days}+ days`);
  if (a.new_days) parts.push(`joined in the last ${a.new_days} days`);
  if (a.level_min || a.level_max) parts.push(`level ${a.level_min || 1}–${a.level_max || "max"}`);
  return "Segment: " + (parts.join(", ") || "all with offers on");
}

const linkText = (link) => {
  if (!link) return "Home";
  if (LINK_NAME[link]) return LINK_NAME[link];
  if (link.startsWith("room:")) return "Room " + link.slice(5);
  if (link.startsWith("shop:")) return "Shop: " + link.slice(5).replace(":", " ");
  return link;
};

export default function notificationsPage(root, _params, ctx) {
  ctx.title("Notifications");
  const form = {
    title: "", body: "", link: "", shopKind: "avatar", shopId: "", room: "",
    audience: "all", inactive: "", fresh: "", lmin: "", lmax: "", when: "now", at: defaultWhen(),
  };
  let configured = true;
  let loaded = false;
  let busy = false;
  const charts = [];
  const ui = {};

  const tilesBox = h("div", { class: "tiles tiles-3" }, [1, 2, 3].map(() => tileSkeleton()));
  const bannerBox = h("div");
  const campaignsBox = h("div", null, skeletonBlock(5));
  const eventsBox = h("div", null, skeletonBlock(5));
  const upd = updatedLabel(ctx, { live: true, every: "30s" });

  // ---------- form values ----------

  const numOrNull = (v) => (v === "" || Number.isNaN(Number(v)) ? null : Math.floor(Number(v)));

  function linkValue() {
    if (form.link === "shop-item") {
      const id = form.shopId.trim();
      return id ? `shop:${form.shopKind}:${id}` : "shop";
    }
    if (form.link === "room") return form.room.trim() ? "room:" + form.room.trim().toUpperCase() : "";
    return form.link;
  }

  function audienceBody() {
    if (form.audience === "all") return { kind: "all" };
    const a = { kind: "segment" };
    for (const [k, v] of [["inactive_days", form.inactive], ["new_days", form.fresh], ["level_min", form.lmin], ["level_max", form.lmax]]) {
      const n = numOrNull(v);
      if (n !== null && n > 0) a[k] = n;
    }
    return a;
  }

  function errors() {
    const e = {};
    if (!form.title.trim()) e.title = "Add a title.";
    else if (form.title.length > TITLE_MAX) e.title = `At most ${TITLE_MAX} characters.`;
    if (!form.body.trim()) e.body = "Add a message.";
    else if (form.body.length > BODY_MAX) e.body = `At most ${BODY_MAX} characters.`;
    if (form.link === "room" && !/^[A-Za-z0-9]{4,8}$/.test(form.room.trim())) e.room = "Enter the room code.";
    if (form.link === "shop-item" && form.shopId.trim() && !/^[A-Za-z0-9_-]+$/.test(form.shopId.trim())) e.shopId = "Letters, digits, - and _ only.";
    const a = audienceBody();
    if (a.level_min && a.level_max && a.level_min > a.level_max) e.level = "The minimum level is above the maximum.";
    if (form.when === "schedule") {
      const at = bdToUnix(form.at);
      if (at === null) e.at = "Pick a date and time.";
      else if (at < Date.now() / 1000 + 60) e.at = "Pick a time in the future.";
    }
    return e;
  }

  const campaignBody = () => {
    const body = { title: form.title.trim(), body: form.body.trim(), audience: audienceBody() };
    const link = linkValue();
    if (link) body.link = link;
    if (form.when === "schedule") body.run_at = bdToUnix(form.at);
    return body;
  };

  // ---------- compose card ----------

  const field = (id, label, input, extra = null) => h("div", { class: "cfg" }, h("label", { class: "cfg-label", for: id }, label), input, extra);
  const errP = () => h("p", { class: "field-err", hidden: true });

  const title = h("input", { type: "text", class: "input", id: "np-title", maxlength: "200", placeholder: "e.g. Weekend tournament starts now", autocomplete: "off", "aria-describedby": "np-title-count" });
  const titleCount = h("span", { class: "counter", id: "np-title-count", "aria-live": "polite" });
  const titleErr = errP();
  const body = h("textarea", { class: "input textarea", id: "np-body", rows: 3, maxlength: "500", placeholder: "e.g. Double coins on every win until Sunday.", "aria-describedby": "np-body-count" });
  const bodyCount = h("span", { class: "counter", id: "np-body-count", "aria-live": "polite" });
  const bodyErr = errP();
  title.addEventListener("input", () => { form.title = title.value; refresh(); });
  body.addEventListener("input", () => { form.body = body.value; refresh(); });

  const linkSel = h("select", { class: "input select", id: "np-link" }, LINKS.map(([v, t]) => h("option", { value: v }, t)));
  const shopKind = h("select", { class: "input select", id: "np-shop-kind", "aria-label": "Shop item kind" }, SHOP_KINDS.map(([v, t]) => h("option", { value: v }, t)));
  const shopId = h("input", { type: "text", class: "input mono", id: "np-shop-id", placeholder: "item id (empty = the shop)", "aria-label": "Shop item id", autocomplete: "off", spellcheck: "false" });
  const shopErr = errP();
  const room = h("input", { type: "text", class: "input mono", id: "np-room", maxlength: "8", placeholder: "Room code, e.g. K7MQ2X", "aria-label": "Room code", autocomplete: "off", spellcheck: "false" });
  const roomErr = errP();
  const shopRow = h("div", { class: "np-row", hidden: true }, shopKind, shopId);
  const roomRow = h("div", { class: "np-row", hidden: true }, room);
  linkSel.addEventListener("change", () => { form.link = linkSel.value; refresh(); });
  shopKind.addEventListener("change", () => { form.shopKind = shopKind.value; refresh(); });
  shopId.addEventListener("input", () => { form.shopId = shopId.value; refresh(); });
  room.addEventListener("input", () => { form.room = room.value; refresh(); });
  const linkHelp = h("p", { class: "help" });

  const numInput = (key, label, ph) => {
    const input = h("input", { type: "number", class: "input input-num", min: "1", step: "1", inputmode: "numeric", "aria-label": label, placeholder: ph });
    input.addEventListener("input", () => { form[key] = input.value; refresh(); previewSoon(); });
    return h("label", { class: "np-num" }, h("span", { class: "help" }, label), input);
  };
  const segBox = h("div", { class: "np-seg", hidden: true },
    h("div", { class: "np-row" },
      numInput("inactive", "Away for at least (days)", "any"),
      numInput("fresh", "Joined within (days)", "any")),
    h("div", { class: "np-row" }, numInput("lmin", "Level from", "1"), numInput("lmax", "Level to", "any")),
    h("p", { class: "help" }, "Players who match every filter you fill in, and have News & offers turned on."));
  const levelErr = errP();
  const audChips = chipGroup({
    value: form.audience, label: "Audience",
    options: [["all", "Everyone"], ["segment", "Segment"]],
    onChange: (v) => { form.audience = v; refresh(); previewSoon(); },
  });
  const reach = h("p", { class: "np-reach", "aria-live": "polite" });

  const whenChips = chipGroup({
    value: form.when, label: "When to send",
    options: [["now", "Send now"], ["schedule", "Schedule"]],
    onChange: (v) => { form.when = v; refresh(); },
  });
  const at = h("input", { type: "datetime-local", class: "input", id: "np-at", value: form.at, "aria-label": "Send at, Bangladesh time" });
  at.addEventListener("input", () => { form.at = at.value; refresh(); });
  const atErr = errP();
  const atRow = h("div", { class: "np-when", hidden: true }, at, h("span", { class: "help" }, "Bangladesh time (UTC+6)"));

  const testId = h("input", { type: "text", class: "input mono", id: "np-test", placeholder: "acc_…", "aria-label": "Account id for the test", autocomplete: "off", spellcheck: "false" });
  const testBtn = h("button", { type: "button", class: "btn" }, icon("note", { size: 14 }), "Send test");
  const testHelp = h("p", { class: "help" });
  testBtn.addEventListener("click", sendTest);
  testId.addEventListener("input", refresh);
  testId.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); if (!testBtn.disabled) sendTest(); } });

  const sendBtn = h("button", { type: "button", class: "btn btn-primary" }, icon("send", { size: 14 }), "Send");
  const sendHelp = h("p", { class: "help np-send-help" });
  sendBtn.addEventListener("click", review);

  const composeCard = card("New campaign", h("div", { class: "np-form" },
    field("np-title", "Title", title, h("div", { class: "field-foot" }, titleErr, titleCount)),
    field("np-body", "Message", body, h("div", { class: "field-foot" }, bodyErr, bodyCount)),
    field("np-link", "Opens", linkSel, [shopRow, shopErr, roomRow, roomErr, linkHelp]),
    h("div", { class: "cfg" }, h("span", { class: "cfg-label" }, "Audience"), audChips, segBox, levelErr, reach),
    h("div", { class: "cfg" }, h("span", { class: "cfg-label" }, "When"), whenChips, atRow, atErr),
    h("div", { class: "np-actions" }, sendBtn, sendHelp),
    h("div", { class: "cfg np-test" }, h("label", { class: "cfg-label", for: "np-test" }, "Send test to account"),
      h("div", { class: "np-row" }, testId, testBtn),
      testHelp)),
  { sub: "Goes to the News & offers channel of players who have it on." });

  // ---------- phone preview ----------

  const pvTitle = h("div", { class: "np-n-title" });
  const pvBody = h("div", { class: "np-n-body" });
  const pvOpens = h("p", { class: "help np-opens" });
  const previewCard = card("Preview", h("div", null,
    h("div", { class: "phone", "aria-label": "Notification preview" },
      h("div", { class: "phone-bar" }, h("span", null, "9:41"), h("span", { class: "phone-bar-r", "aria-hidden": "true" }, "● ● ▮")),
      h("div", { class: "np-n" },
        h("div", { class: "np-n-head" }, h("span", { class: "np-n-ic", "aria-hidden": "true" }, "L"), h("span", null, "Ludo Zing"), h("span", { class: "np-n-dot" }, "·"), h("span", null, "now")),
        pvTitle, pvBody)),
    pvOpens),
  { sub: "As it looks on an Android phone." });

  // ---------- refresh (validation + live bits) ----------

  const setErr = (el, msg) => { el.hidden = !msg; el.textContent = msg || ""; };
  const counter = (el, n, max) => {
    el.textContent = `${n} / ${max}`;
    el.classList.toggle("is-warn", n > max - 10);
    el.classList.toggle("is-over", n > max);
  };

  function refresh() {
    const e = errors();
    counter(titleCount, form.title.length, TITLE_MAX);
    counter(bodyCount, form.body.length, BODY_MAX);
    // show an error only once the field has been touched, but the counters always
    setErr(titleErr, form.title && e.title ? e.title : "");
    setErr(bodyErr, form.body && e.body ? e.body : "");
    title.setAttribute("aria-invalid", String(form.title.length > TITLE_MAX));
    body.setAttribute("aria-invalid", String(form.body.length > BODY_MAX));
    shopRow.hidden = form.link !== "shop-item";
    roomRow.hidden = form.link !== "room";
    setErr(shopErr, e.shopId);
    setErr(roomErr, form.room && e.room ? e.room : "");
    linkHelp.textContent = "Sent as: " + (linkValue() || "home") + " (unknown links just open the game).";
    segBox.hidden = form.audience !== "segment";
    setErr(levelErr, e.level);
    atRow.hidden = form.when !== "schedule";
    setErr(atErr, e.at);
    sendBtn.lastChild.textContent = form.when === "schedule" ? "Schedule" : "Send now";
    // phone preview
    pvTitle.textContent = form.title.trim() || "Your title";
    pvTitle.classList.toggle("is-ph", !form.title.trim());
    pvBody.textContent = form.body.trim() || "Your message shows here, up to a few lines.";
    pvBody.classList.toggle("is-ph", !form.body.trim());
    pvOpens.textContent = "Tapping opens: " + linkText(linkValue());
    // buttons
    const off = !loaded ? "Loading…" : !configured ? "Push is not configured on this server, so nothing can be sent yet." : "";
    sendBtn.disabled = busy || Boolean(off) || Object.keys(e).length > 0;
    sendHelp.textContent = off || (Object.keys(e).length ? "Fill in the title and message to send." : "You'll confirm before anything goes out.");
    const testOk = !off && form.title.trim() && form.body.trim() && form.title.length <= TITLE_MAX && form.body.length <= BODY_MAX && testId.value.trim();
    testBtn.disabled = busy || !testOk;
    testHelp.textContent = off || "Uses the title, message and link above. 20 tests per hour.";
  }

  // ---------- audience reach (debounced, newest answer wins) ----------

  let previewSeq = 0;
  async function loadReach() {
    const my = ++previewSeq;
    const aud = audienceBody();
    reach.className = "np-reach is-busy";
    reach.textContent = "Counting…";
    try {
      const res = await api.post("/push/preview", { audience: aud });
      if (my !== previewSeq) return;
      reach.className = "np-reach";
      replace(reach, icon("players", { size: 15 }), "≈ ", h("strong", null, fmtInt(res?.targeted ?? 0)), " players");
      reach.title = aud.kind === "all" ? "Everyone subscribed to the promos topic; the count is the registered devices with News & offers on." : "";
    } catch (err) {
      if (my !== previewSeq || err.status === 401) return;
      reach.className = "np-reach is-err";
      reach.textContent = "Could not count: " + (err.msg || err.message);
    }
  }
  const previewSoon = debounce(loadReach, 450);

  // ---------- actions ----------

  async function review() {
    const e = errors();
    if (Object.keys(e).length || !configured) return;
    const payload = campaignBody();
    const later = payload.run_at ? bdText(payload.run_at * 1000) + " Bangladesh time" : "";
    const ok = await openDialog({
      title: later ? "Schedule this notification?" : "Send this notification now?",
      confirmLabel: later ? "Schedule" : "Send to players",
      danger: !later,
      wide: true,
      body: [
        h("div", { class: "np-confirm" },
          h("strong", null, payload.title), h("span", null, payload.body)),
        h("ul", { class: "diff" },
          [["Audience", audienceText(payload.audience) + (reach.querySelector("strong") ? ` (≈ ${reach.querySelector("strong").textContent} players)` : "")],
            ["Opens", linkText(payload.link)], ["When", later || "Right away"]]
            .map(([k, v]) => h("li", null, h("span", { class: "diff-k" }, k), h("span", { class: "diff-new" }, v)))),
        h("p", { class: "callout callout-danger" }, icon("alert", { size: 16 }), h("span", null, later
          ? "This goes to real players at that time. You can cancel it until then."
          : "This goes to real players right away and can't be taken back.")),
      ],
      onConfirm: () => api.post("/push/campaigns", payload),
    });
    if (!ok) return;
    toast(later ? "Campaign scheduled" : "Campaign sent to the queue", "ok");
    form.title = ""; form.body = ""; title.value = ""; body.value = "";
    refresh();
    load(true);
  }

  async function sendTest() {
    if (testBtn.disabled) return;
    busy = true;
    testBtn.classList.add("is-busy");
    refresh();
    try {
      const payload = { title: form.title.trim(), body: form.body.trim(), account_id: testId.value.trim() };
      const link = linkValue();
      if (link) payload.link = link;
      const res = await api.post("/push/test", payload);
      const sent = Number(res?.sent) || 0;
      const failed = Number(res?.failed) || 0;
      if (!sent && !failed) toast("That account has no registered device (nothing to send to).", "info");
      else toast(`Test sent to ${sent} device${sent === 1 ? "" : "s"}${failed ? `, ${failed} failed` : ""}.`, failed && !sent ? "error" : "ok");
    } catch (err) {
      if (err.status !== 401) toastErr(err, "Test");
    } finally {
      busy = false;
      testBtn.classList.remove("is-busy");
      refresh();
    }
  }

  async function cancel(c) {
    const ok = await openDialog({
      title: "Cancel this campaign?", confirmLabel: "Cancel campaign", danger: true,
      body: [h("p", null, "“", c.title, "” is scheduled for ", bdText(toMs(c.run_at)), " Bangladesh time and won't be sent.")],
      onConfirm: () => api.post(`/push/campaigns/${enc(c.id)}/cancel`),
    });
    if (!ok) return;
    toast("Campaign canceled", "ok");
    load(true);
  }

  // ---------- data ----------

  function renderCampaigns(list) {
    if (!list.length) return replace(campaignsBox, emptyState("No campaigns yet", "Campaigns you send or schedule are listed here.", "events"));
    const cols = [
      { label: "Campaign", cls: "col-main", render: (c) => h("div", { class: "np-camp" }, h("strong", null, c.title), h("span", { class: "help trunc", title: c.body }, c.body)) },
      { label: "Audience", render: (c) => audienceText(c.audience) },
      { label: "Status", render: (c) => badge(c.status || "–", STATUS_TONE[c.status] || "neutral") },
      { label: "When", render: whenCell },
      { label: "Targeted", align: "right", render: (c) => fmtInt(c.targeted) },
      { label: "Sent", align: "right", render: (c) => fmtInt(c.sent) },
      { label: "Failed", align: "right", render: (c) => (Number(c.failed) ? h("span", { class: "danger-text" }, fmtInt(c.failed)) : "0") },
      { label: "Opened", align: "right", render: openedCell },
      { label: "Actions", cls: "col-act", render: (c) => (c.status === "scheduled"
        ? h("button", { type: "button", class: "btn btn-sm", onClick: () => cancel(c) }, icon("x", { size: 14 }), "Cancel")
        : null) },
    ];
    replace(campaignsBox, simpleTable(cols, list, { caption: "Push campaigns, newest first" }));
  }

  function whenCell(c) {
    const ms = toMs(c.status === "scheduled" ? c.run_at : c.sent_at || c.run_at || c.created_at);
    if (!ms) return h("span", { class: "muted" }, "–");
    return h("div", { class: "np-when-cell" }, timeEl(ms), h("span", { class: "help" }, bdText(ms) + " BST"));
  }

  function openedCell(c) {
    const sent = Number(c.sent) || 0;
    if (!sent) return fmtInt(c.opened);
    const rate = Math.round(((Number(c.opened) || 0) / sent) * 100);
    return h("span", { title: `${rate}% of sent` }, fmtInt(c.opened), " ", h("span", { class: "muted" }, `(${rate}%)`));
  }

  /** Event counters: [{day, kind, sent, failed}] → a per-day chart (sent / failed) and a per-kind table. */
  function renderEvents(rows) {
    for (const c of charts.splice(0)) c.destroy?.();
    rows = Array.isArray(rows) ? rows : [];
    const today = Date.now();
    const days = Array.from({ length: 14 }, (_, i) => new Date(today - (13 - i) * 86400e3).toISOString().slice(0, 10));
    const by = new Map(days.map((d) => [d, { sent: 0, failed: 0 }]));
    const kinds = new Map();
    for (const r of rows) {
      const k = kinds.get(r.kind) || { kind: r.kind, sent: 0, failed: 0 };
      k.sent += Number(r.sent) || 0;
      k.failed += Number(r.failed) || 0;
      kinds.set(r.kind, k);
      const d = by.get(r.day);
      if (d) { d.sent += Number(r.sent) || 0; d.failed += Number(r.failed) || 0; }
    }
    if (!kinds.size) return replace(eventsBox, emptyState("No event pushes yet", "Turn, friend joined, rematch and weekly pushes are counted here.", "chart"));
    const chart = lineChart({
      title: "Event pushes per day", days,
      series: [{ key: "sent", name: "Sent", tone: 1, values: days.map((d) => by.get(d).sent) }, { key: "failed", name: "Failed", tone: 2, values: days.map((d) => by.get(d).failed) }],
      yLabel: "Pushes per day", height: 220,
    });
    charts.push(chart);
    const cols = [
      { label: "Kind", render: (k) => EVENT_KINDS[k.kind] || k.kind },
      { label: "Sent", align: "right", render: (k) => fmtInt(k.sent) },
      { label: "Failed", align: "right", render: (k) => fmtInt(k.failed) },
    ];
    replace(eventsBox, chart, h("div", { class: "np-kinds" }, simpleTable(cols, [...kinds.values()].sort((a, b) => b.sent - a.sent), { caption: "Event pushes by kind, last 14 days" })));
  }

  let failed = 0;
  async function load(manual = false) {
    try {
      const res = await api.get("/push");
      failed = 0;
      configured = Boolean(res?.configured);
      loaded = true;
      const t = res?.tokens || {};
      replace(bannerBox, configured ? null : h("div", { class: "callout callout-warn", role: "status" }, icon("alert", { size: 16 }),
        h("div", null, h("strong", null, "Push not configured. "), "No Firebase service account is set on this server, so sending is off. Local game notifications still work. Set ",
          h("code", null, "FCM_SERVICE_ACCOUNT"), " with ", h("code", null, "tools/cf.sh secret put FCM_SERVICE_ACCOUNT"), " when the Firebase project exists.")));
      replace(tilesBox,
        tile({ label: "Devices registered", value: Number(t.total) || 0, ic: "players", foot: h("span", { class: "tile-sub" }, "Push tokens stored") }),
        tile({ label: "News & offers on", value: Number(t.offers) || 0, ic: "events", foot: h("span", { class: "tile-sub" }, "Can receive campaigns") }),
        tile({ label: "Game alerts on", value: Number(t.game) || 0, ic: "rooms", foot: h("span", { class: "tile-sub" }, "Can receive turn / rematch pushes") }));
      renderCampaigns(Array.isArray(res?.campaigns) ? res.campaigns : []);
      renderEvents(res?.events);
      upd.mark();
      refresh();
      if (!ui.reached) { ui.reached = true; loadReach(); }
    } catch (err) {
      if (err.status === 401) return;
      failed++;
      upd.stale();
      if (!loaded) {
        replace(tilesBox);
        replace(campaignsBox, errorState(err, () => load(true)));
        replace(eventsBox);
        refresh();
      }
      if (manual || failed === 1) toastErr(err, "Notifications");
    }
  }

  root.append(
    pageHead(null, "Send a promo to players' phones, or test it on one account. Event pushes (your turn, friend joined…) go out by themselves.", [upd.el, refreshButton(() => load(true))]),
    bannerBox,
    tilesBox,
    h("div", { class: "grid-2-1 np-top" }, composeCard, previewCard),
    card("Campaigns", campaignsBox, { cls: "card-flush", sub: "Latest 50, newest first. Opened counts players who tapped the notification." }),
    h("div", { style: { marginTop: "16px" } }, card("Event pushes, last 14 days", eventsBox, { sub: "Sent automatically by the game server, per UTC day." })));
  refresh();
  load();
  const p = poll(() => load(), 30000);
  ctx.onCleanup(() => { p.stop(); previewSeq++; for (const c of charts) c.destroy?.(); });
}
