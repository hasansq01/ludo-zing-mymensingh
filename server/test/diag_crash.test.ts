// POST /v1/diag/crash (src/diag.ts): the report's row fields, the optional account, validation, size limits,
// dedupe, the per-IP / per-pid daily limits, payload capping and the defensive log scrub.
import { describe, expect, it } from "vitest";
import { LIMITS, MAX_BODY, MAX_PAYLOAD, scrub } from "../src/diag";
import { DAY, T0, guest, newPid, row, v1, type Json } from "./acc_helpers";

let n = 0;
const sid = () => `s${Date.now().toString(36)}${n++}`;
let ipSeq = 0;
const ip = () => `192.0.2.${100 + (ipSeq++ % 100)}`; // a fresh IP per report keeps the IP limit out of the way

function report(over: Json = {}): Json {
  return {
    v: 1,
    pid: newPid("crash"),
    sid: sid(),
    trigger: "unclean",
    app: { code: 8, name: "0.2.0" },
    device: { model: "SM-A105F", os: "Android", os_version: "11", sdk: 30, cpu_count: 8, gpu: "Mali-G71", gpu_vendor: "ARM", gpu_api: "OpenGL ES 3.2", screen: "720x1520", ram_gb: 1.8, tier: "low" },
    started_at: 1761800000000,
    last_at: 1761800300000,
    ended: false,
    foreground: true,
    screen: "ludo",
    match: { game: "ludo", mode: "cpu", minutes: 4.5, turns: 31 },
    samples: [
      { t: 15, mem: 182.4, mem_peak: 190.1, vmem: 96, fps: 29, objects: 31000, nodes: 2400, screen: "ludo", fg: true },
      { t: 30, mem: 200.5, vmem: 96, fps: 25, objects: 31000, nodes: 2400, screen: "ludo", fg: true },
    ],
    crumbs: [{ t: 0, e: "start", d: "" }, { t: 12, e: "screen", d: "ludo" }],
    exit: null,
    log: "hello",
    ...over,
  };
}

function send(body: unknown, o: { ip?: string; session?: string; now?: number; raw?: string } = {}) {
  const headers: Record<string, string> = { "CF-Connecting-IP": o.ip ?? ip() };
  const r = v1("diag/crash", { method: "POST", body: o.raw !== undefined ? undefined : body, session: o.session, now: o.now ?? T0, headers });
  return o.raw === undefined ? r : rawSend(o.raw, headers, o.now ?? T0);
}

async function rawSend(raw: string, headers: Record<string, string>, now: number) {
  const { SELF } = await import("cloudflare:test");
  const r = await SELF.fetch("https://x/v1/diag/crash", { method: "POST", headers: { ...headers, "X-Test-Now": String(now), "Content-Type": "application/json" }, body: raw });
  return { status: r.status, body: (await r.json()) as Json };
}

const stored = (id: string) => row<Json>("SELECT * FROM crash_reports WHERE id = ?", id);

