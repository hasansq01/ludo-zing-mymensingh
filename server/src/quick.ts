// Quick match over HTTP: GET /v1/quick/ws?game=ludo|sl&players=2|4[&table=<id>][&session=...] (WebSocket) -> the
// Matchmaker Durable Object for that queue (one per "game:size" for the practice table, "game:size:table" for a coin
// table, src/matchmaker.ts). PROTOCOL.md "Quick match", ECONOMY_V1.md §3.
// index.ts routes every /v1/quick/* request here.
import { isGame, type Env } from "./room";
import { QUICK_SIZES } from "./matchmaker";
import { coinTable } from "./econ";

const NO_STORE = { "Cache-Control": "no-store" };

function json(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: NO_STORE });
}

/** The Matchmaker for one queue. */
export function matchmaker(env: Env, game: string, size: number, table = "practice") {
  return env.MATCHMAKER.get(env.MATCHMAKER.idFromName(table === "practice" ? `${game}:${size}` : `${game}:${size}:${table}`));
}

export async function handleQuick(req: Request, env: Env, _ctx?: ExecutionContext): Promise<Response> {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean); // ["v1", "quick", "ws"]
  if (parts.length !== 3 || parts[0] !== "v1" || parts[1] !== "quick" || parts[2] !== "ws") {
    return json({ error: "not_found" }, 404);
  }
  if (req.method !== "GET") return json({ error: "method" }, 405);
  if (req.headers.get("Upgrade")?.toLowerCase() !== "websocket") return json({ error: "expected a websocket upgrade" }, 426);
  const game = url.searchParams.get("game") ?? "ludo";
  const players = Number(url.searchParams.get("players") ?? "2");
  if (!isGame(game) || !(QUICK_SIZES as readonly number[]).includes(players)) {
    return json({ error: "bad_request", msg: 'game must be "ludo" or "sl", players 2 or 4' }, 400);
  }
  const table = url.searchParams.get("table") ?? "practice";
  if (!coinTable(table)) return json({ error: "bad_request", msg: "unknown table" }, 400);
  if (!env.MATCHMAKER) return json({ error: "unavailable" }, 503);
  return matchmaker(env, game, players, table).fetch(req);
}
