// Coin tables (ECONOMY_V1.md §3): the payout math, entries held at queue time and given back when the person leaves
// the queue, the level / coins checks, matches against ghosts settled with the grant (payout, ledger, table_matches),
// a person who leaves forfeiting, a no-show refunded, the practice table's coins, the cron sweep.
import { SELF } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { ECON_V1, coinTable, tableBonus, tablePayouts } from "../src/econ";
import { sweepEntries } from "../src/economy";
import { DB, eventually, row, rows } from "./admin_helpers";
import { E, NEAR_GOAL, finishAll, sleep, type Msg } from "./room_client";
import { QuickClient, guest, joinMatched, resetSpies, type Guest } from "./quick_client";

beforeEach(() => resetSpies());
afterEach(() => resetSpies());

function mm(game: string, size: number, table: string) {
  return E.MATCHMAKER.get(E.MATCHMAKER.idFromName(table === "practice" ? `${game}:${size}` : `${game}:${size}:${table}`));
}

async function hooks(game: string, size: number, table: string, h: Record<string, unknown>) {
  await mm(game, size, table).testHooks({ ...h, room: { ratePerSec: 1000, ...((h.room as object) ?? {}) } } as never);
}

async function queue(game: string, size: number, table: string, g: Guest): Promise<QuickClient> {
  const q = await QuickClient.open(game, size, `&table=${table}`);
  q.send({ t: "hello", v: 1, session: g.session, pid: g.pid, name: "Me", avatar: "pawn-red", frame: "classic" });
  return q;
}

async function coins(account: string): Promise<number> {
  return (await row<{ coins: number }>("SELECT coins FROM accounts WHERE id = ?", account))!.coins;
}

async function setAcc(account: string, cols: Record<string, number>) {
  const k = Object.keys(cols);
  await DB.prepare(`UPDATE accounts SET ${k.map((c) => `${c} = ?`).join(", ")} WHERE id = ?`).bind(...k.map((c) => cols[c]), account).run();
}

async function entriesOf(account: string) {
  return rows<Msg>("SELECT * FROM entries WHERE account_id = ? ORDER BY at", account);
}

describe("payout math", () => {
  it("2 players: the winner takes the pot minus 5%; 4 players: 60 / 30 / 10 of the pool; 1st's bonus 20% of the pool", () => {
    expect(ECON_V1.fee_pct).toBe(5);
    expect(tablePayouts(100, 2, 2)).toEqual({ pot: 200, pool: 190, pay: [190], bonus: 38 });
    expect(tablePayouts(100, 4, 4)).toEqual({ pot: 400, pool: 380, pay: [228, 114, 38], bonus: 76 });
    expect(tablePayouts(500, 4, 4)).toEqual({ pot: 2000, pool: 1900, pay: [1140, 570, 190], bonus: 380 });
    expect(tablePayouts(2_000, 2, 2)).toEqual({ pot: 4000, pool: 3800, pay: [3800], bonus: 760 });
    expect(tablePayouts(2_000, 4, 1).pay).toEqual([4560]); // only one place left to pay: 2nd and 3rd are not paid
    expect(tablePayouts(2_000, 4, 2).pay).toEqual([4560, 2280]);
    expect(tablePayouts(0, 4, 4)).toMatchObject({ pot: 0, pool: 0, pay: [0, 0, 0], bonus: 0 }); // practice
    expect(tableBonus(0, 2)).toBe(0);
  });

  it("rounding down: the remainder stays with the house (odd pools)", () => {
    // pool 133 (pot 140): 79.8 / 39.9 / 13.3 -> 79 / 39 / 13 = 131, 2 coins to the house; bonus 26.6 -> 26
    expect(tablePayouts(35, 4, 4)).toEqual({ pot: 140, pool: 133, pay: [79, 39, 13], bonus: 26 });
    expect(tablePayouts(7, 2, 2)).toEqual({ pot: 14, pool: 13, pay: [13], bonus: 2 });
  });

  it("pot payouts never exceed the pot minus the fee, at every table and size (the bonus is separate, new coins)", () => {
    for (const t of ECON_V1.tables) {
      for (const size of [2, 4]) {
        for (let left = 0; left <= size; left++) {
          const p = tablePayouts(t.entry, size, left);
          const sum = p.pay.reduce((a, b) => a + b, 0);
          expect(sum).toBeLessThanOrEqual(Math.floor((t.entry * size * 95) / 100));
          expect(sum).toBeLessThanOrEqual(p.pot);
          expect(p.pay.length).toBeLessThanOrEqual(left);
          if (left === size) expect(p.pool - sum).toBeLessThan(3); // at most the rounding of three shares
          expect(p.bonus).toBe(t.entry > 0 ? Math.floor((p.pool * 20) / 100) : 0);
        }
      }
    }
  });

  it("the tables and levels of ECONOMY_V1.md", () => {
    expect(ECON_V1.tables.map((t) => [t.id, t.entry, t.level])).toEqual([
      ["practice", 0, 1],
      ["t100", 100, 1],
      ["t500", 500, 1],
      ["t2k", 2000, 6],
      ["t10k", 10000, 10],
      ["t50k", 50000, 15],
    ]);
    expect(coinTable("nope")).toBeUndefined();
  });
});