describe("POST /v1/diag/crash", () => {
  it("stores a valid report and extracts the row fields", async () => {
    const rep = report({ exit: { reason: "low_memory", importance: 100, pss_kb: 250000 }, extra_field: { keep: "me" } });
    const r = await send(rep);
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ok: true, id: expect.stringMatching(/^crs_[a-z2-7]{16}$/) });
    const s = (await stored(r.body.id))!;
    expect(s).toMatchObject({
      received_at: T0 * 1000, pid: rep.pid, sid: rep.sid, account_id: null, app_code: 8, app_version: "0.2.0", model: "SM-A105F", android: "11",
      gpu: "Mali-G71", reason: "low_memory", foreground: 1, screen: "ludo", game: "ludo", mode: "cpu", match_min: 4.5, mem_peak_mb: 200.5,
    });
    expect(s.ip).toMatch(/^[A-Za-z0-9_-]{22}$/);
    const p = JSON.parse(s.payload);
    expect(p.extra_field).toEqual({ keep: "me" });
    expect(p.device.gpu_api).toBe("OpenGL ES 3.2");
    expect(p.samples).toHaveLength(2);
  });

  it("reason: exit.reason, else the trigger, else unknown; strings are cut", async () => {
    const a = await send(report({ trigger: "exit_reason", exit: { reason: "x".repeat(100) } }));
    expect((await stored(a.body.id))!.reason).toBe("x".repeat(40));
    const b = await send(report());
    expect((await stored(b.body.id))!.reason).toBe("unclean");
    const c = await send(report({ trigger: undefined }));
    expect((await stored(c.body.id))!.reason).toBe("unknown");
    const d = await send(report({ foreground: undefined, match: null, samples: [], device: { model: "M".repeat(500) } }));
    const s = (await stored(d.body.id))!;
    expect(s).toMatchObject({ foreground: null, game: null, mem_peak_mb: null });
    expect(s.model).toHaveLength(80);
  });

  it("attaches the account of a valid session; an invalid one is ignored", async () => {
    const g = await guest();
    const a = await send(report(), { session: g.session });
    expect((await stored(a.body.id))!.account_id).toBe(g.id);
    const b = await send(report(), { session: "garbage.token" });
    expect(b.status).toBe(200);
    expect((await stored(b.body.id))!.account_id).toBeNull();
    const c = await send(report(), { session: g.session, now: T0 + 400 * DAY }); // expired
    expect(c.status).toBe(200);
    expect((await stored(c.body.id))!.account_id).toBeNull();
  });

  it("400 on a missing pid / sid, bad JSON and a non-object", async () => {
    for (const bad of [report({ pid: undefined }), report({ sid: undefined }), report({ pid: "" }), report({ sid: 5 }), report({ pid: "   " })]) {
      const r = await send(bad);
      expect(r.status).toBe(400);
      expect(r.body).toEqual({ error: "bad_request" });
    }
    expect((await send(null, { raw: "{nope" })).status).toBe(400);
    expect((await send(null, { raw: "[1]" })).status).toBe(400);
  });

  it("413 over the body limit", async () => {
    const big = JSON.stringify(report({ log: "a".repeat(MAX_BODY) }));
    const r = await send(null, { raw: big });
    expect(r.status).toBe(413);
    expect(r.body).toEqual({ error: "too_large" });
  });

  it("405 on GET", async () => {
    const r = await v1("diag/crash");
    expect(r.status).toBe(405);
  });

  it("dedupes the same pid + sid", async () => {
    const rep = report();
    const a = await send(rep);
    const b = await send(rep);
    expect(b.status).toBe(200);
    expect(b.body).toEqual({ ok: true, dup: true });
    expect((await row<Json>("SELECT COUNT(*) AS c FROM crash_reports WHERE pid = ? AND sid = ?", rep.pid, rep.sid))!.c).toBe(1);
    expect(a.body.id).toBeTruthy();
  });

  it("limits reports per pid (5 a day)", async () => {
    const pid = newPid("crash");
    const t = T0 + 10 * DAY;
    for (let i = 0; i < LIMITS.per_pid; i++) expect((await send(report({ pid }), { now: t })).status).toBe(200);
    const over = await send(report({ pid }), { now: t });
    expect(over.status).toBe(429);
    expect(over.body).toEqual({ error: "rate" });
    expect((await send(report({ pid }), { now: t + DAY + 60 })).status).toBe(200); // a day later
  });

  it("limits reports per IP (20 a day)", async () => {
    const addr = "198.51.100.77";
    const t = T0 + 20 * DAY;
    for (let i = 0; i < LIMITS.per_ip; i++) expect((await send(report(), { ip: addr, now: t })).status, `#${i}`).toBe(200);
    const over = await send(report(), { ip: addr, now: t });
    expect(over.status).toBe(429);
    expect(over.body).toEqual({ error: "rate" });
    expect((await send(report(), { ip: "198.51.100.78", now: t })).status).toBe(200);
    expect((await send(report(), { ip: addr, now: t + DAY + 60 })).status).toBe(200);
  });

  it("caps the stored payload: the log keeps its end, then the trace its start, then samples / crumbs go", async () => {
    // log only (32 KB max, within the cap): kept from the end
    const log = "A".repeat(10) + "B".repeat(40 * 1024) + "TAIL-END";
    const a = await send(report({ log }));
    const pa = JSON.parse((await stored(a.body.id))!.payload);
    expect(pa.log.length).toBe(32 * 1024);
    expect(pa.log.endsWith("TAIL-END")).toBe(true);
    // trace and log together over the cap: the log shrinks first
    const trace = "#00 top frame\n" + "f".repeat(50 * 1024) + "\n#99 bottom";
    const b = await send(report({ log: "L".repeat(30 * 1024) + "LOG-END", exit: { reason: "crash_native", trace: trace + "x".repeat(20 * 1024) } }));
    const row_ = (await stored(b.body.id))!;
    expect(row_.payload.length).toBeLessThanOrEqual(MAX_PAYLOAD);
    const pb = JSON.parse(row_.payload);
    expect(pb.exit.trace.startsWith("#00 top frame")).toBe(true);
    expect(pb.exit.trace.length).toBe(64 * 1024);
    // a payload that only fits when the log is cut: end kept
    const c = await send(report({ log: "M".repeat(22 * 1024) + "LOG-END", exit: { reason: "crash_native", trace: "t".repeat(64 * 1024) }, device: { model: "x", pad: "p".repeat(60 * 1024) } }));
    const pc = JSON.parse((await stored(c.body.id))!.payload);
    expect(bytesOf(pc)).toBeLessThanOrEqual(MAX_PAYLOAD);
    expect(pc.log === "" || pc.log.endsWith("LOG-END") || pc.log.endsWith("M")).toBe(true);
    // samples and crumbs are bounded to 40 / 60 (the last ones stay)
    const d = await send(report({
      samples: Array.from({ length: 100 }, (_, i) => ({ t: i, mem: i })),
      crumbs: Array.from({ length: 100 }, (_, i) => ({ t: i, e: "c", d: String(i) })),
    }));
    const pd = JSON.parse((await stored(d.body.id))!.payload);
    expect(pd.samples).toHaveLength(40);
    expect(pd.samples[39].t).toBe(99);
    expect(pd.crumbs).toHaveLength(60);
    expect(pd.crumbs[0].t).toBe(40);
  });

  it("drops samples and crumbs from the start, then unknown bulk, when log and trace are not enough", async () => {
    // an unknown 100 KB value inside device (kept as given) pushes the payload over the cap with the log and trace already empty
    const a = await send(report({
      log: "",
      exit: { reason: "crash", trace: "" },
      samples: Array.from({ length: 40 }, (_, i) => ({ t: i, mem: 1, screen: "z".repeat(40) })),
      crumbs: Array.from({ length: 60 }, (_, i) => ({ t: i, e: "e", d: "z".repeat(200) })),
      device: { model: "m", pad: "p".repeat(150 * 1024 - 20_000) },
      bulk: "b".repeat(10_000),
    }));
    expect(a.status).toBe(200);
    const sa = (await stored(a.body.id))!;
    expect(sa.payload.length).toBeLessThanOrEqual(MAX_PAYLOAD);
    const pa = JSON.parse(sa.payload);
    expect(pa.samples.length).toBeLessThan(40); // dropped from the start: the newest stay
    if (pa.samples.length) expect(pa.samples[pa.samples.length - 1].t).toBe(39);
    // nothing else fits: unknown fields go, the known ones stay
    const b = await send(report({ device: { model: "SM-X", pad: "p".repeat(150 * 1024) } }));
    const pb = JSON.parse((await stored(b.body.id))!.payload);
    expect(pb.device.model).toBe("SM-X");
    expect(pb.device.pad).toBeUndefined();
    expect(bytesOf(pb)).toBeLessThanOrEqual(MAX_PAYLOAD);
  });

  it("scrubs the log: bearer tokens, JWTs, e-mails, long hex / base64 tokens", async () => {
    const jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123_-xyz";
    const log = [
      "Authorization: Bearer abc.def-ghi123",
      `token ${jwt} end`,
      "mail player@example.com ok",
      `hex ${"ab12".repeat(10)}`,
      `b64 ${"Qm9va1RoaXNJc0FUb2tlbjEyMzQ1Njc4OTBhYmNkZWY"}`,
      "user://logs/godot2026-10-30T10.log is a path and stays",
      "plain_identifier_that_is_quite_long_but_has_no_digits stays",
    ].join("\n");
    const r = await send(report({ log, exit: { reason: "crash", description: "see me@x.org" } }));
    const p = JSON.parse((await stored(r.body.id))!.payload);
    expect(p.log).not.toMatch(/abc\.def-ghi123|eyJ|player@example|ab12ab12|Qm9va1Ro/);
    expect(p.log.match(/\[redacted\]/g)).toHaveLength(5);
    expect(p.log).toContain("user://logs/godot2026-10-30T10.log is a path and stays");
    expect(p.log).toContain("plain_identifier_that_is_quite_long_but_has_no_digits stays");
    expect(p.exit.description).toBe("see [redacted]");
    expect(scrub("nothing here")).toBe("nothing here");
  });
});

const bytesOf = (o: unknown) => new TextEncoder().encode(JSON.stringify(o)).length;
