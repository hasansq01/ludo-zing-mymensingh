// Inline-SVG charts: a multi-series daily line chart (one y axis, crosshair + tooltip, keyboard, table view)
// and stat-tile sparklines. Series colours are CSS tokens (--series-1/2), validated for light and dark surfaces.
import { h, s, clear, fmtInt, compact } from "./dom.js";
import { icon } from "./icons.js";

/** Clean y scale: a 1 / 2 / 5 × 10^k step, about four intervals. */
function niceScale(v) {
  const raw = Math.max(1, v) / 4;
  const p = Math.pow(10, Math.floor(Math.log10(raw)));
  const step = [1, 2, 5, 10].map((m) => m * p).find((s) => s >= raw);
  const st = Math.max(1, step);
  return { max: Math.ceil(Math.max(1, v) / st) * st, step: st };
}

const DAY_FMT = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" });
const DAY_LONG = new Intl.DateTimeFormat(undefined, { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" });
const dayDate = (d) => new Date(d + "T00:00:00Z");

/**
 * series: [{key, name, tone: 1|2, values: number[]}], days: ["YYYY-MM-DD"] (or any x keys, with fmtShort / fmtLong
 * for the axis and the tooltip, e.g. ISO hours; pointLabel heads the table's first column)
 */
export function lineChart({ title, days, series, yLabel = "Per day", xLabel = "Day (UTC)", height = 248, pointLabel = "Day", fmtShort = (d) => DAY_FMT.format(dayDate(d)), fmtLong = (d) => DAY_LONG.format(dayDate(d)) }) {
  const legend = h("ul", { class: "legend", "aria-label": "Legend" }, series.map((sr) =>
    h("li", null, h("span", { class: "lkey lkey-line tone-" + sr.tone, "aria-hidden": "true" }), sr.name)));
  const viewBtn = h("button", { class: "btn btn-sm btn-ghost", type: "button", "aria-pressed": "false" }, icon("table", { size: 14 }), "Table");
  const plot = h("div", { class: "chart-plot" });
  const tip = h("div", { class: "chart-tip", role: "presentation", hidden: true });
  const tableBox = h("div", { class: "chart-table", hidden: true });
  const el = h("figure", { class: "chart" },
    h("div", { class: "chart-top" }, legend, viewBtn),
    h("div", { class: "chart-stage" }, plot, tip),
    tableBox,
    h("figcaption", { class: "sr-only" }, title));

  viewBtn.addEventListener("click", () => {
    const on = viewBtn.getAttribute("aria-pressed") !== "true";
    viewBtn.setAttribute("aria-pressed", String(on));
    clear(viewBtn).append(icon(on ? "chart" : "table", { size: 14 }), on ? "Chart" : "Table");
    plot.parentElement.hidden = on;
    tableBox.hidden = !on;
  });

  // table view (every value reachable without hovering)
  tableBox.appendChild(h("div", { class: "tbl-scroll" }, h("table", { class: "tbl tbl-dense" },
    h("thead", null, h("tr", null, h("th", { scope: "col" }, pointLabel), series.map((sr) => h("th", { scope: "col", class: "num" }, sr.name)))),
    h("tbody", null, days.map((d, i) => h("tr", null, h("td", null, fmtLong(d)),
      series.map((sr) => h("td", { class: "num" }, fmtInt(sr.values[i])))))))));

  let width = 0;
  let idx = -1;
  let geo = null;

  function draw() {
    const W = Math.max(280, width);
    const H = height;
    const m = { l: 44, r: 92, t: 14, b: 40 };
    if (W < 420) m.r = 16;
    const iw = W - m.l - m.r;
    const ih = H - m.t - m.b;
    const n = days.length;
    const sc = niceScale(Math.max(1, ...series.flatMap((sr) => sr.values)));
    const maxV = sc.max;
    const x = (i) => m.l + (n <= 1 ? iw / 2 : (i * iw) / (n - 1));
    const y = (v) => m.t + ih - (v / maxV) * ih;
    geo = { x, y, m, iw, ih, W, H, n };

    const svg = s("svg", {
      viewBox: `0 0 ${W} ${H}`, width: W, height: H, class: "chart-svg", tabindex: "0", role: "img",
      "aria-label": `${title}. ${series.map((sr) => `${sr.name}: ${sr.values.join(", ")}`).join(". ")}. Use the arrow keys to read each day.`,
    });
    // grid + y ticks
    for (let v = 0; v <= maxV + 1e-9; v += sc.step) {
      const k = v;
      const yy = y(v);
      svg.appendChild(s("line", { x1: m.l, x2: m.l + iw, y1: yy, y2: yy, class: k === 0 ? "c-base" : "c-grid" }));
      svg.appendChild(s("text", { x: m.l - 8, y: yy + 4, class: "c-tick", "text-anchor": "end" }, compact(v)));
    }
    // x ticks: every other day, always the last
    const every = n > 10 && W < 640 ? 3 : n > 7 ? 2 : 1;
    days.forEach((d, i) => {
      if ((n - 1 - i) % every !== 0) return;
      svg.appendChild(s("line", { x1: x(i), x2: x(i), y1: m.t + ih, y2: m.t + ih + 4, class: "c-base" }));
      svg.appendChild(s("text", { x: x(i), y: m.t + ih + 18, class: "c-tick", "text-anchor": "middle" }, fmtShort(d)));
    });
    // axis titles
    svg.appendChild(s("text", { x: m.l + iw / 2, y: H - 4, class: "c-axis", "text-anchor": "middle" }, xLabel));
    svg.appendChild(s("text", { x: 12, y: m.t + ih / 2, class: "c-axis", "text-anchor": "middle", transform: `rotate(-90 12 ${m.t + ih / 2})` }, yLabel));

    // lines
    for (const sr of series) {
      const d = sr.values.map((v, i) => (i ? "L" : "M") + x(i).toFixed(1) + " " + y(v).toFixed(1)).join(" ");
      svg.appendChild(s("path", { d, class: "c-line tone-" + sr.tone }));
    }
    // end dots + direct labels (skipped when they would collide; the legend + tooltip carry them then)
    const ends = series.map((sr) => ({ sr, yy: y(sr.values[n - 1] || 0) }));
    const collide = ends.length > 1 && Math.abs(ends[0].yy - ends[1].yy) < 26;
    for (const e of ends) {
      svg.appendChild(s("circle", { cx: x(n - 1), cy: e.yy, r: 4, class: "c-dot tone-" + e.sr.tone }));
      if (!collide && m.r > 40) {
        svg.appendChild(s("text", { x: x(n - 1) + 10, y: e.yy - 2, class: "c-endv" }, fmtInt(e.sr.values[n - 1])));
        svg.appendChild(s("text", { x: x(n - 1) + 10, y: e.yy + 11, class: "c-endl" }, e.sr.name));
      }
    }
    // crosshair layer
    const cross = s("g", { class: "c-cross", visibility: "hidden" },
      s("line", { y1: m.t, y2: m.t + ih, class: "c-crossline" }),
      series.map((sr) => s("circle", { r: 4.5, class: "c-dot tone-" + sr.tone })));
    svg.appendChild(cross);
    const hit = s("rect", { x: m.l - 12, y: m.t, width: iw + 24, height: ih + 20, class: "c-hit" });
    svg.appendChild(hit);

    const show = (i) => {
      idx = i;
      if (i < 0) { cross.setAttribute("visibility", "hidden"); tip.hidden = true; return; }
      cross.setAttribute("visibility", "visible");
      const [ln, ...dots] = cross.children;
      ln.setAttribute("x1", x(i)); ln.setAttribute("x2", x(i));
      series.forEach((sr, k) => { dots[k].setAttribute("cx", x(i)); dots[k].setAttribute("cy", y(sr.values[i])); });
      clear(tip).append(h("div", { class: "tip-head" }, fmtLong(days[i])),
        ...series.map((sr) => h("div", { class: "tip-row" }, h("span", { class: "lkey lkey-line tone-" + sr.tone }),
          h("strong", null, fmtInt(sr.values[i])), h("span", { class: "tip-name" }, sr.name))));
      tip.hidden = false;
      const tw = tip.offsetWidth;
      let left = x(i) + 14;
      if (left + tw > W - 4) left = x(i) - tw - 14;
      tip.style.left = Math.max(4, left) + "px";
      tip.style.top = m.t + 4 + "px";
    };
    hit.addEventListener("pointermove", (e) => {
      const r = svg.getBoundingClientRect();
      const px = ((e.clientX - r.left) / r.width) * W;
      const i = Math.round(((px - m.l) / iw) * (n - 1));
      show(Math.max(0, Math.min(n - 1, i)));
    });
    hit.addEventListener("pointerleave", () => show(-1));
    svg.addEventListener("blur", () => show(-1));
    svg.addEventListener("focus", () => show(idx >= 0 ? idx : n - 1));
    svg.addEventListener("keydown", (e) => {
      if (e.key === "ArrowRight" || e.key === "ArrowLeft") {
        e.preventDefault();
        const cur = idx < 0 ? n - 1 : idx;
        show(Math.max(0, Math.min(n - 1, cur + (e.key === "ArrowRight" ? 1 : -1))));
      } else if (e.key === "Home") { e.preventDefault(); show(0); } else if (e.key === "End") { e.preventDefault(); show(n - 1); } else if (e.key === "Escape") show(-1);
    });
    clear(plot).appendChild(svg);
  }

  const ro = new ResizeObserver((entries) => {
    const w = Math.floor(entries[0].contentRect.width);
    if (w && Math.abs(w - width) > 2) { width = w; draw(); }
  });
  ro.observe(plot);
  el.destroy = () => ro.disconnect();
  return el;
}

/** 14-point sparkline for a stat tile: de-emphasised line, the latest point in the accent. */
export function sparkline(values, label) {
  const W = 96, H = 28, n = values.length;
  if (n < 2) return null;
  const max = Math.max(1, ...values);
  const x = (i) => 2 + (i * (W - 6)) / (n - 1);
  const y = (v) => H - 3 - (v / max) * (H - 7);
  const d = values.map((v, i) => (i ? "L" : "M") + x(i).toFixed(1) + " " + y(v).toFixed(1)).join(" ");
  return s("svg", { viewBox: `0 0 ${W} ${H}`, width: W, height: H, class: "spark", role: "img", "aria-label": label },
    s("path", { d, class: "spark-line" }),
    s("circle", { cx: x(n - 1), cy: y(values[n - 1]), r: 3, class: "spark-dot" }));
}
