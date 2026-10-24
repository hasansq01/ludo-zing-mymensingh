// Shared UI pieces: toasts, dialogs, badges, colour marks, avatars, empty states, skeletons.
import { h, s, shortId, copyText } from "./dom.js";
import { icon } from "./icons.js";

export const COLORS = ["Red", "Green", "Yellow", "Blue"];
export const SYMBOL = ["circle", "square", "triangle", "diamond"]; // the game's colour-blind symbols

// ---------- toasts ----------

export function toast(msg, kind = "error", ms = 5000) {
  const box = document.getElementById("toasts");
  const ic = kind === "ok" ? "check" : kind === "info" ? "info" : "alert";
  const close = h("button", { class: "toast-x", type: "button", "aria-label": "Dismiss" }, icon("x", { size: 14 }));
  const t = h("div", { class: "toast toast-" + kind, role: kind === "error" ? "alert" : "status" },
    icon(ic, { size: 16 }), h("span", { class: "toast-msg" }, msg), close);
  const kill = () => { t.classList.add("out"); setTimeout(() => t.remove(), 200); };
  close.addEventListener("click", kill);
  box.appendChild(t);
  setTimeout(kill, ms);
  while (box.children.length > 4) box.firstChild.remove();
}

const ERR_TEXT = {
  bad_input: "The server rejected the input.",
  not_found: "Not found.",
  forbidden: "Forbidden (the CSRF header was missing).",
  rate: "Too many requests. Wait a moment.",
  admin_disabled: "The admin API is disabled on this server.",
  network: "Network error: the server did not answer.",
};

export function errMessage(err) {
  if (!err) return "Something went wrong.";
  if (err.msg) return err.msg;
  if (err.code && ERR_TEXT[err.code]) return ERR_TEXT[err.code];
  if (err.status === 404) return "Not found.";
  if (err.status === 403) return ERR_TEXT.forbidden;
  if (err.status === 429) return ERR_TEXT.rate;
  if (err.status >= 500) return "Server error (" + err.status + ").";
  return err.message || "Request failed.";
}

export const toastErr = (err, prefix = "") => toast((prefix ? prefix + ": " : "") + errMessage(err), "error");

// ---------- dialog ----------

/**
 * Modal dialog built on <dialog> (focus trap + Esc for free).
 * onConfirm may be async; throwing keeps the dialog open and shows the error inside it.
 * validate() → string | "" gates the confirm button.
 */
export function openDialog({ title, body = [], confirmLabel = "Confirm", danger = false, onConfirm, validate, wide = false }) {
  return new Promise((resolve) => {
    const err = h("p", { class: "dlg-error", role: "alert", hidden: true });
    const ok = h("button", { class: "btn " + (danger ? "btn-danger" : "btn-primary"), type: "submit" }, confirmLabel);
    const cancel = h("button", { class: "btn", type: "button", value: "cancel" }, "Cancel");
    const form = h("form", { method: "dialog", class: "dlg-form" },
      h("header", { class: "dlg-head" },
        danger ? h("span", { class: "dlg-ic danger" }, icon("alert", { size: 18 })) : null,
        h("h2", { class: "dlg-title", id: "dlg-title" }, title)),
      h("div", { class: "dlg-body" }, body),
      err,
      h("footer", { class: "dlg-foot" }, cancel, ok));
    const dlg = h("dialog", { class: "dlg" + (wide ? " dlg-wide" : ""), "aria-labelledby": "dlg-title" }, form);
    let result = false;
    const check = () => {
      if (!validate) return true;
      const msg = validate();
      ok.disabled = Boolean(msg);
      return !msg;
    };
    form.addEventListener("input", check);
    cancel.addEventListener("click", () => dlg.close());
    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      if (!check()) return;
      ok.disabled = true;
      cancel.disabled = true;
      ok.classList.add("is-busy");
      err.hidden = true;
      try {
        const r = onConfirm ? await onConfirm() : true;
        result = r === undefined ? true : r;
        dlg.close();
      } catch (ex) {
        err.textContent = errMessage(ex);
        err.hidden = false;
        ok.disabled = false;
        cancel.disabled = false;
        ok.classList.remove("is-busy");
      }
    });
    dlg.addEventListener("close", () => { dlg.remove(); resolve(result); });
    document.body.appendChild(dlg);
    check();
    dlg.showModal();
    const first = dlg.querySelector("textarea, input:not([type=checkbox])");
    if (first) first.focus();
  });
}

// ---------- marks and badges ----------

const SHAPES = {
  circle: () => s("circle", { cx: 6, cy: 6, r: 5 }),
  square: () => s("rect", { x: 1.2, y: 1.2, width: 9.6, height: 9.6, rx: 1.6 }),
  triangle: () => s("path", { d: "M6 0.8 11.3 10.6H0.7Z", "stroke-linejoin": "round" }),
  diamond: () => s("path", { d: "M6 0.4 11.6 6 6 11.6 0.4 6Z" }),
};

/** Colour marker: the game's colour-blind symbol in the player colour (never colour alone). */
export function colorMark(c, { size = 12, title = true } = {}) {
  c = Number(c);
  if (!(c >= 0 && c <= 3)) return h("span", { class: "cm-none", "aria-hidden": "true" });
  const svgAttrs = { viewBox: "0 0 12 12", width: size, height: size, class: "cm cm-" + c };
  if (title) { svgAttrs.role = "img"; svgAttrs["aria-label"] = COLORS[c]; } else svgAttrs["aria-hidden"] = "true";
  const el = s("svg", svgAttrs, SHAPES[SYMBOL[c]]());
  if (title) el.appendChild(s("title", null, COLORS[c]));
  return el;
}

