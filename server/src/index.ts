// Ludo Zing online rooms: the Worker routes /v1/... to one Room Durable Object per room code (PROTOCOL.md), serves
// the admin console at /admin (static files from ./admin) and its API at /admin/api (ADMIN_API.md), and runs the
// daily cron (D1 pruning).
import { CSP, handleAdmin } from "./admin";
import { cron } from "./cron";
import * as D from "./db";
import { isCode, randomCode, Room, type Env } from "./room";

export { Room };
export type { Env };

const JSON_HEADERS = { "Cache-Control": "no-store" };

function json(body: unknown, status = 200, headers: Record<string, string> = JSON_HEADERS): Response {
  return Response.json(body, { status, headers });
}

function stub(env: Env, code: string): DurableObjectStub<Room> {
  return env.ROOMS.get(env.ROOMS.idFromName(code));
}

const MAINTENANCE_MSG = "Online play is down for maintenance. Please try again later.";

/** POST /v1/rooms: a fresh code, reserved by asking that room's object to init (retried on a collision). */
async function createRoom(env: Env): Promise<Response> {
  // maintenance blocks new rooms only (existing rooms keep working); a D1 failure never blocks play
  const cfg = await D.cachedConfig(env.DB, 10_000).catch((e) => {
    console.error("config read failed:", e);
    return null;
  });
  if (cfg?.maintenance) return json({ error: "maintenance", msg: cfg.motd || MAINTENANCE_MSG }, 503);
  for (let attempt = 0; attempt < 8; attempt++) {
    const code = randomCode();
    if (await stub(env, code).init(code)) return json({ code });
  }
  return json({ error: "no_code" }, 503);
}

/** GET /v1/config: what the game shows on Home (cached 60 s). */
async function publicConfig(env: Env): Promise<Response> {
  try {
    const cfg = await D.cachedConfig(env.DB, 60_000);
    return json({ motd: cfg.motd, maintenance: cfg.maintenance }, 200, { "Cache-Control": "public, max-age=60" });
  } catch (e) {
    console.error("config read failed:", e);
    return json({ motd: "", maintenance: false }, 200, { "Cache-Control": "public, max-age=10" });
  }
}

async function v1(req: Request, env: Env, parts: string[]): Promise<Response> {
  if (parts.length === 2 && parts[1] === "health") {
    return req.method === "GET" ? json({ ok: true }) : json({ error: "method" }, 405);
  }
  if (parts.length === 2 && parts[1] === "config") {
    return req.method === "GET" ? publicConfig(env) : json({ error: "method" }, 405);
  }
  if (parts[1] !== "rooms") return json({ error: "not_found" }, 404);

  if (parts.length === 2) {
    return req.method === "POST" ? createRoom(env) : json({ error: "method" }, 405);
  }
  const code = (parts[2] ?? "").toUpperCase();
  if (!isCode(code)) return json({ error: "not_found" }, 404);

  if (parts.length === 3) {
    if (req.method !== "GET") return json({ error: "method" }, 405);
    const info = await stub(env, code).info();
    return info ? json(info) : json({ error: "not_found" }, 404);
  }
  if (parts.length === 4 && parts[3] === "ws") {
    if (req.method !== "GET") return json({ error: "method" }, 405);
    if (req.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return json({ error: "expected a websocket upgrade" }, 426);
    }
    return stub(env, code).fetch(req); // 404 there when the room doesn't exist
  }
  return json({ error: "not_found" }, 404);
}

/** /admin and /admin/*: the console's static files (./admin, ASSETS binding), /admin/ -> index.html. */
async function adminFiles(req: Request, env: Env, url: URL): Promise<Response> {
  if (req.method !== "GET" && req.method !== "HEAD") return json({ error: "method" }, 405);
  if (!env.ASSETS) return json({ error: "not_found" }, 404);
  let path = url.pathname.slice("/admin".length);
  if (path === "" || path === "/") path = "/index.html";
  const get = (p: string) => env.ASSETS!.fetch(new Request(new URL(p, url.origin), { method: req.method, headers: req.headers }));
  let res = await get(path);
  // the console routes with #hashes; an extensionless path that is not a file still gets the app
  if (res.status === 404 && !/\.[A-Za-z0-9]+$/.test(path)) res = await get("/index.html");
  const out = new Response(res.body, res);
  out.headers.set("Content-Security-Policy", CSP);
  out.headers.set("X-Frame-Options", "DENY");
  out.headers.set("X-Content-Type-Options", "nosniff");
  out.headers.set("Referrer-Policy", "no-referrer");
  if ((out.headers.get("Content-Type") ?? "").includes("text/html")) out.headers.set("Cache-Control", "no-cache");
  return out;
}

async function route(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const url = new URL(req.url);
  const parts = url.pathname.split("/").filter(Boolean); // ["v1", "rooms", CODE, "ws"]
  if (parts[0] === "v1") return v1(req, env, parts);
  if (parts[0] === "admin") {
    if (parts[1] === "api") return handleAdmin(req, env, ctx, parts.slice(2));
    return adminFiles(req, env, url);
  }
  return json({ error: "not_found" }, 404);
}

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    try {
      return await route(req, env, ctx);
    } catch (e) {
      console.error("worker error:", e);
      const msg = e instanceof Error ? `${e.name}: ${e.message}\n${e.stack ?? ""}` : String(e);
      ctx.waitUntil(
        D.addEvent(env.DB, { level: "error", kind: "worker", msg: `${req.method} ${new URL(req.url).pathname}: ${msg}` })
          .run()
          .catch(() => {}),
      );
      return json({ error: "internal" }, 500);
    }
  },

  async scheduled(_ctrl: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(cron(env).then(() => undefined));
  },
} satisfies ExportedHandler<Env>;
