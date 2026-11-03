// Mini Ludo board in SVG, drawn from a LudoRules state (the same geometry as godot/scripts/world/ludo_board.gd:
// 15×15 grid, TRACK starting at Red's OFF square, HOME columns, BASE corners, FIN lanes in the centre).
// Pawns keep their element between updates so CSS transitions animate moves.
import { s, clear } from "./dom.js";

export const TRACK = [[1,6],[2,6],[3,6],[4,6],[5,6],[6,5],[6,4],[6,3],[6,2],[6,1],[6,0],[7,0],[8,0],[8,1],[8,2],[8,3],[8,4],[8,5],[9,6],[10,6],[11,6],[12,6],[13,6],[14,6],[14,7],[14,8],[13,8],[12,8],[11,8],[10,8],[9,8],[8,9],[8,10],[8,11],[8,12],[8,13],[8,14],[7,14],[6,14],[6,13],[6,12],[6,11],[6,10],[6,9],[5,8],[4,8],[3,8],[2,8],[1,8],[0,8],[0,7],[0,6]];
export const HOME = [
  [[1,7],[2,7],[3,7],[4,7],[5,7]],
  [[7,1],[7,2],[7,3],[7,4],[7,5]],
  [[13,7],[12,7],[11,7],[10,7],[9,7]],
  [[7,13],[7,12],[7,11],[7,10],[7,9]],
];
export const BASE = [[0,0],[9,0],[9,9],[0,9]];
export const OFF = [0, 13, 26, 39];
export const STARS = [8, 21, 34, 47];
export const GOAL = 56;
const FIN = [{ x: 6.55, y: 7.5, ax: "y" }, { x: 7.5, y: 6.55, ax: "x" }, { x: 8.45, y: 7.5, ax: "y" }, { x: 7.5, y: 8.45, ax: "x" }];

const PLAYER = ["#e5484d", "#2fa86b", "#f4c430", "#3b7be0"];
const PLAYER_DARK = ["#b8282d", "#1f8a52", "#c99a12", "#2a63bf"];
const TINT = ["#f9d4d2", "#cdebd9", "#fbedbd", "#cfdcf6"];
const CREAM = "#fffaf3";

/** Grid position (cell centre, in squares) of pawn i of colour c at progress p. */
export function gridOf(c, p, i) {
  if (p < 0) {
    const b = BASE[c];
    return [b[0] + 2 + (i % 2) * 2, b[1] + 2 + Math.floor(i / 2) * 2];
  }
  if (p <= 50) {
    const t = TRACK[(OFF[c] + p) % 52];
    return [t[0] + 0.5, t[1] + 0.5];
  }
  if (p < GOAL) {
    const hc = HOME[c][p - 51];
    return [hc[0] + 0.5, hc[1] + 0.5];
  }
  const f = FIN[c];
  const o = (i - 1.5) * 0.46;
  return f.ax === "y" ? [f.x, f.y + o] : [f.x + o, f.y];
}

function star(cx, cy, r) {
  const pts = [];
  for (let k = 0; k < 10; k++) {
    const a = -Math.PI / 2 + (k * Math.PI) / 5;
    const rr = k % 2 ? r * 0.45 : r;
    pts.push((cx + Math.cos(a) * rr).toFixed(3) + "," + (cy + Math.sin(a) * rr).toFixed(3));
  }
  return s("polygon", { points: pts.join(" ") });
}