export function colorLabel(c) {
  if (!(c >= 0 && c <= 3)) return h("span", { class: "muted" }, "–");
  return h("span", { class: "clabel" }, colorMark(c, { title: false }), COLORS[c]);
}

export function badge(text, tone = "neutral", ic = null) {
  return h("span", { class: "badge badge-" + tone }, ic ? icon(ic, { size: 12 }) : null, text);
}

const STATUS_TONE = { lobby: "info", playing: "ok", over: "neutral", closed: "muted", abandoned: "warn" };
export const statusBadge = (st) => badge(st || "unknown", STATUS_TONE[st] || "neutral");

const RESULT_TONE = { playing: "ok", over: "neutral", abandoned: "warn", closed: "muted" };
export const resultBadge = (r) => badge(r === "over" ? "finished" : r || "–", RESULT_TONE[r] || "neutral");

const LEVEL_IC = { info: "info", warn: "alert", error: "error" };
export const levelBadge = (lv) => badge(lv || "info", lv === "error" ? "danger" : lv === "warn" ? "warn" : "info", LEVEL_IC[lv] || "info");

export const onlineDot = (on) =>
  h("span", { class: "dot " + (on ? "dot-on" : "dot-off"), role: "img", "aria-label": on ? "online" : "offline", title: on ? "Online" : "Offline" });

// The game's avatar catalogue (godot/scripts/core/collection.gd AVATARS): tile gradients by id.
const AVATARS = {
  "pawn-red": ["#ff8a80", "#e5484d"], "pawn-green": ["#8be3b0", "#2fa86b"], "pawn-yellow": ["#ffe27a", "#e0a100"],
  "pawn-blue": ["#8fb7ff", "#3b7be0"], latte: ["#f1d9b5", "#a8693c"], dice: ["#ff9a9d", "#c3141b"],
  robot: ["#b8e7ff", "#3a8fd0"], crown: ["#c99bff", "#6a35c0"],
};

/** Round avatar chip: catalogue colours + the name's initial. */
export function avatar(id, name, size = 28) {
  const g = AVATARS[id] || ["#efdfd5", "#c7a98a"];
  const letter = (String(name || "?").trim()[0] || "?").toUpperCase();
  return h("span", {
    class: "av", title: id ? "Avatar: " + id : "No avatar", "aria-hidden": "true",
    style: { "--a1": g[0], "--a2": g[1], width: size + "px", height: size + "px", fontSize: Math.round(size * 0.46) + "px" },
  }, letter);
}

export function copyBtn(text, label = "Copy") {
  const b = h("button", { class: "icon-btn sm", type: "button", title: label, "aria-label": label + " " + text }, icon("copy", { size: 13 }));
  b.addEventListener("click", async (e) => {
    e.stopPropagation();
    e.preventDefault();
    if (await copyText(text)) toast("Copied " + text, "ok", 1800);
  });
  return b;
}

export const pidLink = (pid, text) =>
  pid ? h("a", { href: "#/players/" + encodeURIComponent(pid), class: "mono link", title: pid }, text ?? shortId(pid)) : h("span", { class: "muted" }, "–");

export const codeLink = (code) =>
  code ? h("a", { href: "#/rooms/" + encodeURIComponent(code), class: "mono link code" }, code) : h("span", { class: "muted" }, "–");

// ---------- states ----------

export function emptyState(title, hint = "", ic = "info") {
  return h("div", { class: "empty" }, h("span", { class: "empty-ic" }, icon(ic, { size: 22 })),
    h("p", { class: "empty-title" }, title), hint ? h("p", { class: "empty-hint" }, hint) : null);
}

export function errorState(err, retry) {
  return h("div", { class: "empty empty-err" }, h("span", { class: "empty-ic" }, icon("alert", { size: 22 })),
    h("p", { class: "empty-title" }, "Could not load"), h("p", { class: "empty-hint" }, errMessage(err)),
    retry ? h("button", { class: "btn btn-sm", type: "button", onClick: retry }, icon("refresh", { size: 14 }), "Retry") : null);
}

export function skel(cls = "") {
  return h("span", { class: "skel " + cls, "aria-hidden": "true" });
}

export function skeletonBlock(lines = 4) {
  const out = h("div", { class: "skel-block", role: "status", "aria-label": "Loading" });
  for (let i = 0; i < lines; i++) out.appendChild(skel(i === 0 ? "w40" : i % 2 ? "w90" : "w70"));
  return out;
}

export function card(title, body, { actions = null, cls = "", sub = "" } = {}) {
  return h("section", { class: "card " + cls },
    title ? h("header", { class: "card-head" },
      h("div", null, h("h2", { class: "card-title" }, title), sub ? h("p", { class: "card-sub" }, sub) : null),
      actions ? h("div", { class: "card-actions" }, actions) : null) : null,
    h("div", { class: "card-body" }, body));
}

/** Definition list of [label, value] rows. */
export function kv(rows) {
  return h("dl", { class: "kv" }, rows.filter(Boolean).map(([k, v]) => [h("dt", null, k), h("dd", null, v)]));
}

export function switchEl({ checked, label, onChange, id }) {
  const b = h("button", {
    class: "switch", type: "button", role: "switch", id, "aria-checked": String(Boolean(checked)), "aria-label": label,
  }, h("span", { class: "switch-knob" }));
  b.addEventListener("click", () => {
    const v = b.getAttribute("aria-checked") !== "true";
    b.setAttribute("aria-checked", String(v));
    onChange?.(v);
  });
  return b;
}
