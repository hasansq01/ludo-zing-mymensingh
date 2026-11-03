// Cursor-paginated data table: skeleton on first load, previous rows dimmed while refetching, empty / error
// states, optional expandable rows and row links.
import { h, clear, tickTimes } from "./dom.js";
import { icon } from "./icons.js";
import { emptyState, errorState, toastErr, skel } from "./ui.js";

/**
 * columns: [{label, render(item) → Node|string, cls, align: "right", sr: bool (visually hidden header)}]
 * load(params) → Promise<{items, next}>; params gets {limit, cursor}.
 * rowHref(item) → "#/..." makes the row clickable (the first link in the row stays the keyboard target).
 * expand(item) → Node adds a disclosure button per row.
 */
export function dataTable({ columns, load, rowHref, expand, empty = ["Nothing here yet", ""], limit = 50, caption = "", dense = false, onData }) {
  let cursors = [null];
  let page = 0;
  let next = null;
  let items = [];
  let gen = 0;
  let loadedOnce = false;
  const allCols = expand ? [{ label: "Expand", sr: true, cls: "col-x", render: null }, ...columns] : columns;

  const thead = h("thead", null, h("tr", null, allCols.map((c) =>
    h("th", { scope: "col", class: (c.cls || "") + (c.align === "right" ? " num" : "") }, c.sr ? h("span", { class: "sr-only" }, c.label) : c.label))));
  const tbody = h("tbody");
  const table = h("table", { class: "tbl" + (dense ? " tbl-dense" : "") }, caption ? h("caption", { class: "sr-only" }, caption) : null, thead, tbody);
  const scroller = h("div", { class: "tbl-scroll" }, table);
  const info = h("span", { class: "tbl-info" });
  const prev = h("button", { class: "btn btn-sm", type: "button", disabled: true, "aria-label": "Previous page" }, icon("left", { size: 14 }), "Prev");
  const nextBtn = h("button", { class: "btn btn-sm", type: "button", disabled: true, "aria-label": "Next page" }, "Next", icon("right", { size: 14 }));
  const foot = h("div", { class: "tbl-foot" }, info, h("div", { class: "tbl-pager" }, prev, nextBtn));
  const stateBox = h("div", { class: "tbl-state" });
  const el = h("div", { class: "tbl-wrap" }, scroller, stateBox, foot);

  let params = {};

  function skeleton() {
    clear(tbody);
    for (let r = 0; r < 8; r++) {
      tbody.appendChild(h("tr", { class: "skel-row", "aria-hidden": "true" },
        allCols.map((c, i) => h("td", { class: c.cls || "" }, c.render === null ? null : skel(i === 0 || (expand && i === 1) ? "w70" : "w50")))));
    }
  }

  function render() {
    clear(tbody);
    clear(stateBox);
    if (!items.length) {
      stateBox.appendChild(emptyState(empty[0], empty[1], "search"));
      table.classList.add("is-empty");
    } else table.classList.remove("is-empty");
    for (const it of items) {
      const href = rowHref ? rowHref(it) : null;
      const tr = h("tr", { class: href ? "row-link" : "" });
      let detail = null;
      if (expand) {
        const btn = h("button", { class: "icon-btn sm disc", type: "button", "aria-expanded": "false", "aria-label": "Show details" }, icon("right", { size: 14 }));
        btn.addEventListener("click", (e) => {
          e.stopPropagation();
          const open = btn.getAttribute("aria-expanded") === "true";
          btn.setAttribute("aria-expanded", String(!open));
          tr.classList.toggle("is-open", !open);
          if (open) { detail?.remove(); detail = null; } else {
            detail = h("tr", { class: "row-detail" }, h("td", { colspan: String(allCols.length) }, expand(it)));
            tr.after(detail);
          }
        });
        tr.appendChild(h("td", { class: "col-x" }, btn));
      }
      for (const c of columns) {
        let v;
        try { v = c.render(it); } catch { v = "–"; }
        tr.appendChild(h("td", { class: (c.cls || "") + (c.align === "right" ? " num" : "") }, v));
      }
      if (href) {
        tr.addEventListener("click", (e) => {
          if (e.target.closest("a, button, input, select, textarea")) return;
          if (window.getSelection()?.toString()) return;
          location.hash = href;
        });
      }
      tbody.appendChild(tr);
    }
    const from = page * limit + (items.length ? 1 : 0);
    info.textContent = items.length ? `${from}–${page * limit + items.length}${next ? "" : " (end)"}` : "";
    prev.disabled = page === 0;
    nextBtn.disabled = !next;
    foot.hidden = !items.length && page === 0;
  }

  async function fetchPage({ quiet = false } = {}) {
    const my = ++gen;
    if (!loadedOnce) skeleton();
    else if (!quiet) el.classList.add("is-loading");
    el.setAttribute("aria-busy", "true");
    try {
      const res = await load({ ...params, limit, cursor: cursors[page] || undefined });
      if (my !== gen) return;
      items = Array.isArray(res?.items) ? res.items : [];
      next = res?.next || null;
      loadedOnce = true;
      render();
      onData?.(items);
    } catch (err) {
      if (my !== gen) return;
      if (err.status === 401) return;
      if (!loadedOnce || !quiet) {
        clear(tbody);
        clear(stateBox).appendChild(errorState(err, () => fetchPage()));
        foot.hidden = true;
      }
      if (quiet) return;
      toastErr(err);
    } finally {
      if (my === gen) {
        el.classList.remove("is-loading");
        el.removeAttribute("aria-busy");
        tickTimes(el);
      }
    }
  }

  prev.addEventListener("click", () => { if (page > 0) { page--; fetchPage(); } });
  nextBtn.addEventListener("click", () => {
    if (!next) return;
    cursors = cursors.slice(0, page + 1);
    cursors.push(next);
    page++;
    fetchPage();
    scroller.scrollIntoView({ block: "nearest" });
  });

  return {
    el,
    /** New filters: back to page 1. */
    setParams(p) { params = p; cursors = [null]; page = 0; fetchPage(); },
    /** Same page again (auto-refresh): no dimming, no error toast. */
    refresh() { return fetchPage({ quiet: true }); },
    get page() { return page; },
  };
}
