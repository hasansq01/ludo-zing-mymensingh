// Pawn skins at online tables: the hello's `pawn` travels to lobby members and to the match's seats (start / sync),
// only when the account owns that skin (else Classic, ""); a hello without one (an older client) shows the account's
// own; quick matches carry the queued skin, and ghosts wear a plausible mix.
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { item } from "../src/econ";
import { GHOST_PAWNS, ghostPawn } from "../src/ghosts";
import { Mulberry32 } from "../src/rules/rng";
import { pawnFor } from "../src/room";
import { ok, setAccount } from "./acc_helpers";
import { Client, NEAR_GOAL, createRoom, newPid, startAll, type Msg } from "./room_client";
import { QuickClient, guest, joinMatched, mmHooks, resetSpies, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

/** A guest account that owns these skins (bought through the wallet; the last one bought is in use). */
async function owner(...ids: string[]): Promise<Guest> {
  const g = await guest();
  await setAccount(g.account, { coins: 50_000, gems: 1000 });
  for (const id of ids) {
    const gemsOnly = !item("pawn", id)!.buy;
    await ok("shop/buy", { session: g.session, body: { kind: "pawn", id, ...(gemsOnly ? { currency: "gems" } : {}) } });
  }
  return g;
}

describe("pawnFor", () => {
  it("a known skin the account owns, else Classic", () => {
    expect(pawnFor("crown", ["classic", "crown"])).toBe("crown");
    expect(pawnFor("crown", ["classic"])).toBe("");
    expect(pawnFor("crown", null)).toBe("");
    expect(pawnFor("classic", ["classic"])).toBe("");
    expect(pawnFor("nope", ["nope"])).toBe("");
    expect(pawnFor("x".repeat(40), null)).toBe("");
    expect(pawnFor(7, ["classic"])).toBe("");
    expect(pawnFor(undefined, ["classic", "trim"])).toBe("");
  });
});

describe("pawn skins in friend rooms", () => {
  it("hello -> lobby -> start seats: owned skins travel, unowned and unknown ones become Classic", async () => {
    const code = await createRoom({ ratePerSec: 1000, tok: NEAR_GOAL });
    const a = await owner("trim");
    const b = await guest(); // owns nothing
    const d = await owner("marble"); // marble in use, says nothing (an older client)
    const ca = await Client.join(code, { pid: a.pid, session: a.session, name: "A", pawn: "trim" });
    const cb = await Client.join(code, { pid: b.pid, session: b.session, name: "B", pawn: "crown" });
    const cc = await Client.join(code, { pid: newPid(), name: "C", pawn: "marble" }); // no account at all
    const cd = await Client.join(code, { pid: d.pid, session: d.session, name: "D" });
    const l = await ca.waitFor((m) => m.t === "lobby" && m.members.length === 4);
    expect(l.members.map((m: Msg) => [m.name, m.pawn])).toEqual([["A", "trim"], ["B", ""], ["C", ""], ["D", "marble"]]);
    const starts = await startAll([ca, cb, cc, cd]);
    const byName = Object.fromEntries(starts[1].seats.map((s: Msg) => [s.name, s.pawn]));
    expect(byName).toEqual({ A: "trim", B: "", C: "", D: "marble" });
    for (const st of starts) expect(st.seats).toEqual(starts[0].seats); // everyone sees the same skins
    // a reconnect (sync) carries them too
    cb.close();
    const again = await Client.join(code, { pid: b.pid, session: b.session, name: "B", pawn: "crown" });
    const sync = await again.wait("sync");
    expect(Object.fromEntries(sync.seats.map((s: Msg) => [s.name, s.pawn]))).toEqual(byName);
    for (const c of [ca, cc, cd, again]) c.close();
  });

  it("a member changes skin in the lobby by saying hello again", async () => {
    const code = await createRoom({ ratePerSec: 1000 });
    const a = await owner("kitty", "glitter"); // glitter in use
    const c1 = await Client.join(code, { pid: a.pid, session: a.session, name: "A", pawn: "glitter" });
    expect((await c1.wait("lobby")).members[0].pawn).toBe("glitter");
    const c2 = await Client.join(code, { pid: a.pid, session: a.session, name: "A", pawn: "kitty" });
    const l = await c2.waitFor((m) => m.t === "lobby" && m.members[0].pawn === "kitty");
    expect(l.members.length).toBe(1);
    c2.close();
  });
});

describe("pawn skins in quick matches", () => {
  it("the queued skin (owned) reaches the seats; ghosts wear known skins or Classic", async () => {
    await mmHooks("ludo", 4, { wait: 300, room: { tok: NEAR_GOAL, timeScale: 0.05 } });
    const g = await owner("crown");
    const q = await QuickClient.queue("ludo", 4, g, "Rakibul", { pawn: "crown" });
    const m = await q.wait("matched");
    q.close();
    const c = await joinMatched(m.code, m.token, g, "Rakibul");
    const st = await c.wait("start", 8000);
    const mine = st.seats.find((s: Msg) => s.id === c.id);
    expect(mine.pawn).toBe("crown");
    for (const s of st.seats) expect(s.pawn === "" || item("pawn", s.pawn) !== undefined).toBe(true);
    c.close();
  });

  it("an unowned queued skin becomes Classic", async () => {
    await mmHooks("ludo", 2, { wait: 300, room: { tok: NEAR_GOAL, timeScale: 0.05 } });
    const g = await guest();
    const q = await QuickClient.queue("ludo", 2, g, "Rakibul", { pawn: "knight" });
    const m = await q.wait("matched");
    q.close();
    const c = await joinMatched(m.code, m.token, g, "Rakibul");
    const st = await c.wait("start", 8000);
    expect(st.seats.find((s: Msg) => s.id === c.id).pawn).toBe("");
    c.close();
  });

  it("ghost skins: about half Classic, the rest a mix of every listed skin, all of them real", () => {
    expect(GHOST_PAWNS.every(([id]) => id === "" || item("pawn", id) !== undefined)).toBe(true);
    const rng = new Mulberry32(7);
    const seen = new Map<string, number>();
    for (let k = 0; k < 4000; k++) {
      const p = ghostPawn(rng);
      seen.set(p, (seen.get(p) ?? 0) + 1);
    }
    expect([...seen.keys()].sort()).toEqual(GHOST_PAWNS.map(([id]) => id).sort());
    const classic = (seen.get("") ?? 0) / 4000;
    expect(classic).toBeGreaterThan(0.4);
    expect(classic).toBeLessThan(0.6);
  });
});
