// The public privacy policy and account-deletion pages (linked from Google Play).
import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

describe("public pages", () => {
  it("/privacy and /delete-account are HTML with the contact address", async () => {
    for (const p of ["privacy", "delete-account"]) {
      const r = await SELF.fetch(`https://x/${p}`);
      expect(r.status).toBe(200);
      expect(r.headers.get("Content-Type")).toContain("text/html");
      const t = await r.text();
      expect(t).toContain("Hello@oclasp.com");
      expect(t).toContain("Ludo Zing");
      expect(t).not.toContain("<script");
    }
    expect((await SELF.fetch("https://x/privacy", { method: "POST" })).status).toBe(405);
  });

  it("/privacy says what the crash report holds and how long it is kept", async () => {
    const t = await (await SELF.fetch("https://x/privacy")).text();
    expect(t).toContain(
      "When the app closes unexpectedly, it sends a diagnostic report (device model, Android version, memory use, which screen was open and the app's own log) that we use only to fix crashes and keep for 90 days.",
    );
  });
});