describe("GET /v1/tables", () => {
  it("lists the tables with unlocked / affordable and the broke bonus", async () => {
    const g = await guest();
    const r = await SELF.fetch("https://x/v1/tables", { headers: { Authorization: `Bearer ${g.session}` } });
    const b = (await r.json()) as Msg;
    expect(r.status).toBe(200);
    expect(b.fee_pct).toBe(5);
    expect(b.tables.find((t: Msg) => t.id === "t100")).toMatchObject({ entry: 100, unlocked: true, affordable: true });
    expect(b.tables.find((t: Msg) => t.id === "t2k")).toMatchObject({ unlocked: false });
    expect(b.tables.find((t: Msg) => t.id === "t10k")).toMatchObject({ affordable: false });
    expect(b.broke).toBe(false);
  });
});

describe("entries in the queue", () => {
  it("queueing takes the entry; cancelling gives it back (ledger entry + entry_refund)", async () => {
    await hooks("ludo", 2, "t100", { wait: 60_000 });
    const g = await guest();
    const q = await queue("ludo", 2, "t100", g);
    await q.wait("queued");
    expect(await coins(g.account)).toBe(2400);
    const [e] = await entriesOf(g.account);
    expect(e).toMatchObject({ status: "held", amount: 100, tier: "t100", game: "ludo", size: 2 });
    q.send({ t: "cancel" });
    await q.wait("cancelled");
    await eventually(async () => (await coins(g.account)) === 2500, 5000, "refund");
    expect((await entriesOf(g.account))[0].status).toBe("refunded");
    const led = await rows<Msg>("SELECT delta_coins, reason FROM ledger WHERE account_id = ? AND reason LIKE 'entry%' ORDER BY id", g.account);
    expect(led).toEqual([
      { delta_coins: -100, reason: "entry" },
      { delta_coins: 100, reason: "entry_refund" },
    ]);
  });

  it("closing the socket while queued gives the entry back", async () => {
    await hooks("sl", 2, "t100", { wait: 60_000 });
    const g = await guest();
    const q = await queue("sl", 2, "t100", g);
    await q.wait("queued");
    q.close();
    await eventually(async () => (await coins(g.account)) === 2500, 5000, "refund");
  });

  it("queueing again on another connection keeps the one entry", async () => {
    await hooks("ludo", 4, "t100", { wait: 60_000 });
    const g = await guest();
    const q1 = await queue("ludo", 4, "t100", g);
    await q1.wait("queued");
    const q2 = await queue("ludo", 4, "t100", g);
    await q2.wait("queued");
    await q1.waitClosed();
    expect(await coins(g.account)).toBe(2400);
    expect((await entriesOf(g.account)).map((e) => e.status)).toEqual(["held"]);
    q2.close();
    await eventually(async () => (await coins(g.account)) === 2500, 5000, "refund");
  });

  it("a table above your level is locked; too few coins: error coins + short", async () => {
    const g = await guest();
    const q = await queue("ludo", 2, "t2k", g);
    expect(await q.wait("error")).toMatchObject({ code: "locked", level: 6 });
    await setAcc(g.account, { coins: 50 });
    const q2 = await queue("ludo", 2, "t100", g);
    expect(await q2.wait("error")).toMatchObject({ code: "coins", short: 50 });
    expect(await coins(g.account)).toBe(50);
    expect(await entriesOf(g.account)).toEqual([]);
  });

  it("an unknown table is refused before the queue", async () => {
    const r = await SELF.fetch("https://x/v1/quick/ws?game=ludo&players=2&table=t7", { headers: { Upgrade: "websocket" } });
    expect(r.status).toBe(400);
  });
});

