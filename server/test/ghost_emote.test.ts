// The ghosts' emote policy (src/ghosts.ts ghostEmoteReply): pure and seeded, so every behaviour is checked over many
// seeded runs: variety, no repeats, spam decay and silence, conversations of 1-3 replies, personalities, situation
// biases, owned packs only, delays, the humans' rate limits, memory that survives JSON (hibernation).
import { describe, expect, it } from "vitest";
import {
  EMOTE_PACKS,
  GHOST_DELAY_MAX,
  GHOST_EMOTE,
  PERSONAS,
  ghostEmoteReply,
  ghostPersonas,
  ghostPool,
  newGhostMemory,
  packOfEmote,
  progressLead,
  type GhostMemory,
  type GhostSituation,
  type GhostTrigger,
  type Persona,
} from "../src/ghosts";
import { Mulberry32 } from "../src/rules/rng";

/** Seeds 1, 2, 3... are scrambled and warmed up: Mulberry32 streams of adjacent seeds are correlated. */
const R = (k: number): Mulberry32 => {
  const r = new Mulberry32(Math.imul(k + 1, 2654435761) ^ 0x5bd1e995);
  r.next();
  r.next();
  return r;
};
const PACKS = ["pawns", "friends", "game"];
const ownedOf = (pack: string) => new Set([...EMOTE_PACKS.starter, ...(EMOTE_PACKS[pack] ?? [])]);
const human = (id: string, from = 1): GhostTrigger => ({ kind: "emote", id, from, human: true });
const SEC = 1000;

function count<T>(xs: T[]): Map<T, number> {
  const m = new Map<T, number>();
  for (const x of xs) m.set(x, (m.get(x) ?? 0) + 1);
  return m;
}

/** A human sends `ids` (cycled) every `every` ms; returns what one ghost answered, per emote (null = nothing). */
function spam(persona: Persona, pack: string, seed: number, n: number, every: number, id = "laugh", sit: Partial<GhostSituation> = {}) {
  const rng = R(seed);
  const mem = newGhostMemory();
  const out: Array<{ id: string; delayMs: number; at: number } | null> = [];
  for (let k = 0; k < n; k++) {
    const now = 1_000_000 + k * every;
    const r = ghostEmoteReply({ now, ...sit }, persona, mem, human(id), rng, pack);
    out.push(r ? { ...r, at: now + r.delayMs } : null);
  }
  return { out, mem };
}

