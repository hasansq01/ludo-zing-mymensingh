// Admin crash reports (ADMIN_API.md "Crashes"): the list (newest first, filters, paging), the summary counts, the
// detail with the parsed payload, the session requirement.
import { beforeAll, describe, expect, it } from "vitest";
import { api, call, DB, login } from "./admin_helpers";

let cookie = "";
const NOW = Date.now();
const DAY = 86_400_000;
const get = (path: string, status = 200) => api(cookie, path, {}, status);

interface Seed { n: number; at: number; model: string; reason: string; version: string; gpu?: string }
const ABC = "abcdefghijklmnopqrstuvwxyz234567";
const idOf = (n: number) => "crs_" + "a".repeat(14) + ABC[n >> 5] + ABC[n & 31];

async function seed(s: Seed): Promise<string> {
  const id = idOf(s.n);
  const payload = { v: 1, device: { model: s.model, gpu: s.gpu ?? "Mali-G71" }, log: `log ${s.n}` };
  await DB.prepare(
    "INSERT INTO crash_reports (id, received_at, pid, sid, app_version, model, gpu, reason, payload) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
  ).bind(id, s.at, `pid${s.n}`, `sid${s.n}`, s.version, s.model, s.gpu ?? "Mali-G71", s.reason, JSON.stringify(payload)).run();
  return id;
}

beforeAll(async () => {
  cookie = await login();
  await DB.exec("DELETE FROM crash_reports");
  await seed({ n: 1, at: NOW - 1 * DAY, model: "SM-A105F", reason: "low_memory", version: "0.2.0" });
  await seed({ n: 2, at: NOW - 2 * DAY, model: "SM-A105F", reason: "crash_native", version: "0.2.0", gpu: "Adreno 506" });
  await seed({ n: 3, at: NOW - 3 * DAY, model: "Redmi 9A", reason: "low_memory", version: "0.1.9" });
  await seed({ n: 4, at: NOW - 4 * DAY, model: "Redmi 9A", reason: "unclean", version: "0.2.0" });
  await seed({ n: 5, at: NOW - 40 * DAY, model: "Redmi 9A", reason: "anr", version: "0.1.9" });
});

describe("GET /admin/api/crashes", () => {
  it("lists newest first without the payload", async () => {
    const r = await get("crashes");
    expect(r.rows.map((x: { sid: string }) => x.sid)).toEqual(["sid1", "sid2", "sid3", "sid4", "sid5"]);
    expect(r.next).toBeNull();
    expect(r.rows[0]).toMatchObject({ model: "SM-A105F", reason: "low_memory", app_version: "0.2.0", received_at: NOW - DAY });
    expect(r.rows[0].payload).toBeUndefined();
  });

  it("filters by version, model and reason (combinable)", async () => {
    const ids = async (q: string) => (await get(`crashes?${q}`)).rows.map((x: { sid: string }) => x.sid);
    expect(await ids("version=0.1.9")).toEqual(["sid3", "sid5"]);
    expect(await ids("model=SM-A105F")).toEqual(["sid1", "sid2"]);
    expect(await ids("reason=low_memory")).toEqual(["sid1", "sid3"]);
    expect(await ids("model=Redmi%209A&reason=low_memory&version=0.1.9")).toEqual(["sid3"]);
    expect(await ids("model=nothing")).toEqual([]);
  });

  it("pages with limit and before", async () => {
    const a = await get("crashes?limit=2");
    expect(a.rows.map((x: { sid: string }) => x.sid)).toEqual(["sid1", "sid2"]);
    expect(a.next).toBe(NOW - 2 * DAY);
    const b = await get(`crashes?limit=2&before=${a.next}`);
    expect(b.rows.map((x: { sid: string }) => x.sid)).toEqual(["sid3", "sid4"]);
    const c = await get(`crashes?limit=2&before=${b.next}`);
    expect(c.rows.map((x: { sid: string }) => x.sid)).toEqual(["sid5"]);
    expect(c.next).toBeNull();
    await get("crashes?limit=0", 400);
    await get("crashes?before=abc", 400);
  });
});

describe("GET /admin/api/crashes/summary", () => {
  it("counts by model, reason, version and gpu over the window", async () => {
    const s = await get("crashes/summary?days=30");
    expect(s.total).toBe(4);
    expect(s.by_model).toEqual([{ model: "Redmi 9A", n: 2 }, { model: "SM-A105F", n: 2 }]);
    expect(s.by_reason[0]).toEqual({ reason: "low_memory", n: 2 });
    expect(s.by_reason).toHaveLength(3);
    expect(s.by_version).toEqual([{ version: "0.2.0", n: 3 }, { version: "0.1.9", n: 1 }]);
    expect(s.by_gpu).toEqual([{ gpu: "Mali-G71", n: 3 }, { gpu: "Adreno 506", n: 1 }]);
    expect((await get("crashes/summary?days=60")).total).toBe(5);
    expect((await get("crashes/summary")).days).toBe(30);
    expect((await get("crashes/summary?days=0")).days).toBe(1);
  });
});

describe("GET /admin/api/crashes/:id", () => {
  it("returns the row with the parsed payload", async () => {
    const d = await get(`crashes/${idOf(2)}`);
    expect(d).toMatchObject({ id: idOf(2), model: "SM-A105F", reason: "crash_native", payload: { v: 1, log: "log 2", device: { gpu: "Adreno 506" } } });
    await get(`crashes/${idOf(99)}`, 404);
    await get("crashes/nope", 404);
  });
});

describe("auth", () => {
  it("needs a session and GET", async () => {
    for (const p of ["crashes", "crashes/summary", `crashes/${idOf(1)}`]) expect((await call(p)).status).toBe(401);
    expect((await call("crashes", { cookie, method: "POST", body: {} })).status).toBe(405);
  });
});
