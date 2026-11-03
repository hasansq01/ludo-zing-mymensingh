// GDScript value semantics the economy relies on, so the port reads the same profile data the same way.
// Profiles come from JSON, where every number is a float in Godot; these helpers mirror int(), `is Dictionary`,
// `is Array`, String.strip_edges() and Rewards._is_int().

export type Dict = Record<string, unknown>;

export function isDict(v: unknown): v is Dict {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function isArray(v: unknown): v is unknown[] {
  return Array.isArray(v);
}

/** String.to_int(): digits before the first ".", every other character skipped, a "-" before any digit flips the sign. */
export function stringToInt(s: string): number {
  const dot = s.indexOf(".");
  const to = dot >= 0 ? dot : s.length;
  let n = 0;
  let sign = 1;
  for (let i = 0; i < to; i++) {
    const c = s.charCodeAt(i);
    if (c >= 48 && c <= 57) n = n * 10 + (c - 48);
    else if (c === 45 && n === 0) sign = -sign;
  }
  return n * sign;
}

/**
 * int(v): floats truncate toward zero, bools are 0 / 1, strings use String.to_int(). Godot raises a script error for
 * null, arrays and dictionaries; the port returns `fallback` there instead (a server must never throw on stored data).
 */
export function toInt(v: unknown, fallback = 0): number {
  if (typeof v === "number") return Number.isFinite(v) ? Math.trunc(v) : fallback;
  if (typeof v === "boolean") return v ? 1 : 0;
  if (typeof v === "string") return stringToInt(v);
  return fallback;
}

/** int(d.get(key, dflt)): the default only when the key is missing (or, unlike Godot, null). */
export function getInt(d: Dict, key: string, dflt = 0): number {
  const v = d[key];
  return v === undefined || v === null ? dflt : toInt(v, dflt);
}

/** is_equal_approx(a, b) (CMP_EPSILON 1e-5, relative to a). */
export function isEqualApprox(a: number, b: number): boolean {
  if (a === b) return true;
  let tol = 0.00001 * Math.abs(a);
  if (tol < 0.00001) tol = 0.00001;
  return Math.abs(a - b) < tol;
}

/** Rewards._is_int: a whole number (JSON numbers load as floats). Bools are not ints. */
export function isGdInt(v: unknown): v is number {
  return typeof v === "number" && Number.isFinite(v) && isEqualApprox(v, Math.round(v));
}

/** String.strip_edges(): drops characters <= 32 at both ends. */
export function stripEdges(s: string): string {
  let a = 0;
  let b = s.length;
  while (a < b && s.charCodeAt(a) <= 32) a++;
  while (b > a && s.charCodeAt(b - 1) <= 32) b--;
  return s.slice(a, b);
}

/** _list(p, key): a copy of the array, [] when it isn't one. */
export function list(p: Dict, key: string): unknown[] {
  const v = p[key];
  return Array.isArray(v) ? v.slice() : [];
}

/** str(v) for the comparisons the game makes against ids ("" for missing values). */
export function str(v: unknown, dflt = ""): string {
  if (v === undefined) return dflt;
  if (typeof v === "string") return v;
  if (v === null) return "<null>";
  return String(v);
}

export function clone<T>(v: T): T {
  return structuredClone(v);
}

export function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}