describe("spam: loses interest", () => {
  it("20 identical emotes: varied replies, decaying to silence, never back to back, never in the last 12", () => {
    const first = new Map<string, number>();
    let early = 0;
    let late = 0;
    const seen = new Set<string>();
    for (let seed = 1; seed <= 300; seed++) {
      const persona = PERSONAS[seed % 5];
      const { out } = spam(persona, PACKS[seed % 3], seed, 20, 2 * SEC);
      const ids = out.filter((x) => x).map((x) => x!.id);
      for (let k = 1; k < ids.length; k++) expect(ids[k]).not.toBe(ids[k - 1]);
      // avoid its last 3
      for (let k = 3; k < ids.length; k++) expect(ids.slice(k - 3, k)).not.toContain(ids[k]);
      for (const i of ids) seen.add(i);
      if (out[0]) first.set(out[0].id, (first.get(out[0].id) ?? 0) + 1);
      early += out.slice(0, 3).filter((x) => x).length;
      late += out.slice(3).filter((x) => x).length;
      // the 4th emote may get an "ok, enough"; everything after that is silence (the sulk lasts 45-90 s)
      if (out[3]) expect(["facepalm", "sleepy"]).toContain(out[3].id);
      expect(out.slice(4).filter((x) => x)).toEqual([]);
    }
    expect(seen.size).toBeGreaterThanOrEqual(6); // not one fixed answer
    expect(first.size).toBeGreaterThanOrEqual(5);
    expect(early).toBeGreaterThan(120); // its own pace (4-12 s) blocks some answers to a 2 s spam
    expect(late).toBeLessThan(early / 2); // only the odd "ok, enough"
  });

  it("the first emote is answered about half the time, the second within 15 s about a quarter", () => {
    let a = 0;
    let b = 0;
    const N = 2000;
    for (let seed = 1; seed <= N; seed++) {
      const persona = PERSONAS[seed % 5];
      const { out } = spam(persona, "pawns", seed, 2, 12 * SEC, "happy");
      if (out[0]) a++;
      if (out[1]) b++;
    }
    expect(a / N).toBeGreaterThan(0.35);
    expect(a / N).toBeLessThan(0.65);
    expect(b / N).toBeGreaterThan(0.08);
    expect(b / N).toBeLessThan(a / N * 0.7);
  });

  it("an occasional 'ok, enough' (facepalm / sleepy), then a 45-90 s quiet period, and the window resets after 60 s", () => {
    let enough = 0;
    let quietOk = 0;
    for (let seed = 1; seed <= 400; seed++) {
      const rng = R(seed);
      const mem = newGhostMemory();
      let said: string | null = null;
      for (let k = 0; k < 6; k++) {
        const r = ghostEmoteReply({ now: k * 3 * SEC }, "sore", mem, human("angry"), rng, "friends");
        if (k === 3 && r) said = r.id;
      }
      if (said) {
        expect(["facepalm", "sleepy"]).toContain(said);
        enough++;
      }
      // sulking: quietUntil is 45-90 s after the 4th emote (t = 9 s); the others kept it going afterwards
      expect(mem.quietUntil - 9 * SEC).toBeGreaterThanOrEqual(45 * SEC);
      expect(mem.quietUntil - 9 * SEC).toBeLessThanOrEqual(90 * SEC);
      const during = ghostEmoteReply({ now: 40 * SEC }, "sore", mem, human("angry"), rng, "friends");
      expect(during).toBeNull();
      // 61 s after the last emote the window has reset: a first emote again, and it can be answered
      let ans = 0;
      for (let t = 0; t < 8; t++) {
        const m2: GhostMemory = JSON.parse(JSON.stringify(mem));
        if (ghostEmoteReply({ now: 200 * SEC + t * 70 * SEC }, "friendly", m2, human("hi"), R(seed * 31 + t), "friends")) ans++;
      }
      if (ans > 0) quietOk++;
    }
    expect(enough).toBeGreaterThan(20); // sore loser, owns facepalm: now and then (not every time)
    expect(enough).toBeLessThan(300);
    expect(quietOk).toBeGreaterThan(350);
  });
});

describe("conversations end", () => {
  it("a back-and-forth with one person ends after 1-3 of its replies, then it ignores that person for a while", () => {
    const lengths = new Map<number, number>();
    for (let seed = 1; seed <= 400; seed++) {
      const rng = R(seed);
      const mem = newGhostMemory();
      let replies = 0;
      let k = 0;
      for (; k < 80; k++) {
        const r = ghostEmoteReply({ now: k * 35 * SEC }, "friendly", mem, human("hi"), rng, "pawns");
        if (r) replies++;
        if (mem.threads["1"]?.until) break;
      }
      expect(k).toBeLessThan(80);
      expect(replies).toBeGreaterThanOrEqual(1);
      expect(replies).toBeLessThanOrEqual(3);
      lengths.set(replies, (lengths.get(replies) ?? 0) + 1);
      // the next emote from the same person is ignored (a 60-120 s thread ignore)
      expect(ghostEmoteReply({ now: (k + 1) * 35 * SEC }, "friendly", mem, human("hi"), rng, "pawns")).toBeNull();
      // but another person starts a new conversation
      let other = 0;
      for (let t = 0; t < 30; t++) if (ghostEmoteReply({ now: (k + 2) * 35 * SEC + t * 70 * SEC }, "friendly", mem, human("hi", 2), rng, "pawns")) other++;
      expect(other).toBeGreaterThan(0);
    }
    expect([...lengths.keys()].sort()).toEqual([1, 2, 3]);
  });
});