function drawBoard() {
  const g = s("g", { class: "b-static" });
  g.appendChild(s("rect", { x: 0, y: 0, width: 15, height: 15, rx: 0.35, fill: CREAM }));
  for (let c = 0; c < 4; c++) {
    const [bx, by] = BASE[c];
    g.appendChild(s("rect", { x: bx, y: by, width: 6, height: 6, fill: PLAYER[c], class: "b-base b-base-" + c }));
    g.appendChild(s("rect", { x: bx + 1, y: by + 1, width: 4, height: 4, rx: 0.45, fill: CREAM }));
    for (let i = 0; i < 4; i++) {
      const [x, y] = gridOf(c, -1, i);
      g.appendChild(s("circle", { cx: x, cy: y, r: 0.62, fill: TINT[c], stroke: PLAYER[c], "stroke-width": 0.09 }));
    }
    for (const [x, y] of HOME[c]) g.appendChild(s("rect", { x, y, width: 1, height: 1, fill: PLAYER[c] }));
    const st = TRACK[OFF[c]];
    g.appendChild(s("rect", { x: st[0], y: st[1], width: 1, height: 1, fill: PLAYER[c] }));
    const sp = star(st[0] + 0.5, st[1] + 0.5, 0.32);
    sp.setAttribute("fill", CREAM);
    g.appendChild(sp);
  }
  for (const k of STARS) {
    const t = TRACK[k];
    const sp = star(t[0] + 0.5, t[1] + 0.5, 0.34);
    sp.setAttribute("fill", "#d9c3cf");
    g.appendChild(sp);
  }
  const tri = [[[6, 6], [6, 9]], [[6, 6], [9, 6]], [[9, 6], [9, 9]], [[6, 9], [9, 9]]];
  for (let c = 0; c < 4; c++) {
    const [a, b] = tri[c];
    g.appendChild(s("polygon", { points: `${a[0]},${a[1]} ${b[0]},${b[1]} 7.5,7.5`, fill: PLAYER[c] }));
  }
  const line = { fill: "none", stroke: "rgba(110,70,95,.38)", "stroke-width": 0.035 };
  const cells = TRACK.concat(...HOME);
  for (const [x, y] of cells) g.appendChild(s("rect", { x, y, width: 1, height: 1, ...line }));
  g.appendChild(s("rect", { x: 6, y: 6, width: 3, height: 3, ...line }));
  for (const [x, y] of BASE) g.appendChild(s("rect", { x, y, width: 6, height: 6, ...line }));
  g.appendChild(s("rect", { x: 0.03, y: 0.03, width: 14.94, height: 14.94, rx: 0.33, ...line, "stroke-width": 0.06 }));
  return g;
}

function pawnEl(c) {
  return s("g", { class: "pawn" },
    s("ellipse", { cx: 0.04, cy: 0.12, rx: 0.36, ry: 0.3, fill: "rgba(60,25,40,.28)" }),
    s("circle", { r: 0.34, fill: PLAYER[c], stroke: PLAYER_DARK[c], "stroke-width": 0.07 }),
    s("circle", { r: 0.15, fill: "#fff", "fill-opacity": 0.32, cx: -0.08, cy: -0.1 }));
}

const SPREAD = {
  1: [[0, 0]],
  2: [[-0.22, 0], [0.22, 0]],
  3: [[-0.22, -0.2], [0.22, -0.2], [0, 0.22]],
  4: [[-0.22, -0.22], [0.22, -0.22], [-0.22, 0.22], [0.22, 0.22]],
};

