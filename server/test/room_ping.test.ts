// Keep-alive: the exact {"t":"ping"} text is answered by the runtime's auto-response ({"t":"pong"}, no now),
// without reaching webSocketMessage; any other ping shape still gets the old pong with now.
import { describe, expect, it } from "vitest";
import { SELF } from "cloudflare:test";
import { createRoom } from "./room_client";

async function raw(path: string): Promise<WebSocket> {
  const r = await SELF.fetch("https://x" + path, { headers: { Upgrade: "websocket" } });
  const ws = r.webSocket!;
  ws.accept();
  return ws;
}
function next(ws: WebSocket): Promise<string> {
  return new Promise((res) => ws.addEventListener("message", (e) => res(String(e.data)), { once: true }));
}

describe("keep-alive auto-response", () => {
  it("room: the exact ping text gets {\"t\":\"pong\"} with no now", async () => {
    const code = await createRoom();
    const ws = await raw(`/v1/rooms/${code}/ws`);
    const p = next(ws);
    ws.send('{"t":"ping"}');
    expect(await p).toBe('{"t":"pong"}');
    ws.close();
  });

  it("room: another ping shape still gets the old pong with now", async () => {
    const code = await createRoom();
    const ws = await raw(`/v1/rooms/${code}/ws`);
    const p = next(ws);
    ws.send('{"t":"ping","v":1}');
    const m = JSON.parse(await p);
    expect(m.t).toBe("pong");
    expect(m.now).toBeGreaterThan(0);
    ws.close();
  });

  it("queue: the exact ping text is auto-answered, other shapes get now", async () => {
    const ws = await raw("/v1/quick/ws?game=ludo&players=2");
    let p = next(ws);
    ws.send('{"t":"ping"}');
    expect(await p).toBe('{"t":"pong"}');
    p = next(ws);
    ws.send('{"t":"ping", "v":1}');
    expect(JSON.parse(await p).now).toBeGreaterThan(0);
    ws.close();
  });
});