describe("personalities", () => {
  const rate = (persona: Persona, f: (rng: Mulberry32, mem: GhostMemory) => unknown, n = 1500) => {
    let hit = 0;
    for (let seed = 1; seed <= n; seed++) if (f(R(seed), newGhostMemory())) hit++;
    return hit / n;
  };
  const firstReply = (p: Persona) => rate(p, (rng, mem) => ghostEmoteReply({ now: 5 * SEC }, p, mem, human("hi"), rng, "pawns"));
  const onEvent = (p: Persona, kind: "capture" | "captured" | "six" | "finish") => rate(p, (rng, mem) => ghostEmoteReply({ now: 5 * SEC }, p, mem, { kind }, rng, "friends"));

  it("reply rates differ: chatty > friendly > cheeky > quiet", () => {
    const r = Object.fromEntries(PERSONAS.map((p) => [p, firstReply(p)]));
    expect(r.chatty).toBeGreaterThan(r.friendly);
    expect(r.friendly).toBeGreaterThan(r.quiet + 0.15);
    expect(r.chatty).toBeGreaterThan(r.quiet * 2);
    expect(r.cheeky).toBeGreaterThan(r.quiet);
  });

  it("event rates: sore loser sulks loudly after being captured, cheeky gloats, quiet rarely emotes", () => {
    expect(onEvent("sore", "captured")).toBeGreaterThan(onEvent("quiet", "captured") * 2);
    expect(onEvent("cheeky", "capture")).toBeGreaterThan(onEvent("friendly", "capture") * 1.5);
    expect(onEvent("chatty", "six")).toBeGreaterThan(onEvent("quiet", "six") * 3);
  });

  it("pool biases: cheeky teases, friendly loves, sore is angry", () => {
    const share = (p: Persona, trig: GhostTrigger, id: string, pack: string) => {
      let n = 0;
      let tot = 0;
      for (let seed = 1; seed <= 1500; seed++) {
        const r = ghostEmoteReply({ now: 5 * SEC, chance: 1 }, p, newGhostMemory(), trig, R(seed), pack);
        if (r) {
          tot++;
          if (r.id === id) n++;
        }
      }
      return n / tot;
    };
    expect(share("cheeky", human("laugh"), "tease", "friends")).toBeGreaterThan(share("friendly", human("laugh"), "tease", "friends") * 3);
    expect(share("friendly", human("hi"), "love", "pawns")).toBeGreaterThan(share("cheeky", human("hi"), "love", "pawns") * 2);
    expect(share("sore", { kind: "captured" }, "angry", "pawns")).toBeGreaterThan(share("friendly", { kind: "captured" }, "angry", "pawns") * 3);
  });

  it("ghosts of one match have different personalities (up to 5), and a lone ghost varies across matches", () => {
    for (let seed = 1; seed <= 200; seed++) {
      const ps = ghostPersonas(3, R(seed));
      expect(new Set(ps).size).toBe(3);
      expect(new Set(ghostPersonas(5, R(seed))).size).toBe(5);
    }
    const lone = count(Array.from({ length: 1000 }, (_, k) => ghostPersonas(1, R(k + 1))[0]));
    expect(lone.size).toBe(5);
    for (const v of lone.values()) expect(v).toBeGreaterThan(80);
  });

  it("chatty ghosts sometimes open with a hi (once); quiet ones never do", () => {
    let hi = 0;
    let other = 0;
    for (let seed = 1; seed <= 1000; seed++) {
      const mem = newGhostMemory();
      const rng = R(seed);
      const r = ghostEmoteReply({ now: 0 }, "chatty", mem, { kind: "open" }, rng, "pawns");
      if (r) {
        r.id === "hi" ? hi++ : other++;
        expect(r.delayMs).toBeGreaterThanOrEqual(GHOST_EMOTE.open[0]);
        expect(r.delayMs).toBeLessThanOrEqual(GHOST_EMOTE.open[1]);
      }
      expect(ghostEmoteReply({ now: 1 }, "chatty", mem, { kind: "open" }, rng, "pawns")).toBeNull(); // once
      expect(ghostEmoteReply({ now: 0 }, "quiet", newGhostMemory(), { kind: "open" }, rng, "pawns")).toBeNull();
    }
    expect(hi / 1000).toBeGreaterThan(0.25);
    expect(hi / 1000).toBeLessThan(0.55);
    expect(hi).toBeGreaterThan(other * 2);
  });
});

