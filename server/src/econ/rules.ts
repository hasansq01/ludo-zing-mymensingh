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
  ludo: { win: { coins: 150, xp: 100 }, finish: { coins: 20, xp: 40 }, left: { coins: 0, xp: 0 } },
  sl: { win: { coins: 100, xp: 60 }, finish: { coins: 10, xp: 25 }, left: { coins: 0, xp: 0 } },
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
