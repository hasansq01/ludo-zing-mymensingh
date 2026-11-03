// Settlement by progress (owner decision 2026-10-31, ECONOMY_V1.md §3 "Nobody connected"): a quick match frozen
// because no person was connected, and nobody came back within TIMING.abandonAfter, is ended for good and every seat
// (people, bots and ghosts alike) is placed by how far it got. Pure functions over the rules states; room.ts endAway
// applies them.
//
// Score of a side:
//   Ludo: pawns home first (tok = GOAL), then the distance travelled: the sum over its pawns of min(p, GOAL) + 1
//         (0 in base; a pair counts per pawn, as both pawns' tok move). Teams: the sum over both colours.
//   S&L:  the square reached (home 0, dist = pos).
// Order: sides that had already finished keep their real places first (in finish order); the rest follow by score
// (more pawns home, then more distance; ties: the lower colour first, as the rules' standings).
import * as L from "./rules/ludo";
import * as SL from "./rules/sl";
import { ECON_V1 } from "./econ/rules";

export type ProgressGame = "ludo" | "sl";

export interface ProgressScore {
  /** Ludo: pawns home (teams: of both colours); S&L: 0. */
  home: number;
  /** Ludo: steps travelled (teams: of both colours); S&L: the square. */
  dist: number;
}

export interface ProgressRanking {
  /** Every playing colour in final order. */
  order: number[];
  /** The colours placed by progress (their side had not finished before the settlement). */
  byProgress: number[];
  /** Each colour's score (Teams: its team's score). */
  scores: Record<number, ProgressScore>;
}

/** Ludo: colour c's own score (pawns home, steps travelled). */
export function ludoScore(s: L.LudoState, c: number): ProgressScore {
  let home = 0;
  let dist = 0;
  for (const p0 of s.tok[c] ?? []) {
    const p = Math.trunc(p0);
    if (p >= L.GOAL) home++;
    dist += Math.max(0, Math.min(p, L.GOAL) + 1);
  }
  return { home, dist };
}

/** S&L: colour c's square. */
export function slScore(g: SL.SlState, c: number): ProgressScore {
  const p = g.players.find((x) => x.c === c);
  return { home: 0, dist: p ? Math.max(0, Math.trunc(p.pos)) : 0 };
}

/** a is ahead of b (more pawns home, then more distance). */
function ahead(a: ProgressScore, b: ProgressScore): boolean {
  return a.home !== b.home ? a.home > b.home : a.dist > b.dist;
}

function cmp(a: ProgressScore, b: ProgressScore, ca: number, cb: number): number {
  if (ahead(a, b)) return -1;
  if (ahead(b, a)) return 1;
  return ca - cb;
}

function add(a: ProgressScore, b: ProgressScore): ProgressScore {
  return { home: a.home + b.home, dist: a.dist + b.dist };
}

/** The final order of a match ended by the settlement (see the file comment). */
export function rankByProgress(game: ProgressGame, state: unknown): ProgressRanking {
  if (game === "sl") {
    const g = state as SL.SlState;
    const fin = SL.finishedOf(g)
      .filter((k) => g.players[k])
      .map((k) => g.players[k].c);
    const scores: Record<number, ProgressScore> = {};
    for (const p of g.players) scores[p.c] = slScore(g, p.c);
    const rest = g.players.map((p) => p.c).filter((c) => !fin.includes(c));
    rest.sort((a, b) => cmp(scores[a], scores[b], a, b));
    return { order: [...fin, ...rest], byProgress: rest, scores };
  }
  const s = state as L.LudoState;
  const cols = [0, 1, 2, 3].filter((c) => L.active(s, c));
  const own: Record<number, ProgressScore> = {};
  for (const c of cols) own[c] = ludoScore(s, c);
  const fin = (s.finished ?? []).map((x) => Math.trunc(x));
  if (L.teamOn(s)) {
    // a team places only when it is done (that ends the game), so every team is placed by its score here
    const teams = [
      [0, 2],
      [1, 3],
    ].filter((t) => t.some((c) => cols.includes(c)));
    const scores: Record<number, ProgressScore> = {};
    const teamScore = (t: number[]): ProgressScore => t.filter((c) => own[c]).reduce((acc, c) => add(acc, own[c]), { home: 0, dist: 0 });
    for (const t of teams) for (const c of t) if (own[c]) scores[c] = teamScore(t);
    teams.sort((a, b) => cmp(teamScore(a), teamScore(b), a[0], b[0]));
    const order: number[] = [];
    for (const t of teams) {
      const members = t.filter((c) => cols.includes(c));
      // within a team: a member that finished first (in finish order), then by its own score
      members.sort((a, b) => {
        const fa = fin.indexOf(a);
        const fb = fin.indexOf(b);
        if (fa >= 0 !== fb >= 0) return fa >= 0 ? -1 : 1;
        if (fa >= 0) return fa - fb;
        return cmp(own[a], own[b], a, b);
      });
      order.push(...members);
    }
    return { order, byProgress: [...order], scores };
  }
  const done = fin.filter((c) => cols.includes(c));
  const rest = cols.filter((c) => !done.includes(c));
  rest.sort((a, b) => cmp(own[a], own[b], a, b));
  return { order: [...done, ...rest], byProgress: rest, scores: own };
}

/**
 * The anti-gaming rule: may a disconnected person placed 1st by progress take the 1st place money? Only with a
 * clear lead over the runner-up (the next side behind it in the order; none: clear). Ludo: more pawns home, or a
 * distance lead of more than ECON_V1.away_lead.ludo_track_pct percent of one pawn's full track (GOAL + 1 steps: 57,
 * so 15 steps or more). S&L: a lead of ECON_V1.away_lead.sl_squares squares or more.
 */
export function clearLead(game: ProgressGame, lead: ProgressScore, next: ProgressScore | undefined): boolean {
  if (!next) return true;
  if (game === "sl") return lead.dist - next.dist >= ECON_V1.away_lead.sl_squares;
  if (lead.home > next.home) return true;
  if (lead.home < next.home) return false;
  return (lead.dist - next.dist) * 100 > ECON_V1.away_lead.ludo_track_pct * (L.GOAL + 1);
}

/**
 * Applies a settlement order to a state that the rules just ended ({k: "end"}): the order becomes s.finished and
 * its first side the winner (Ludo standings() then follow it; S&L keeps player indices).
 */
export function applyOrder(game: ProgressGame, state: unknown, order: number[]): void {
  if (game === "sl") {
    const g = state as SL.SlState;
    const idx = order.map((c) => g.players.findIndex((p) => p.c === c)).filter((k) => k >= 0);
    g.finished = idx;
    if (idx.length) g.winner = idx[0];
    return;
  }
  const s = state as L.LudoState;
  s.finished = [...order];
  if (order.length) s.winner = order[0];
}