describe("situation shifts the weights", () => {
  const weight = (pool: Array<[string, number]>, ids: string[]) => pool.filter(([i]) => ids.includes(i)).reduce((a, [, w]) => a + w, 0) / pool.reduce((a, [, w]) => a + w, 0);
  const pool = (trig: GhostTrigger, sit: Partial<GhostSituation>, mem = newGhostMemory(), persona: Persona = "chatty", pack = "game") =>
    ghostPool(trig, persona, mem, { now: 100 * SEC, ...sit }, ownedOf(pack), R(3));

  it("winning is cheeky, losing is sad", () => {
    const cheeky = ["cool", "tease", "crown", "laugh", "champ"];
    const sad = ["cry", "sad", "facepalm", "sob"];
    for (const trig of [human("laugh"), human("party"), { kind: "capture" } as GhostTrigger]) {
      expect(weight(pool(trig, { lead: 0.3 }, newGhostMemory(), "chatty", "friends"), cheeky)).toBeGreaterThan(weight(pool(trig, { lead: -0.3 }, newGhostMemory(), "chatty", "friends"), cheeky));
    }
    for (const trig of [human("party"), human("crown"), { kind: "captured" } as GhostTrigger]) {
      expect(weight(pool(trig, { lead: -0.3 }), ["sad", "flag", "facepalm"])).toBeGreaterThan(weight(pool(trig, { lead: 0.3 }), ["sad", "flag", "facepalm"]));
    }
    expect(weight(pool({ kind: "captured" }, { lead: -0.3 }, newGhostMemory(), "chatty", "friends"), sad)).toBeGreaterThan(weight(pool({ kind: "captured" }, { lead: 0.3 }, newGhostMemory(), "chatty", "friends"), sad));
  });

  it("right after its own capture it gloats; right after being captured it sulks (and stops being sweet)", () => {
    const fresh = newGhostMemory();
    const gloating = newGhostMemory();
    gloating.capAt = 95 * SEC;
    const hurt = newGhostMemory();
    hurt.hitAt = 95 * SEC;
    const GL = ["tease", "laugh", "cool", "champ", "crown"];
    expect(weight(pool(human("happy"), {}, gloating, "friendly", "friends"), GL)).toBeGreaterThan(weight(pool(human("happy"), {}, fresh, "friendly", "friends"), GL));
    const SK = ["angry", "cry", "facepalm", "sob"];
    expect(weight(pool(human("angry"), {}, hurt, "cheeky", "friends"), SK)).toBeGreaterThan(weight(pool(human("angry"), {}, fresh, "cheeky", "friends"), SK));
    expect(weight(pool(human("hi"), {}, hurt, "friendly", "pawns"), ["love", "happy"])).toBeLessThan(weight(pool(human("hi"), {}, fresh, "friendly", "pawns"), ["love", "happy"]));
  });

  it("a sad person it just beat gets a cheeky or a friendly answer, depending on the personality", () => {
    const m = newGhostMemory();
    m.capAt = 95 * SEC;
    const ch = (p: Persona) => {
      let cheeky = 0;
      for (let seed = 1; seed <= 600; seed++) {
        const r = ghostEmoteReply({ now: 100 * SEC, chance: 1 }, p, JSON.parse(JSON.stringify(m)), human("sob"), R(seed), "friends");
        if (r && ["cool", "tease", "laugh"].includes(r.id)) cheeky++;
      }
      return cheeky;
    };
    expect(ch("cheeky")).toBeGreaterThan(ch("friendly") * 2);
    const friendly = (() => {
      let n = 0;
      for (let seed = 1; seed <= 600; seed++) {
        const r = ghostEmoteReply({ now: 100 * SEC, chance: 1 }, "friendly", JSON.parse(JSON.stringify(m)), human("cry"), R(seed), "pawns");
        if (r && ["love", "hi"].includes(r.id)) n++;
      }
      return n;
    })();
    expect(friendly).toBeGreaterThan(150);
  });

  it("progressLead: Ludo token progress and S&L squares", () => {
    const ludo = { tok: [[56, 56, 10, -1], [-1, -1, -1, -1], [5, -1, -1, -1], [-1, -1, -1, -1]] };
    expect(progressLead(ludo, 0, [0, 1])).toBeGreaterThan(0.3);
    expect(progressLead(ludo, 1, [0, 1])).toBeLessThan(-0.3);
    expect(progressLead(ludo, 2, [2, 3])).toBeGreaterThan(0);
    const sl = { players: [{ c: 0, pos: 80 }, { c: 2, pos: 10 }] };
    expect(progressLead(sl, 0, [0, 2])).toBeCloseTo(0.7);
    expect(progressLead(sl, 2, [0, 2])).toBeCloseTo(-0.7);
    expect(progressLead(sl, 0, [0])).toBe(0);
  });
});

