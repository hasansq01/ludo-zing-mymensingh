// Server-only economy rules: values with no GDScript counterpart (the offline game has no server, no online coins,
// no claim limits). Everything else comes from catalog.json. The values are the lead's "Economy decisions" in
// ONLINE_V2.md (2026-10-24). None of them feeds the offline functions the parity tests replay (those take the day
// key, the clock and the dice as arguments).

/**
 * Day boundaries: minutes east of UTC. 360 = Bangladesh (UTC+6, no DST): the server's day for the daily reward, the
 * spin, the claim caps and the leaderboard weeks starts at Bangladesh midnight (Economy decision 1). The offline game
 * uses the device's local day instead (README: "Days").
 */
export const DAY_OFFSET_MIN = 360;

/**
 * Online matches (friend rooms, quick match), granted by the Room at `over`, once per account per match.
 * win: your side won; finish: played to the end without winning; left: left before the end (a bot took the seat).
 * Ludo XP matches LudoMatch.NET_XP_WIN / NET_XP_PLAY (100 / 40, catalog.match.online_today); coins are new in v2.
 * Snakes & Ladders pays less (its offline game pays half of Ludo) but gives XP, so it counts for the XP board
 * (Economy decision 2).
 */
export const ONLINE_REWARDS = {
  // coins doubled-and-more by the owner 2026-10-31 (ECONOMY_V1.md §0: Ludo 150 / 20 -> 300 / 50, S&L 100 / 10 -> 200 / 25)
  ludo: { win: { coins: 300, xp: 100 }, finish: { coins: 50, xp: 40 }, left: { coins: 0, xp: 0 } },
  sl: { win: { coins: 200, xp: 60 }, finish: { coins: 25, xp: 25 }, left: { coins: 0, xp: 0 } },
} as const;

/** Offline match claims (POST /v1/claims; Economy decisions 3-5). */
export const CLAIM_LIMITS = {
  /** A shorter match is recorded but grants nothing. */
  min_duration_s: { ludo: 60, sl: 30 } as Record<string, number>,
  /** Granted claims in any rolling 3600 s window; past it a claim grants nothing. */
  per_hour: 20,
  /** Coins from claims per day (DAY_OFFSET_MIN days); the claim that reaches it is paid the remainder. */
  coins_per_day: 6000,
  /** XP from claims per day, the same way (online XP is not capped: those matches are server-run). */
  xp_per_day: 3000,
  /** Pairs a single Ludo claim may add to stats.pairsFormed. */
  pairs_per_claim: 6,
  /** The longest `rolls` list an S&L win claim may carry. */
  max_rolls: 2000,
} as const;

/** The one-time import of the local (pre-v2) profile. */
export const IMPORT_CAPS = {
  coins: 50_000,
  xp: 200_000,
  /** Each stats counter. */
  stat: 1_000_000,
  /** NetClient.NAME_MAX. */
  name_max: 16,
} as const;

/** A coin table of quick match (ECONOMY_V1.md §3). entry 0 = the free practice table. */
export interface CoinTable {
  id: string;
  entry: number;
  /** The level needed to queue. */
  level: number;
}

/**
 * Economy v1 (ECONOMY_V1.md §0, owner 2026-10-26): coin tables, the table fee, re-rolls, rewarded ads, gems earned,
 * the gems -> coins exchange, the broke bonus and the gem packs sold on Google Play.
 */
