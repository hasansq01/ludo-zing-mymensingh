// Config: maintenance mode, message of the day, turn timers. Save shows a diff and asks for confirmation.
import { h, replace } from "../dom.js";
import { api } from "../api.js";
import { icon } from "../icons.js";
import { card, switchEl, openDialog, toast, toastErr, errorState, skeletonBlock } from "../ui.js";
import { pageHead } from "./common.js";

const MOTD_MAX = 140;
const TIMERS = [
  { key: "turn_roll_s", label: "Roll", hint: "Time to tap the dice.", def: 15 },
  { key: "turn_choose_s", label: "Choose a pawn", hint: "Time to pick which pawn moves.", def: 20 },
  { key: "turn_pair_s", label: "Pair question", hint: "Time to answer “form a pair?”.", def: 10 },
];
const T_MIN = 5;
const T_MAX = 120;

export default function configPage(root, _params, ctx) {
  ctx.title("Config");
  const body = h("div", { class: "config" }, skeletonBlock(4), skeletonBlock(4), skeletonBlock(4));
  root.append(pageHead(null, "Server-wide settings read by the Worker and every room. Changes apply within a minute."), body);
  let saved = null;
  let draft = null;
  let ui = null;

  const onBeforeUnload = (e) => { if (dirtyKeys().length) { e.preventDefault(); e.returnValue = ""; } };
  window.addEventListener("beforeunload", onBeforeUnload);
  ctx.onCleanup(() => window.removeEventListener("beforeunload", onBeforeUnload));

  async function load() {
    try {
      const c = await api.get("/config");
      saved = normalize(c);
      draft = { ...saved };
      ctx.setMaintenance(saved.maintenance);
      build();
    } catch (err) {
      if (err.status === 401) return;
      replace(body, errorState(err, load));
    }
  }

  function normalize(c) {
    const o = { maintenance: Boolean(c?.maintenance), motd: String(c?.motd ?? "") };
    for (const t of TIMERS) o[t.key] = Number(c?.[t.key]) || t.def;
    return o;
  }

  function timerError(v) {
    if (v === "" || v === null || Number.isNaN(Number(v))) return "Enter a number of seconds.";
    const n = Number(v);
    if (!Number.isInteger(n)) return "Whole seconds only.";
    if (n < T_MIN || n > T_MAX) return `Between ${T_MIN} and ${T_MAX} seconds.`;
    return "";
  }

  function dirtyKeys() {
    if (!saved || !draft) return [];
    return Object.keys(saved).filter((k) => String(saved[k]) !== String(draft[k]));
  }

  function errors() {
    const e = {};
    if (draft.motd.length > MOTD_MAX) e.motd = `At most ${MOTD_MAX} characters.`;
    for (const t of TIMERS) { const m = timerError(draft[t.key]); if (m) e[t.key] = m; }
    return e;
  }

  function build() {
    // maintenance
    const maintWarn = h("div", { class: "callout callout-danger", role: "note" }, icon("alert", { size: 16 }),
      h("div", null, h("strong", null, "New rooms will be refused."), " Creating a room answers ", h("code", null, "503 maintenance"),
        " and the game shows your message of the day (or a default text). Rooms already open, and matches in progress, keep working."));
    const maintState = h("span", { class: "switch-state" });
    const sw = switchEl({ checked: draft.maintenance, label: "Maintenance mode", id: "sw-maint", onChange: (v) => { draft.maintenance = v; refresh(); } });
    const maintCard = card("Maintenance mode", h("div", { class: "cfg" },
      h("div", { class: "cfg-row" },
        h("div", { class: "cfg-text" }, h("label", { for: "sw-maint", class: "cfg-label" }, "Refuse new rooms"),
          h("p", { class: "help" }, "Use before a deploy that changes the protocol, or to drain the server.")),
        h("div", { class: "cfg-ctl" }, maintState, sw)),
      maintWarn));

    // motd
    const motd = h("textarea", { class: "input textarea", id: "motd", rows: 2, value: draft.motd, placeholder: "e.g. Weekend tournament starts Friday 8 pm!", "aria-describedby": "motd-help motd-count" });
    const count = h("span", { class: "counter", id: "motd-count", "aria-live": "polite" });
    const motdErr = h("p", { class: "field-err", hidden: true });
    const preview = h("div", { class: "motd-preview", "aria-label": "Preview" });
    motd.addEventListener("input", () => { draft.motd = motd.value; refresh(); });
    const motdCard = card("Message of the day", h("div", { class: "cfg" },
      h("label", { class: "cfg-label", for: "motd" }, "Message"),
      motd,
      h("div", { class: "field-foot" }, h("span", { class: "help", id: "motd-help" }, "Shown on the game's Home screen (public GET /v1/config, cached 60 s). Leave empty for none."), count),
      motdErr,
      h("div", { class: "cfg-label sub" }, "Preview"),
      preview));

    // timers
    const timerInputs = {};
    const timerRows = TIMERS.map((t) => {
      const input = h("input", { type: "number", class: "input input-num", id: "t-" + t.key, min: T_MIN, max: T_MAX, step: 1, inputmode: "numeric", value: String(draft[t.key]), "aria-describedby": "th-" + t.key });
      const err = h("p", { class: "field-err", id: "te-" + t.key, hidden: true });
      input.addEventListener("input", () => { draft[t.key] = input.value === "" ? "" : Number(input.value); refresh(); });
      timerInputs[t.key] = { input, err };
      return h("div", { class: "timer" },
        h("label", { class: "cfg-label", for: "t-" + t.key }, t.label),
        h("div", { class: "num-wrap" }, input, h("span", { class: "unit" }, "s")),
        h("p", { class: "help", id: "th-" + t.key }, t.hint, " Default ", String(t.def), " s."),
        err);
    });
    const timersCard = card("Turn timers", h("div", { class: "cfg" },
      h("div", { class: "timers" }, timerRows),
      h("p", { class: "help" }, `Each ${T_MIN}–${T_MAX} seconds. Applies to matches started after the change; two timeouts in a row turn a player into a bot.`)));

    // save bar
    const dirtyText = h("span", { class: "savebar-text" });
    const discard = h("button", { class: "btn btn-ghost", type: "button" }, "Discard");
    const save = h("button", { class: "btn btn-primary", type: "button" }, "Review and save");
    discard.addEventListener("click", () => { draft = { ...saved }; build(); });
    save.addEventListener("click", review);
    const bar = h("div", { class: "savebar", role: "region", "aria-label": "Unsaved changes" }, icon("info", { size: 16 }), dirtyText, h("span", { class: "spacer" }), discard, save);

    replace(body, maintCard, motdCard, timersCard, bar);
    ui = { maintWarn, maintState, motd, count, motdErr, preview, timerInputs, bar, dirtyText, save };
    refresh();
  }

  function refresh() {
    const e = errors();
    ui.maintWarn.hidden = !draft.maintenance;
    ui.maintState.textContent = draft.maintenance ? "On" : "Off";
    ui.maintState.classList.toggle("is-on", draft.maintenance);
    const n = draft.motd.length;
    ui.count.textContent = `${n} / ${MOTD_MAX}`;
    ui.count.classList.toggle("is-warn", n > MOTD_MAX - 20);
    ui.count.classList.toggle("is-over", n > MOTD_MAX);
    ui.motdErr.hidden = !e.motd;
    ui.motdErr.textContent = e.motd || "";
    ui.motd.setAttribute("aria-invalid", String(Boolean(e.motd)));
    replace(ui.preview, draft.motd.trim()
      ? h("div", { class: "motd-pill" }, h("span", { class: "motd-ic" }, icon("info", { size: 14 })), h("span", null, draft.motd))
      : h("span", { class: "muted" }, "No message: the Home screen shows nothing."));
    for (const t of TIMERS) {
      const { input, err } = ui.timerInputs[t.key];
      err.hidden = !e[t.key];
      err.textContent = e[t.key] || "";
      input.setAttribute("aria-invalid", String(Boolean(e[t.key])));
      if (e[t.key]) input.setAttribute("aria-errormessage", "te-" + t.key); else input.removeAttribute("aria-errormessage");
    }
    const d = dirtyKeys();
    const bad = Object.keys(e).length;
    ui.bar.classList.toggle("is-dirty", d.length > 0);
    ui.dirtyText.textContent = bad ? "Fix the highlighted fields to save." : d.length ? `${d.length} unsaved change${d.length > 1 ? "s" : ""}` : "No changes";
    ui.save.disabled = !d.length || bad > 0;
  }

  const LABELS = { maintenance: "Maintenance mode", motd: "Message of the day", turn_roll_s: "Roll timer", turn_choose_s: "Choose timer", turn_pair_s: "Pair question timer" };
  const fmt = (k, v) => (k === "maintenance" ? (v ? "On" : "Off") : k === "motd" ? (v ? "“" + v + "”" : "(empty)") : v + " s");

  async function review() {
    const keys = dirtyKeys();
    if (!keys.length || Object.keys(errors()).length) return;
    const turningOn = keys.includes("maintenance") && draft.maintenance;
    const patch = {};
    for (const k of keys) patch[k] = k.startsWith("turn_") ? Number(draft[k]) : draft[k];
    const ok = await openDialog({
      title: "Save " + keys.length + " change" + (keys.length > 1 ? "s" : "") + "?",
      danger: turningOn,
      confirmLabel: turningOn ? "Save and turn on maintenance" : "Save changes",
      wide: true,
      body: [
        h("ul", { class: "diff" }, keys.map((k) => h("li", null,
          h("span", { class: "diff-k" }, LABELS[k] || k),
          h("span", { class: "diff-old" }, fmt(k, saved[k])),
          icon("right", { size: 14 }),
          h("span", { class: "diff-new" + (k === "maintenance" && draft[k] ? " danger-text" : "") }, fmt(k, draft[k]))))),
        turningOn ? h("p", { class: "callout callout-danger" }, icon("alert", { size: 16 }), h("span", null, "Players won't be able to create rooms until you turn this off.")) : null,
      ],
      onConfirm: () => api.put("/config", patch),
    });
    if (!ok) return;
    toast("Config saved", "ok");
    try {
      const c = await api.get("/config");
      saved = normalize(c);
    } catch (err) {
      toastErr(err, "Reload");
      saved = { ...draft };
    }
    draft = { ...saved };
    ctx.setMaintenance(saved.maintenance);
    build();
  }

  load();
}
