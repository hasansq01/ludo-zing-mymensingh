import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig(async () => {
  // D1: test/setup.ts applies migrations/ to the (per test file) local database before each file.
  const migrations = await readD1Migrations(fileURLToPath(new URL("./migrations", import.meta.url)));
  return {
    plugins: [
      cloudflareTest({
        wrangler: { configPath: "./wrangler.jsonc" },
        // TEST_MODE enables the Room's test hooks (fixed dice, short games, a time scale). It exists only here:
        // wrangler.jsonc has no such var, so deployed rooms ignore and refuse hooks.
        // ADMIN_PASSWORD stands in for the secret (deployed: tools/cf.sh secret put ADMIN_PASSWORD).
        miniflare: {
          bindings: { TEST_MODE: "1", ADMIN_PASSWORD: "test-admin-password", TEST_MIGRATIONS: migrations },
        },
      }),
    ],
    test: { testTimeout: 30_000, setupFiles: ["./test/setup.ts"] },
  };
});
