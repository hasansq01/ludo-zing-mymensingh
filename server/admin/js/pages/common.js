// Page building blocks: header, filter bar, search box, tabs, chips, tiles.
import { h, debounce, fmtInt } from "../dom.js";
import { icon } from "../icons.js";
import { skel } from "../ui.js";

export function pageHead(title, sub, actions = []) {
  return h("div", { class: "page-head" },
    h("div", null, h("h2", { class: "page-title" }, title), sub ? h("p", { class: "page-sub" }, sub) : null),
    actions.length ? h("div", { class: "page-actions" }, actions) : null);
}

export function searchBox({ value = "", placeholder, label, onInput, width = "" }) {
  const input = h("input", { type: "search", class: "input input-search", value, placeholder, "aria-label": label, autocomplete: "off", spellcheck: "false" });
  const fire = debounce(() => onInput(input.value.trim()), 280);
  input.addEventListener("input", fire);
  input.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); onInput(input.value.trim()); } });
  return h("label", { class: "search " + width }, icon("search", { size: 15, cls: "search-ic" }), input);
}

export function textFilter({ value = "", placeholder, label, onInput, mono = false, list }) {
  const input = h("input", { type: "text", class: "input" + (mono ? " mono" : ""), value, placeholder, "aria-label": label, autocomplete: "off", spellcheck: "false", list });
  const fire = debounce(() => onInput(input.value.trim()), 320);
  input.addEventListener("input", fire);
  input.addEventListener("change", () => onInput(input.value.trim()));
  return input;
}

export function selectFilter({ value = "", options, label, onChange }) {
  const sel = h("select", { class: "input select", "aria-label": label },
    options.map(([v, t]) => h("option", { value: v, selected: v === value }, t)));
  sel.addEventListener("change", () => onChange(sel.value));
  return sel;
}

/** A row of mutually exclusive chips (radio semantics). */
export function chipGroup({ value, options, label, onChange }) {
  const btns = [];
  const group = h("div", { class: "chips", role: "radiogroup", "aria-label": label });
  const set = (v, focus) => {
    for (const b of btns) {
      const on = b.dataset.v === v;
      b.setAttribute("aria-checked", String(on));
      b.tabIndex = on ? 0 : -1;
      if (on && focus) b.focus();
    }
  };
  options.forEach(([v, text, tone]) => {
    const b = h("button", { type: "button", role: "radio", class: "chip" + (tone ? " chip-" + tone : ""), dataset: { v } }, text);
    b.addEventListener("click", () => { set(v); onChange(v); });
    b.addEventListener("keydown", (e) => {
      const i = btns.indexOf(b);
      let j = -1;
      if (e.key === "ArrowRight" || e.key === "ArrowDown") j = (i + 1) % btns.length;
      if (e.key === "ArrowLeft" || e.key === "ArrowUp") j = (i - 1 + btns.length) % btns.length;
      if (j >= 0) { e.preventDefault(); const nv = btns[j].dataset.v; set(nv, true); onChange(nv); }
    });
    btns.push(b);
    group.appendChild(b);
  });
  set(value);
  return group;
}

/** Toggle chip (aria-pressed). */
export function toggleChip({ pressed, text, onChange, tone = "" }) {
  const b = h("button", { type: "button", class: "chip" + (tone ? " chip-" + tone : ""), "aria-pressed": String(Boolean(pressed)) }, text);
  b.addEventListener("click", () => {
    const v = b.getAttribute("aria-pressed") !== "true";
    b.setAttribute("aria-pressed", String(v));
    onChange(v);
  });
  return b;
}

/** Tabs (WAI-ARIA tablist; arrow keys move). Panels are rendered by the caller. */
export function tabs({ value, options, label, onChange }) {
  const btns = [];
  const list = h("div", { class: "tabs", role: "tablist", "aria-label": label });
  const set = (v, focus) => {
    for (const b of btns) {
      const on = b.dataset.v === v;
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
      if (on && focus) b.focus();
    }
  };
  options.forEach(([v, text]) => {
    const b = h("button", { type: "button", role: "tab", class: "tab", dataset: { v } }, text);
    b.addEventListener("click", () => { set(v); onChange(v); });
    b.addEventListener("keydown", (e) => {
      const i = btns.indexOf(b);
      let j = -1;
      if (e.key === "ArrowRight") j = (i + 1) % btns.length;
      if (e.key === "ArrowLeft") j = (i - 1 + btns.length) % btns.length;
      if (e.key === "Home") j = 0;
      if (e.key === "End") j = btns.length - 1;
      if (j >= 0) { e.preventDefault(); const nv = btns[j].dataset.v; set(nv, true); onChange(nv); }
    });
    btns.push(b);
    list.appendChild(b);
  });
  set(value);
  return list;
}

export function filterBar(...kids) {
  return h("div", { class: "filters", role: "search" }, kids);
}

/** Stat tile: label, value, optional foot (sub text / sparkline). */
export function tile({ label, value, foot = null, tone = "", ic = null }) {
  return h("div", { class: "tile " + tone },
    h("div", { class: "tile-label" }, ic ? icon(ic, { size: 14 }) : null, label),
    h("div", { class: "tile-value" }, typeof value === "number" ? fmtInt(value) : value),
    foot ? h("div", { class: "tile-foot" }, foot) : null);
}

export function tileSkeleton() {
  return h("div", { class: "tile", "aria-hidden": "true" }, skel("w50"), h("div", { class: "tile-value" }, skel("w40 tall")), skel("w70"));
}

export function refreshButton(onClick) {
  const b = h("button", { type: "button", class: "btn btn-sm", title: "Refresh now" }, icon("refresh", { size: 14 }), h("span", { class: "hide-sm" }, "Refresh"));
  b.addEventListener("click", async () => {
    b.classList.add("is-spinning");
    try { await onClick(); } finally { setTimeout(() => b.classList.remove("is-spinning"), 400); }
  });
  return b;
}

/** "Updated 4s ago" ticker with a live dot. */
export function updatedLabel(ctx, { live = false, every = "" } = {}) {
  let at = 0;
  const txt = h("span", null, "Loading…");
  const el = h("span", { class: "updated" + (live ? " is-live" : ""), "aria-live": "off" },
    live ? h("span", { class: "live-dot", "aria-hidden": "true" }) : null, txt);
  const t = setInterval(() => paint(), 1000);
  ctx.onCleanup(() => clearInterval(t));
  function paint() {
    if (!at) return;
    const sec = Math.max(0, Math.round((Date.now() - at) / 1000));
    txt.textContent = (sec < 2 ? "Updated just now" : `Updated ${sec < 60 ? sec + "s" : Math.round(sec / 60) + "m"} ago`) + (every ? " · auto " + every : "");
  }
  return {
    el,
    mark() { at = Date.now(); el.classList.remove("is-stale"); paint(); },
    stale() { el.classList.add("is-stale"); },
    setLive(on) { el.classList.toggle("is-live", on); },
  };
}
