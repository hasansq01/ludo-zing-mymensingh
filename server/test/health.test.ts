import { SELF } from "cloudflare:test";
import { expect, it } from "vitest";

it("health answers", async () => {
  const r = await SELF.fetch("https://x/v1/health");
  expect(await r.json()).toEqual({ ok: true });
});