describe("coin-table matches", () => {
  it("1 human vs a ghost at 100: the entry is settled with the payout of the place; table_matches row", async () => {
    await hooks("ludo", 2, "t100", { wait: 200, room: { tok: NEAR_GOAL, timeScale: 0.05 } });
    const g = await guest();
    const q = await queue("ludo", 2, "t100", g);
    const m = await q.matched(8000);
    q.close();
    const c = await joinMatched(m.code, m.token, g, "Me");
    c.autoplay = true;
    await c.wait("start", 8000);
    c.playTurn(c.state.turn);
    const [over] = await finishAll([c], 30_000);
    const won = over.winner === c.color;
    const e = await eventually(async () => {
      const [x] = await entriesOf(g.account);
      return x && x.status === "settled" ? x : null;
    }, 8000, "settled");
    expect(e.place).toBe(won ? 0 : 1);
    expect(e.payout).toBe(won ? 190 : 0);
    expect(e.room).toBe(m.code);
    // the winner: the pool (190) plus the house bonus (38), on a separate ledger row
    expect(await coins(g.account)).toBe(2400 + (won ? 190 + 38 : 0));
    expect(over.table).toMatchObject({ tier: "t100", entry: 100, payouts: { [String(over.winner)]: 190 }, bonus: { [String(over.winner)]: 38 }, refunds: {} });
    const tm = await row<Msg>("SELECT * FROM table_matches WHERE match_id = ?", e.match_id);
    expect(tm).toMatchObject({ tier: "t100", entry: 100, size: 2, humans: 1, ghosts: 1, pot: 200, fee: 10, paid_humans: won ? 190 : 0, winner_ghost: won ? 0 : 1 });
    const grant = await row<Msg>("SELECT * FROM match_grants WHERE match_id = ? AND account_id = ?", e.match_id, g.account);
    expect(grant).toMatchObject({ outcome: won ? "win" : "finish", coins: won ? 190 : 0 });
    const led = await rows<Msg>("SELECT delta_coins, reason, ref, balance_after FROM ledger WHERE account_id = ? AND reason IN ('payout', 'table_bonus') ORDER BY id", g.account);
    if (won) {
      expect(led).toEqual([
        { delta_coins: 190, reason: "payout", ref: e.match_id, balance_after: 2590 },
        { delta_coins: 38, reason: "table_bonus", ref: e.match_id, balance_after: 2628 },
      ]);
    } else expect(led.filter((l) => l.reason === "table_bonus")).toEqual([]); // a ghost's win: no bonus to anyone
    const sum = await row<{ s: number }>("SELECT SUM(delta_coins) AS s FROM ledger WHERE account_id = ?", g.account);
    expect(sum!.s).toBe(await coins(g.account)); // the ledger still sums to the balance
  });

  it("leaving the match forfeits the entry (the match is abandoned: nothing comes back)", async () => {
    await hooks("ludo", 2, "t100", { wait: 200, room: { timeScale: 0.05 } });
    const g = await guest();
    const q = await queue("ludo", 2, "t100", g);
    const m = await q.matched(8000);
    q.close();
    const c = await joinMatched(m.code, m.token, g, "Me");
    await c.wait("start", 8000);
    c.send({ t: "leave" });
    const e = await eventually(async () => {
      const [x] = await entriesOf(g.account);
      return x && x.status !== "playing" && x.status !== "held" ? x : null;
    }, 8000, "closed entry");
    expect(e.status).toBe("forfeit");
    expect(e.payout).toBe(0);
    await sleep(200);
    expect(await coins(g.account)).toBe(2400);
  });

  it("matched but never connected (no-show): the room closes and the entry comes back", async () => {
    await hooks("ludo", 2, "t100", { wait: 200, room: { timeScale: 0.01 } });
    const g = await guest();
    const q = await queue("ludo", 2, "t100", g);
    await q.matched(8000);
    q.close();
    expect(await coins(g.account)).toBe(2400);
    await eventually(async () => (await coins(g.account)) === 2500, 8000, "no-show refund");
    expect((await entriesOf(g.account))[0]).toMatchObject({ status: "refunded" });
  });

  it("the practice table takes no entry and pays 50 / 10 coins", async () => {
    await hooks("ludo", 2, "practice", { wait: 200, room: { tok: NEAR_GOAL, timeScale: 0.05 } });
    const g = await guest();
    const q = await queue("ludo", 2, "practice", g);
    const m = await q.matched(8000);
    q.close();
    expect(await coins(g.account)).toBe(2500);
    const c = await joinMatched(m.code, m.token, g, "Me");
    c.autoplay = true;
    await c.wait("start", 8000);
    c.playTurn(c.state.turn);
    const [over] = await finishAll([c], 30_000);
    const won = over.winner === c.color;
    await eventually(async () => (await coins(g.account)) === 2500 + (won ? 50 : 10), 8000, "practice coins");
    expect(await entriesOf(g.account)).toEqual([]);
  });
});

describe("cron sweep", () => {
  it("refunds entries left held / playing for 3 hours; settled ones stay", async () => {
    const g = await guest();
    const old = Date.now() - ECON_V1.entry_sweep_ms - 1000;
    await setAcc(g.account, { coins: 2300 });
    await DB.batch([
      DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status) VALUES (?, ?, ?, 'ludo', 2, 't100', 100, 'playing')").bind("ent_aaaaaaaaaaaaaaaa", g.account, old),
      DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status) VALUES (?, ?, ?, 'ludo', 2, 't100', 100, 'settled')").bind("ent_bbbbbbbbbbbbbbbb", g.account, old),
      DB.prepare("INSERT INTO entries (id, account_id, at, game, size, tier, amount, status) VALUES (?, ?, ?, 'ludo', 2, 't100', 100, 'held')").bind("ent_cccccccccccccccc", g.account, Date.now()),
    ]);
    expect(await sweepEntries(E as never)).toBe(1);
    expect(await coins(g.account)).toBe(2400);
    const st = await rows<Msg>("SELECT id, status FROM entries WHERE account_id = ? ORDER BY id", g.account);
    expect(st.map((x) => x.status)).toEqual(["refunded", "settled", "held"]);
  });
});
