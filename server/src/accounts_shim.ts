// The Room / Matchmaker side of the accounts interface agreed with the accounts work (src/accounts.ts, W2-ACC):
//   verifySession(env, token) -> {account_id} | null
//   accountForPid(env, pid) -> {account_id, banned} | null
//   getPublicProfile(env, account_id) -> {name, avatar, frame, level}
//   grantOnlineMatch(env, {match_id, game, results: [{account_id, outcome: "win" | "finish" | "left"}]})  (idempotent)
// plus the D1 helper db.ts gets for quick-match stats: recordQuickStat(env, {...}).
//
// Room and Matchmaker code call accounts(env) / quickStat(env, ...) only. The real functions are wired in REAL below;
// the fallbacks (no account, no grant) are used for anything missing. Tests (TEST_MODE "1" only) replace any function through globalThis.__lzAccounts, and observe stats through
// globalThis.__lzQuickStats (the Durable Objects run in the test isolate, so globalThis is shared).
import * as A from "./accounts";
import * as D from "./db";

export type GameKind = "ludo" | "sl";
export type OnlineOutcome = "win" | "finish" | "left";

export interface SessionInfo {
  account_id: string;
  /** Optional: when the accounts module reports the account's ban with the session. */
  banned?: boolean;
  ban_reason?: string | null;
}

export interface PidAccount {
  account_id: string;
  banned: boolean;
  ban_reason?: string | null;
}

export interface PublicProfile {
  name: string;
  avatar: string;
  frame: string;
  level: number;
}

export interface OnlineMatchGrant {
  match_id: string;
  game: GameKind;
  /**
   * place / entry_id: quick matches (ECONOMY_V1.md §3; place -1 = left, forfeit). refund: a match ended by the
   * settlement by progress gave this person's entry back instead of the 1st prize (no clear lead).
   */
  results: Array<{ account_id: string; outcome: OnlineOutcome; place?: number; entry_id?: string; refund?: boolean }>;
  /** Quick matches: the coin table (entry 0 = practice). */
  table?: { tier: string; entry: number; size: number; humans: number; ghosts: number; winner_ghost?: boolean };
}

export interface AccountsApi {
  verifySession(env: unknown, token: string): Promise<SessionInfo | null>;
  accountForPid(env: unknown, pid: string): Promise<PidAccount | null>;
  getPublicProfile(env: unknown, account_id: string): Promise<PublicProfile | null>;
  grantOnlineMatch(env: unknown, g: OnlineMatchGrant): Promise<unknown>;
}

/** One quick-match stats increment (quick_stats row of today, game, size). Missing fields add 0. */
export interface QuickStat {
  game: GameKind;
  size: number;
  /** Queue entries (a hello that got queued). */
  queued?: number;
  /** Humans matched into a room. */
  matched?: number;
  /** Ghost seats created. */
  ghost_filled?: number;
  /** Sum of the matched humans' waits (ms). */
  wait_ms?: number;
  /** A finished quick match that a human (resp. a ghost) won. */
  human_wins?: number;
  ghost_wins?: number;
}

// The real accounts module (src/accounts.ts). Its verifySession answers null for a banned account; when it also
// exports checkSession, the session check below uses that instead so a banned player gets "banned", not "session".
interface CheckSession {
  (env: never, token: unknown): Promise<
    { ok: true; row: { id: string } } | { ok: false; error: string; reason?: string; account_id?: string }
  >;
}
const REAL: Partial<AccountsApi> = {
  verifySession: A.verifySession as unknown as AccountsApi["verifySession"],
  accountForPid: A.accountForPid as unknown as AccountsApi["accountForPid"],
  getPublicProfile: A.getPublicProfile as unknown as AccountsApi["getPublicProfile"],
  grantOnlineMatch: A.grantOnlineMatch as unknown as AccountsApi["grantOnlineMatch"],
};
const checkSession = (A as unknown as { checkSession?: CheckSession }).checkSession;
const plainVerify = REAL.verifySession!;

/** verifySession plus the ban: {account_id, banned: true, ban_reason} for a valid session of a banned account. */
async function verifyWithBan(env: unknown, token: string): Promise<SessionInfo | null> {
  if (typeof checkSession !== "function") return plainVerify(env, token);
  const c = await checkSession(env as never, token);
  if (c.ok) return { account_id: c.row.id };
  if (c.error === "banned") {
    // the account id is in the (signed) token: "<account_id>.<exp>.<hmac>"
    const id = typeof token === "string" ? token.split(".")[0] : "";
    return { account_id: id, banned: true, ban_reason: c.reason ?? "" };
  }
  return null;
}
REAL.verifySession = verifyWithBan;

const FALLBACK: AccountsApi = {
  verifySession: async () => null,
  accountForPid: async () => null,
  getPublicProfile: async () => null,
  grantOnlineMatch: async () => undefined,
};

interface TestGlobals {
  __lzAccounts?: Partial<AccountsApi>;
  __lzQuickStats?: QuickStat[];
}

function testGlobals(env: { TEST_MODE?: string }): TestGlobals | null {
  return env.TEST_MODE === "1" ? (globalThis as unknown as TestGlobals) : null;
}

/** The accounts functions for this env (the real module, test overrides, else the no-account fallbacks). */
export function accounts(env: { TEST_MODE?: string }): AccountsApi {
  const over = testGlobals(env)?.__lzAccounts ?? {};
  const pickFn = <K extends keyof AccountsApi>(k: K): AccountsApi[K] =>
    (over[k] ?? (typeof REAL[k] === "function" ? REAL[k] : undefined) ?? FALLBACK[k]) as AccountsApi[K];
  return {
    verifySession: pickFn("verifySession"),
    accountForPid: pickFn("accountForPid"),
    getPublicProfile: pickFn("getPublicProfile"),
    grantOnlineMatch: pickFn("grantOnlineMatch"),
  };
}

type RecordQuickStat = (env: unknown, s: Record<string, unknown>) => unknown;

/** Adds one quick_stats increment (fire-and-forget; never throws). */
export async function quickStat(env: { TEST_MODE?: string }, s: QuickStat): Promise<void> {
  const tg = testGlobals(env);
  if (tg) (tg.__lzQuickStats ??= []).push({ ...s });
  const fn = (D as unknown as { recordQuickStat?: RecordQuickStat }).recordQuickStat;
  if (typeof fn !== "function") return;
  try {
    await fn(env, { ...s, day: D.utcDay(Date.now()) });
  } catch (e) {
    console.error("recordQuickStat failed:", e);
  }
}