export const ECON_V1 = {
  tables: [
    { id: "practice", entry: 0, level: 1 },
    { id: "t100", entry: 100, level: 1 },
    { id: "t500", entry: 500, level: 1 },
    { id: "t2k", entry: 2_000, level: 6 },
    { id: "t10k", entry: 10_000, level: 10 },
    { id: "t50k", entry: 50_000, level: 15 },
  ] as readonly CoinTable[],
  /** Percent of the pot kept by the house (the coin sink; owner 2026-10-31: 10 -> 5). */
  fee_pct: 5,
  /**
   * 4-player tables: percent of the pool for 1st, 2nd, 3rd (owner 2026-10-31, was 75 / 25), each rounded down; the
   * rounding remainder stays with the house.
   */
  shares_4p: [60, 30, 10] as readonly number[],
  /**
   * The house bonus (owner 2026-10-31): 1st place at a paid table also gets this percent of the pool as new coins
   * (ledger `table_bonus`), on top of the pot payout. Ghost winners get none.
   */
  bonus_pct: 20,
  /**
   * Settlement by progress (a quick match ended because nobody was connected, room.ts endAway): a person who was
   * disconnected (not finished) gets 1st place money only with a clear lead over the runner-up. Ludo: more pawns home,
   * or a distance lead above this percent of one pawn's full track (GOAL + 1 = 57 steps, so 15+ steps); S&L: this
   * many squares or more. Otherwise their entry is refunded and the 1st prize stays with the house.
   */
  away_lead: { ludo_track_pct: 25, sl_squares: 20 },
  /** Practice table coins (XP as ONLINE_REWARDS). */
  practice: { ludo: { win: 50, finish: 10 }, sl: { win: 50, finish: 10 } } as Record<string, { win: number; finish: number }>,
  /** Below this many coins a player is broke (the cheapest paid table). */
  broke_below: 100,
  /** The daily broke bonus (once per Bangladesh day, only while broke). */
  broke_bonus: 300,
  /** Re-roll: gems when no free re-roll is held; the hold window (ms); ghosts' chance to use theirs on a bad roll. */
  reroll_gems: 5,
  reroll_window_ms: 3_000,
  reroll_free_max: 9,
  ghost_reroll_chance: 0.25,
  /** Rewarded ads: per-kind daily caps (Bangladesh day), what each grants, the total cap. */
  ads: {
    reroll: { per_day: 3, amount: 1 },
    refill: { per_day: 2, amount: 500 },
    double: { per_day: 2, amount: 0 }, // amount = the match's payout
    gems: { per_day: 1, amount: 2 },
  } as Record<string, { per_day: number; amount: number }>,
  ads_per_day: 8,
  /** A pending ad nonce expires after this long; `double` must start within this long after the match ended. */
  ad_nonce_ms: 30 * 60_000,
  double_within_ms: 15 * 60_000,
  /** Gems per level gained. */
  level_gems: 5,
  /** Weekly board prizes by rank (1-based; ranks 4-10 get the last value). */
  weekly_gems: [50, 30, 20, 10, 10, 10, 10, 10, 10, 10],
  /** Gems for claiming an achievement (on top of its coins). */
  achievement_gems: 10,
  /** Gems -> coins (one way). */
  exchange: [
    { gems: 10, coins: 1_000 },
    { gems: 50, coins: 5_500 },
    { gems: 120, coins: 14_000 },
  ],
  /** Consumable gem packs (Play Console product ids). */
  products: { gems_80: 80, gems_220: 220, gems_500: 500, gems_1200: 1_200 } as Record<string, number>,
  /** Entries still held / playing after this long are refunded by the cron. */
  entry_sweep_ms: 3 * 3600_000,
} as const;

export function coinTable(id: string): CoinTable | undefined {
  return ECON_V1.tables.find((t) => t.id === id);
}

/**
 * The payouts of a coin-table match: places = seat keys in final order (seats that left already removed). The pot
 * is entry x size (ghost entries are virtual); the pool is the pot minus the fee (rounded down). 2 players: 1st takes
 * the pool; 4 players: 1st / 2nd / 3rd ECON_V1.shares_4p percent of the pool, each rounded down (the remainder is the
 * house's). Returns [place index -> coins] for the paid places (at most `placesLeft` of them), and `bonus`: the house
 * bonus for 1st place (new coins, not part of the pot; 0 at the practice table).
 */
export function tablePayouts(entry: number, size: number, placesLeft: number): { pot: number; pool: number; pay: number[]; bonus: number } {
  const pot = Math.max(0, Math.trunc(entry)) * size;
  const pool = Math.floor((pot * (100 - ECON_V1.fee_pct)) / 100);
  const pay = size <= 2 ? [pool] : ECON_V1.shares_4p.map((pct) => Math.floor((pool * pct) / 100));
  return { pot, pool, pay: pay.slice(0, Math.max(0, placesLeft)), bonus: tableBonus(entry, size) };
}

/** The house bonus of 1st place at a paid table (ECON_V1.bonus_pct of the pool, rounded down); 0 for practice. */
export function tableBonus(entry: number, size: number): number {
  if (!(entry > 0)) return 0;
  const pool = Math.floor((Math.trunc(entry) * size * (100 - ECON_V1.fee_pct)) / 100);
  return Math.floor((pool * ECON_V1.bonus_pct) / 100);
}