/** createBoard() → {el, update(state)}; state = LudoRules state or null (empty board). */
export function createBoard({ label = "Ludo board" } = {}) {
  const svg = s("svg", { viewBox: "-0.2 -0.2 15.4 15.4", class: "board", role: "img", "aria-label": label });
  svg.appendChild(drawBoard());
  const veils = BASE.map(([x, y]) => s("rect", { x, y, width: 6, height: 6, class: "b-veil", visibility: "hidden" }));
  veils.forEach((v) => svg.appendChild(v));
  const turnRing = s("rect", { width: 6, height: 6, rx: 0.3, class: "b-turn", fill: "none", visibility: "hidden" });
  svg.appendChild(turnRing);
  const pawnLayer = s("g", { class: "b-pawns" });
  const badgeLayer = s("g", { class: "b-badges" });
  svg.appendChild(pawnLayer);
  svg.appendChild(badgeLayer);
  const pawns = [];
  for (let c = 0; c < 4; c++) {
    pawns.push([]);
    for (let i = 0; i < 4; i++) {
      const p = pawnEl(c);
      p.style.transform = `translate(${gridOf(c, -1, i)[0]}px, ${gridOf(c, -1, i)[1]}px)`;
      pawnLayer.appendChild(p);
      pawns[c].push(p);
    }
  }

  function update(state) {
    clear(badgeLayer);
    const tok = state?.tok;
    const players = state?.players || ["off", "off", "off", "off"];
    veils.forEach((v, c) => v.setAttribute("visibility", state && players[c] === "off" ? "visible" : "hidden"));
    // group pawns by cell (track / home); base and goal positions are unique per pawn
    const cells = new Map();
    for (let c = 0; c < 4; c++) {
      for (let i = 0; i < 4; i++) {
        const p = tok ? Number(tok[c]?.[i] ?? -1) : -1;
        const el = pawns[c][i];
        const off = players[c] === "off";
        el.classList.toggle("is-off", off);
        el.setAttribute("visibility", off ? "hidden" : "visible");
        el.classList.toggle("is-turn", !!state && state.turn === c && state.phase !== "over");
        const [x, y] = gridOf(c, p, i);
        if (p >= 0 && p < GOAL) {
          const key = x + ":" + y;
          if (!cells.has(key)) cells.set(key, { x, y, byColor: new Map() });
          const cell = cells.get(key);
          if (!cell.byColor.has(c)) cell.byColor.set(c, []);
          cell.byColor.get(c).push(i);
        } else {
          el.style.transform = `translate(${x}px, ${y}px) scale(${p >= GOAL ? 0.72 : 1})`;
        }
      }
    }
    for (const cell of cells.values()) {
      const colours = [...cell.byColor.keys()];
      const spots = SPREAD[Math.min(4, colours.length)];
      const scale = colours.length > 1 ? 0.7 : 1;
      colours.forEach((c, k) => {
        const [dx, dy] = spots[k] || [0, 0];
        const list = cell.byColor.get(c);
        list.forEach((i, j) => {
          pawns[c][i].style.transform = `translate(${cell.x + dx + j * 0.03}px, ${cell.y + dy - j * 0.03}px) scale(${scale})`;
        });
        if (list.length > 1) {
          const bx = cell.x + dx + 0.3 * scale, by = cell.y + dy - 0.3 * scale;
          badgeLayer.appendChild(s("g", { class: "b-badge" },
            s("circle", { cx: bx, cy: by, r: 0.27 }),
            s("text", { x: bx, y: by + 0.115, "text-anchor": "middle" }, String(list.length))));
        }
      });
    }
    if (state && state.phase !== "over" && state.turn >= 0 && state.turn <= 3) {
      const [bx, by] = BASE[state.turn];
      turnRing.setAttribute("x", bx);
      turnRing.setAttribute("y", by);
      turnRing.setAttribute("visibility", "visible");
    } else turnRing.setAttribute("visibility", "hidden");
  }

  update(null);
  return { el: svg, update };
}

/** Die face (SVG) for value v (1–6); 0 / missing → blank face. */
export function dieFace(v, size = 34) {
  const pips = {
    1: [[2, 2]], 2: [[1, 1], [3, 3]], 3: [[1, 1], [2, 2], [3, 3]], 4: [[1, 1], [3, 1], [1, 3], [3, 3]],
    5: [[1, 1], [3, 1], [2, 2], [1, 3], [3, 3]], 6: [[1, 1], [3, 1], [1, 2], [3, 2], [1, 3], [3, 3]],
  };
  const svg = s("svg", { viewBox: "0 0 4 4", width: size, height: size, class: "die", role: "img", "aria-label": v ? "Dice " + v : "Not rolled" },
    s("rect", { x: 0.15, y: 0.25, width: 3.7, height: 3.7, rx: 0.8, class: "die-lip" }),
    s("rect", { x: 0.15, y: 0.1, width: 3.7, height: 3.6, rx: 0.8, class: "die-face" }));
  for (const [x, y] of pips[v] || []) svg.appendChild(s("circle", { cx: x * 0.95 + 0.1, cy: y * 0.9, r: 0.36, class: "die-pip" }));
  if (!pips[v]) svg.appendChild(s("text", { x: 2, y: 2.35, "text-anchor": "middle", class: "die-q" }, "–"));
  return svg;
}
