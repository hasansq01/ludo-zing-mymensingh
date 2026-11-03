# Billing plugin (Google Play Billing, gem packs)

Godot Android v2 plugin (Kotlin) for the consumable gem packs. Contract: `server/ECONOMY_V1.md` sections 2 and 6.
Singleton `BillingPlugin` (not `Billing`: that is the GDScript `class_name`); GDScript wrapper
`godot/scripts/net/billing.gd` (`Billing`), a safe stub when the plugin is missing (desktop, headless, the non-Gradle
"Android Emulator" preset).

Play Billing Library: `com.android.billingclient:billing-ktx:8.3.0` (newest 8.x; 9.1.0 exists). minSdk 24.
`enablePendingPurchases(PendingPurchasesParams...enableOneTimeProducts())`. The library's manifest adds the
`com.android.vending.BILLING` permission.

## API (plugin, snake_case)

| Method | Answer |
|---|---|
| `start_connection()` | `connected` / `connect_failed(code, message)`; `disconnected` when Play drops the service. It reconnects with backoff (1 s doubling to 60 s) after a drop or a retryable failure. |
| `query_products(ids: PackedStringArray)` | `products(Array[Dictionary{id, title, description, price, price_micros, currency}])` / `query_failed(code, message)` |
| `purchase(product_id, obfuscated_account_id)` | opens Play's sheet (`setObfuscatedAccountId`); answer from the purchase signals below. Needs a prior `query_products` (else `purchase_failed(-101)`). |
| `query_purchases()` | `owned(Array[Dictionary])`: unconsumed INAPP purchases in state PURCHASED (`query_failed` on error) |
| `consume(token)` | `consumed(token)` / `consume_failed(token, code, message)` |

Purchase updates: `purchased({product_id, token, order_id, state, account_id})`, `pending(product_id)` (cash or
carrier payment still processing), `canceled` (user canceled), `purchase_failed(code, message)`. Our own codes:
`-100` not connected, `-101` unknown product; everything else is a `BillingClient.BillingResponseCode`
(7 = already owned: call `query_purchases` and verify it).

The plugin never acknowledges or consumes by itself. The server verifies the token (`POST /v1/iap/verify`), grants the
gems and consumes it (that also acknowledges, inside Play's 3-day window). `consume()` is only a fallback.

## GDScript wrapper

`Billing`: `available()`, `start()`, `query(ids)`, `buy(product_id, account_id)`, `restore()`, `consume(token)`;
signals `products`, `purchased`, `pending`, `failed(where, code, message)`, `canceled`, `owned`, `consumed`,
`connected`, `disconnected`; pending list `add_pending(p)` / `remove_pending(token)` / `pending_list()` in
`Save.prefs.iap_pending` (`[{product_id, token, at}]`, at most 10, one per token). The expected flow is in the header
of `billing.gd`: buy, `purchased`, `add_pending`, verify, `remove_pending`; on launch `restore()` + `pending_list()`,
verify each.

## Files

| Path | What |
|---|---|
| `src/main/java/com/flipfold/ludozing/billing/BillingPlugin.kt` | The plugin. |
| `src/main/AndroidManifest.xml` | Registration (`org.godotengine.plugin.v2.BillingPlugin`). |
| `godot/addons/billing/` | Editor plugin + export plugin (AAR + the Maven dependency) and the built AARs in `bin/{debug,release}` (checked in). |
| `godot/scripts/net/billing.gd`, `godot/tests/test_billing.gd` | Wrapper and tests. |
| `tools/build-billing-plugin.sh` | Rebuilds both AARs into `godot/addons/billing/bin/`. |

## Build

`tools/build-billing-plugin.sh [--clean]` (JDK 17+, Android SDK; Gradle 8.11.1 wrapper). Only needed after changing the
Kotlin or the version. When changing the version, update `billingVersion` in `build.gradle` and `BILLING_DEPENDENCY` in
`godot/addons/billing/export_plugin.gd`. Export: the `Android` and `Android Release` presets have `plugins/billing=true`
(Gradle build); `Android Emulator` has it false.

## What the owner must set up

1. Play Console > the app > Monetize > In-app products: create four **managed products** (consumable) with the ids
   `gems_80`, `gems_220`, `gems_500`, `gems_1200`, set their prices (Bangladesh taka tiers) and activate them.
2. Upload a build with the BILLING permission to an internal testing track at least once (products can't be bought by an
   app Play has never seen with billing).
3. Play Console > Settings > License testing: add the testers' Google accounts (they buy without being charged).
   Install the game from the testing track on a phone signed in with a tester account.
4. The server side (`PLAY_SERVICE_ACCOUNT` with access to the Android Publisher API for this app) is set up separately.