describe("owned packs, repeats, delays, limits, memory", () => {
  const triggers: GhostTrigger[] = [
    { kind: "capture" }, { kind: "captured" }, { kind: "six" }, { kind: "finish" },
    ...Object.values(EMOTE_PACKS).flat().map((id) => human(id)),
  ];

  it("only emotes from starter plus the one owned pack, whatever the trigger (graceful fallback, e.g. hi without pawns)", () => {
    let sent = 0;
    for (let seed = 1; seed <= 200; seed++) {
      const pack = ["", ...PACKS][seed % 4];
      const owned = ownedOf(pack);
      const mem = newGhostMemory();
      const rng = R(seed);
      triggers.forEach((trig, k) => {
        const r = ghostEmoteReply({ now: k * 60 * SEC, chance: 1, lead: (seed % 3 - 1) * 0.3 }, PERSONAS[seed % 5], mem, trig, rng, pack);
        if (r) {
          sent++;
          expect(owned.has(r.id)).toBe(true);
          expect(packOfEmote(r.id)).not.toBe("");
        }
      });
    }
    expect(sent).toBeGreaterThan(3000);
    // a ghost without pawns answers "hi" with something from the starter set
    const r = ghostEmoteReply({ now: 0, chance: 1 }, "friendly", newGhostMemory(), human("hi"), R(1), "game");
    expect(r && EMOTE_PACKS.starter.concat(EMOTE_PACKS.game).includes(r.id)).toBe(true);
  });

  it("never the same emote twice in a row and avoids its last 3, over a long chat", () => {
    for (let seed = 1; seed <= 100; seed++) {
      const mem = newGhostMemory();
      const rng = R(seed);
      const ids: string[] = [];
      for (let k = 0; k < 150; k++) {
        const r = ghostEmoteReply({ now: k * 40 * SEC, chance: 1 }, PERSONAS[seed % 5], mem, triggers[k % triggers.length], rng, PACKS[seed % 3]);
        if (r) ids.push(r.id);
      }
      expect(ids.length).toBeGreaterThan(80);
      for (let k = 1; k < ids.length; k++) expect(ids[k]).not.toBe(ids[k - 1]);
      for (let k = 3; k < ids.length; k++) expect(ids.slice(k - 3, k)).not.toContain(ids[k]);
      expect(mem.last.length).toBe(3);
    }
  });

  it("delays: 1.0-3.5 s, longer (up to 9 s) on its own turn, scaled by the time scale", () => {
    const calm: number[] = [];
    const own: number[] = [];
    const scaled: number[] = [];
    for (let seed = 1; seed <= 600; seed++) {
      const run = (sit: Partial<GhostSituation>, into: number[]) => {
        const r = ghostEmoteReply({ now: 0, chance: 1, ...sit }, "chatty", newGhostMemory(), human("hi"), R(seed), "pawns");
        if (r) into.push(r.delayMs);
      };
      run({}, calm);
      run({ ownTurn: true }, own);
      run({ scale: 0.1 }, scaled);
    }
    expect(Math.min(...calm)).toBeGreaterThanOrEqual(GHOST_EMOTE.delay[0]);
    expect(Math.max(...calm)).toBeLessThanOrEqual(GHOST_EMOTE.delay[1]);
    expect(Math.min(...own)).toBeGreaterThanOrEqual(GHOST_EMOTE.delay[0] + GHOST_EMOTE.ownExtra[0]);
    expect(Math.max(...own)).toBeLessThanOrEqual(GHOST_DELAY_MAX);
    expect(Math.max(...own)).toBeGreaterThan(GHOST_EMOTE.delay[1] + GHOST_EMOTE.ownExtra[1]); // sometimes after its move
    expect(own.reduce((a, b) => a + b) / own.length).toBeGreaterThan(calm.reduce((a, b) => a + b) / calm.length + 800);
    expect(Math.min(...scaled)).toBeGreaterThanOrEqual(GHOST_EMOTE.delay[0] * 0.1 - 1);
    expect(Math.max(...scaled)).toBeLessThanOrEqual(GHOST_EMOTE.delay[1] * 0.1 + 1);
  });

  it("the humans' limits: 1 per 2 s and 6 per 30 s, even when every event fires", () => {
    for (let seed = 1; seed <= 100; seed++) {
      const mem = newGhostMemory();
      const rng = R(seed);
      const at: number[] = [];
      for (let k = 0; k < 400; k++) {
        const now = k * 250;
        const r = ghostEmoteReply({ now, chance: 1 }, "chatty", mem, { kind: "finish" }, rng, "friends");
        if (r) at.push(now + r.delayMs);
      }
      at.sort((a, b) => a - b);
      expect(at.length).toBeGreaterThan(6);
      for (let k = 1; k < at.length; k++) expect(at[k] - at[k - 1]).toBeGreaterThanOrEqual(2000);
      for (let k = 6; k < at.length; k++) expect(at[k] - at[k - 6]).toBeGreaterThanOrEqual(30_000);
    }
  });

  it("chance 0 is silence (the test hook)", () => {
    for (let seed = 1; seed <= 100; seed++) {
      for (const trig of triggers) expect(ghostEmoteReply({ now: seed * 99 * SEC, chance: 0 }, "chatty", newGhostMemory(), trig, R(seed), "pawns")).toBeNull();
    }
  });

  it("ghosts rarely react to each other: at most once per other ghost", () => {
    let reacted = 0;
    for (let seed = 1; seed <= 2000; seed++) {
      const mem = newGhostMemory();
      const rng = R(seed);
      let n = 0;
      for (let k = 0; k < 10; k++) if (ghostEmoteReply({ now: k * 60 * SEC }, "chatty", mem, { kind: "emote", id: "laugh", from: 2, human: false }, rng, "friends")) n++;
      expect(n).toBeLessThanOrEqual(1);
      reacted += n;
      // another ghost is another pair
      for (let k = 0; k < 10; k++) if (ghostEmoteReply({ now: 1000 * SEC + k * 60 * SEC }, "chatty", mem, { kind: "emote", id: "laugh", from: 3, human: false }, rng, "friends")) n++;
      expect(n).toBeLessThanOrEqual(2);
    }
    // one offer per ghost emote: a rare reaction (chatty doubles the 5%)
    let once = 0;
    for (let seed = 1; seed <= 4000; seed++) if (ghostEmoteReply({ now: 0 }, "chatty", newGhostMemory(), { kind: "emote", id: "laugh", from: 2, human: false }, R(seed), "friends")) once++;
    expect(once / 4000).toBeLessThan(0.15);
    expect(once).toBeGreaterThan(0);
    expect(reacted).toBeGreaterThan(0);
  });

  it("memory is plain JSON: a copy through JSON (hibernation) decides exactly like the original", () => {
    for (let seed = 1; seed <= 100; seed++) {
      const a = newGhostMemory();
      const rngA = R(seed);
      const rngB = R(seed);
      let b = newGhostMemory();
      for (let k = 0; k < 60; k++) {
        const now = k * 9 * SEC;
        const trig = triggers[(k * 7) % triggers.length];
        const x = ghostEmoteReply({ now }, "cheeky", a, trig, rngA, "friends");
        b = JSON.parse(JSON.stringify(b)); // evicted and loaded before every decision
        const y = ghostEmoteReply({ now }, "cheeky", b, trig, rngB, "friends");
        expect(y).toEqual(x);
      }
      expect(b).toEqual(a);
    }
  });
});
