extends "res://tests/test_suite.gd"
## Economy v1, the game's wallet UI (server/ECONOMY_V1.md sections 2, 5 and 6) against the fake server and fake plugins:
## the new Account calls, AdFlow (success, cap, no fill, closed early, show failed, polling and its timeout), GemStore's
## verify / pending logic and the Store sheet, gem buying in the Shop, the Home top bar's gem label, the Rewards sheet's
## video section, the Privacy choices row and the achievement gems. Save is swapped for a throwaway profile and its
## debounced write is cut, so user://save.json is never touched.

const Fake := preload("res://tests/fake_accounts.gd")
const FakeBilling := preload("res://tests/fake_billing.gd")
const FakeAds := preload("res://tests/fake_ads.gd")

var _done := false
var _sp: Dictionary
var _spf: Dictionary
var _root: Node

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	_sandbox()
	_all()
	_restore()
	check("econ wallet: the suite ran to the end (nothing suspended for real)", _done)

func _sandbox() -> void:
	_sp = Save.profile
	_spf = Save.prefs
	Save.profile = Fake.base_profile()
	Save.prefs = {}
	Save.normalize()
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)

func _restore() -> void:
	Save._dirty = false
	Save.profile = _sp
	Save.prefs = _spf
	if not Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.connect(Save.flush)

func _all() -> void:
	await _account_calls()
	await _ad_flow()
	await _gem_store()
	await _store_sheet()
	await _shop_gems()
	await _top_bar()
	await _rewards_videos()
	await _privacy_and_ach()
	_done = true


# ---------- helpers ----------

## An Account on the fake server that writes into its own profile (never Save).
func make(fake: Fake) -> Account:
	var a := Account.new()
	a.use_save = false
	a.prefs = {}
	a.profile_own = Fake.base_profile()
	a.url_base = "ws://fake"
	a.http_fn = fake.http
	return a

## An Account that is the current one and writes into Save.profile (the sheets read it).
func live(fake: Fake) -> Account:
	var a := Account.new()
	a.url_base = "ws://fake"
	a.http_fn = fake.http
	a.persist = Callable()
	_root.add_child(a)
	return a

func drop(a: Account) -> void:
	if a.get_parent():
		a.get_parent().remove_child(a)
	Account.set_instance(null)
	a.free()

func texts(n: Node, out: Array = []) -> Array:
	if n is Label:
		out.append((n as Label).text)
	if n is Button and (n as Button).text != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts(c, out)
	return out


# ---------- the Account calls ----------

func _account_calls() -> void:
	var f := Fake.new()
	f.prices["room_neon"] = 3000
	var a := make(f)
	await a.sign_in_guest()
	f.profile.coins = 50000
	f.profile.gems = 100
	await a.refresh_me()
	var r: Dictionary = await a.buy("room", "neon", "gems")
	check("buy: with gems the body says currency gems, 30 gems are paid", r.ok and f.last("/v1/shop/buy").body == {kind = "room", id = "neon", currency = "gems"} and a.profile_own.gems == 70 and a.profile_own.coins == 50000, [r, f.last("/v1/shop/buy")])
	f.prices["dice_gold"] = 900
	r = await a.buy("dice", "gold")
	check("buy: the default currency is coins", r.ok and f.last("/v1/shop/buy").body.currency == "coins" and a.profile_own.coins == 49100)
	f.profile.gems = 2
	r = await a.buy("dice", "gold", "gems")
	check("buy: not enough gems -> error gems with the shortfall", not r.ok and r.error == "gems" and r.short == 7, r)
	var t: Dictionary = await a.fetch_tables()
	check("fetch_tables: GET /v1/tables -> six tables and the broke state", t.ok and t.tables.size() == 6 and t.tables[0].id == "practice" and t.broke == false and f.last("/v1/tables").method == HTTPClient.METHOD_GET, t)
	f.profile.gems = 60
	r = await a.exchange(1)
	check("exchange: 50 gems -> 5,500 coins", r.ok and f.last("/v1/gems/exchange").body == {pack = 1} and r.gems == 50 and r.coins == 5500 and a.profile_own.gems == 10 and a.profile_own.coins == 49100 + 5500, r)
	r = await a.exchange(2)
	check("exchange: too few gems -> error gems (+short)", not r.ok and r.error == "gems" and r.short == 110, r)
	r = await a.claim_broke()
	check("claim_broke: not broke -> not_broke", not r.ok and r.error == "not_broke", r)
	f.profile.coins = 40
	r = await a.claim_broke()
	check("claim_broke: broke -> +300 coins", r.ok and r.coins == 300 and a.profile_own.coins == 340, r)
	r = await a.claim_broke()
	check("claim_broke: the second try is refused", not r.ok, r)
	var td: Dictionary = await a.ads_today()
	check("ads_today: the videos left today", td.ok and td.left.reroll == 3 and td.left.gems == 1 and td.total_left == 8, td)
	var st: Dictionary = await a.ads_start("gems")
	check("ads_start: a nonce, the user id and the custom data", st.ok and st.nonce == "n1" and st.user_id == "acc1" and st.custom_data == "n1" and f.last("/v1/ads/start").body == {kind = "gems"}, st)
	var st2: Dictionary = await a.ads_start("double", "m42")
	check("ads_start: `ref` is sent when given", st2.ok and f.last("/v1/ads/start").body == {kind = "double", ref = "m42"})
	f.profile.coins = 5000
	var st3: Dictionary = await a.ads_start("refill")
	check("ads_start: refill while not broke -> not_eligible", not st3.ok and st3.error == "not_eligible", st3)
	f.ads_left.gems = 0
	var st4: Dictionary = await a.ads_start("gems")
	check("ads_start: no videos left -> cap", not st4.ok and st4.error == "cap", st4)
	var ss: Dictionary = await a.ads_status("n1")
	check("ads_status: granted -> kind, amount and the profile is written", ss.ok and ss.status == "granted" and ss.amount == 2 and a.profile_own.gems == 12 and f.last("/v1/ads/status").path == "/v1/ads/status?nonce=n1", [ss, a.profile_own.gems])
	var sn: Dictionary = await a.ads_status("zzz")
	check("ads_status: an unknown nonce -> not_found", not sn.ok and sn.error == "not_found")
	var ip: Dictionary = await a.iap_products()
	check("iap_products: the packs and their gems", ip.ok and ip.products.size() == 4 and ip.products[0].gems == 80, ip)
	var v1: Dictionary = await a.iap_verify("gems_80", "tokA")
	check("iap_verify: grants the pack", v1.ok and v1.gems == 80 and f.last("/v1/iap/verify").body == {product_id = "gems_80", token = "tokA"} and a.profile_own.gems == 92, [v1, a.profile_own.gems])
	var v2: Dictionary = await a.iap_verify("gems_80", "tokA")
	check("iap_verify: the same token again is a duplicate, nothing more is granted", v2.ok and v2.duplicate == true and a.profile_own.gems == 92, v2)
	f.iap_results["tokB"] = "pending"
	var v3: Dictionary = await a.iap_verify("gems_220", "tokB")
	check("iap_verify: not paid yet -> pending", not v3.ok and v3.error == "pending" and a.profile_own.gems == 92, v3)
	f.iap_results["tokC"] = "invalid"
	var v4: Dictionary = await a.iap_verify("gems_220", "tokC")
	check("iap_verify: a bad purchase -> invalid", not v4.ok and v4.error == "invalid", v4)
	f.iap_results["tokD"] = "unavailable"
	var v5: Dictionary = await a.iap_verify("gems_220", "tokD")
	check("iap_verify: Play down -> unavailable (503)", not v5.ok and v5.error == "unavailable" and v5.status == 503, v5)
	var ac: Dictionary = await a.claim_ach("first")
	check("claim_ach: the answer carries the gems (+10)", ac.ok and ac.coins == 200 and ac.gems == 10 and a.profile_own.gems == 102, ac)
	for code in ["gems", "cap", "not_eligible", "not_broke", "pending", "invalid", "unavailable", "locked"]:
		var txt := Account.error_text(code)
		check("error_text: %s has its own friendly line" % code, txt != "" and txt != Account.error_text("zzz") and not txt.contains(code.to_upper()), txt)
	check("error_text: gems says gems", Account.error_text("gems") == "Not enough gems.")
	f.online = false
	var off: Dictionary = await a.exchange(0)
	check("calls: offline -> error offline", not off.ok and off.error == "offline", off)
	a.free()


# ---------- AdFlow ----------

## An AdFlow on a fake AdMob plugin and the fake server; its waits are instant. Returns {flow, ads, plugin, acc, fake, log}.
func flow_rig(show_result := "watched") -> Dictionary:
	var f := Fake.new()
	var acc := make(f)
	acc.prefs = {}
	var plugin := FakeAds.new()
	plugin.show_result = show_result
	var ads := Ads.new(plugin, false)
	var flow := AdFlow.new(ads, acc)
	flow.sleep_fn = func(_s: float): pass
	var log := []
	flow.done.connect(func(ok: bool, info: Dictionary): log.append([ok, info]))
	return {flow = flow, ads = ads, plugin = plugin, acc = acc, fake = f, log = log}

func free_rig(r: Dictionary) -> void:
	for k in ["flow", "ads", "acc"]:
		(r[k] as Node).free()

func _ad_flow() -> void:
	# success: gems
	var r := flow_rig()
	await r.acc.sign_in_guest()
	await r.flow.watch("gems")
	var res: Array = r.log[0]
	check("adflow: a watched video grants the gems", res[0] and res[1].kind == "gems" and res[1].amount == 2 and r.acc.profile_own.gems == 2, r.log)
	check("adflow: the ad is shown with the user id and the nonce from /v1/ads/start", r.plugin.calls.has("show_rewarded:acc1:n1"), r.plugin.calls)
	check("adflow: polls /v1/ads/status for the nonce, and is no longer busy", r.fake.count("/v1/ads/status") == 1 and not r.flow.busy)
	# success: re-roll
	r.plugin.ready = true                                # (a new ad loads by itself after one closes)
	await r.flow.watch("reroll")
	check("adflow: a re-roll video adds a free re-roll", r.log.size() == 2 and r.log[1][0] and r.log[1][1].kind == "reroll" and r.acc.profile_own.rerolls == 1, r.log)
	free_rig(r)
	# the server needs a few polls
	r = flow_rig()
	await r.acc.sign_in_guest()
	r.fake.ads_pending_polls = 2
	await r.flow.watch("gems")
	check("adflow: pending, pending, granted -> three polls, then the reward", r.log[0][0] and r.fake.count("/v1/ads/status") == 3, [r.log, r.fake.count("/v1/ads/status")])
	free_rig(r)
	# polling timeout
	r = flow_rig()
	await r.acc.sign_in_guest()
	r.fake.ads_pending_polls = 999
	await r.flow.watch("gems")
	var polls: int = r.fake.count("/v1/ads/status")
	check("adflow: still pending after 20 s -> timeout (polls every 1.5 s)", not r.log[0][0] and r.log[0][1].error == "timeout" and polls >= 13 and polls <= 16 and r.log[0][1].text != "", [r.log, polls])
	check("adflow: ...and the profile is asked for once more", r.fake.count("/v1/me") >= 1)
	free_rig(r)
	# the server turns the reward down
	r = flow_rig()
	await r.acc.sign_in_guest()
	r.fake.ads_final = "rejected"
	await r.flow.watch("gems")
	check("adflow: a rejected reward -> error rejected", not r.log[0][0] and r.log[0][1].error == "rejected", r.log)
	free_rig(r)
	# cap
	r = flow_rig()
	await r.acc.sign_in_guest()
	r.fake.ads_left.gems = 0
	await r.flow.watch("gems")
	check("adflow: no videos left -> cap, and no ad is shown", not r.log[0][0] and r.log[0][1].error == "cap" and not r.plugin.calls.any(func(c): return str(c).begins_with("show_rewarded")), r.log)
	free_rig(r)
	# no ad loaded
	r = flow_rig()
	await r.acc.sign_in_guest()
	r.plugin.ready = false
	await r.flow.watch("gems")
	check("adflow: no ad loaded -> the friendly line, and nothing is started", not r.log[0][0] and r.log[0][1].error == "no_fill" and r.log[0][1].text == "No video right now, try again in a minute." and r.fake.count("/v1/ads/start") == 0, r.log)
	free_rig(r)
	# the ad can't be shown
	r = flow_rig("fail")
	await r.acc.sign_in_guest()
	await r.flow.watch("gems")
	check("adflow: show failed -> no_fill", not r.log[0][0] and r.log[0][1].error == "no_fill" and r.fake.count("/v1/ads/status") == 0, r.log)
	free_rig(r)
	# closed before the reward
	r = flow_rig("early")
	await r.acc.sign_in_guest()
	await r.flow.watch("gems")
	check("adflow: closed without the reward -> closed, nothing is polled or granted", not r.log[0][0] and r.log[0][1].error == "closed" and r.fake.count("/v1/ads/status") == 0 and r.acc.profile_own.gems == 0, r.log)
	free_rig(r)
	# the double ad carries the match id
	r = flow_rig()
	await r.acc.sign_in_guest()
	await r.flow.watch("double", "m7")
	check("adflow: `ref` goes to /v1/ads/start", r.fake.last("/v1/ads/start").body == {kind = "double", ref = "m7"} and r.log[0][0], r.fake.last("/v1/ads/start"))
	free_rig(r)
	# offline
	r = flow_rig()
	await r.acc.sign_in_guest()
	r.fake.online = false
	r.acc._session = ""
	await r.flow.watch("gems")
	check("adflow: offline -> error offline with the connect line", not r.log[0][0] and r.log[0][1].error == "offline" and r.log[0][1].text == Account.offline_text("ads"), r.log)
	free_rig(r)
	# off Android: the stub
	var f := Fake.new()
	var acc := make(f)
	var flow := AdFlow.new(Ads.new(), acc)
	var log := []
	flow.done.connect(func(ok: bool, info: Dictionary): log.append([ok, info]))
	await flow.watch("gems")
	check("adflow: off Android (no plugin) -> done(false, unavailable)", log.size() == 1 and not log[0][0] and log[0][1].error == "unavailable" and f.calls.is_empty(), log)
	flow.free()
	acc.free()
	# available()
	check("adflow: available() is false without Ads / Account", not AdFlow.available())
	var r2 := flow_rig()
	Ads.set_instance(r2.ads)
	Account.set_instance(r2.acc)
	check("adflow: available() with the plugin and an Account", AdFlow.available())
	Account.set_instance(null)
	check("adflow: ...not without an Account", not AdFlow.available())
	Ads.set_instance(Ads.new())
	var stub_ads := Ads.instance()
	Account.set_instance(r2.acc)
	check("adflow: ...not with the stub", not AdFlow.available())
	Account.set_instance(null)
	Ads.set_instance(null)
	stub_ads.free()
	free_rig(r2)
	# a second watch while one is running is ignored
	var r3 := flow_rig()
	await r3.acc.sign_in_guest()
	r3.flow.busy = true
	await r3.flow.watch("gems")
	check("adflow: busy -> a second watch is ignored", r3.log.size() == 0)
	r3.flow.busy = false
	free_rig(r3)


# ---------- GemStore (Billing + verify) ----------

func store_rig() -> Dictionary:
	var f := Fake.new()
	var acc := make(f)
	var plugin := FakeBilling.new()
	var billing := Billing.new(plugin, false)
	billing.use_save = false
	billing.prefs = {}
	billing.persist = func(): pass
	var store := GemStore.new(billing, acc)
	_root.add_child(store)
	var log := []
	store.granted.connect(func(g: int, p: String): log.append(["granted", g, p]))
	store.rejected.connect(func(p: String): log.append(["rejected", p]))
	return {store = store, billing = billing, plugin = plugin, acc = acc, fake = f, log = log}

func free_store(r: Dictionary) -> void:
	_root.remove_child(r.store)
	(r.store as Node).free()
	(r.acc as Node).free()

func _gem_store() -> void:
	var r := store_rig()
	await r.acc.sign_in_guest()
	var s: GemStore = r.store
	check("store: gems_of reads the pack size from the id", GemStore.gems_of("gems_80") == 80 and GemStore.gems_of("gems_1200") == 1200 and GemStore.gems_of("x") == 0)
	check("store: available with the plugin", s.available() and not s.payment_pending())
	s.billing.query()
	check("store: query fills the packs, cheapest first, with the Play prices", s.products.size() == 4 and s.products[0].id == "gems_80" and s.products[3].id == "gems_1200" and s.product("gems_80").price == "৳120.00", s.products)
	# buy -> purchased -> pending list -> verify -> removed -> +80 gems
	s.buy("gems_80")
	check("store: the purchase carries the account id", r.plugin.calls.has("purchase:gems_80:acc1"), r.plugin.calls)
	check("store: verified with the server and the gems added (+80)", r.log == [["granted", 80, "gems_80"]] and r.acc.profile_own.gems == 80 and r.fake.count("/v1/iap/verify") == 1, [r.log, r.acc.profile_own.gems])
	check("store: ...and the pending entry is gone after the verify", r.billing.pending_list().is_empty() and not s.payment_pending() and not s.buying)
	# a payment that isn't through yet stays in the list
	r.fake.iap_results["tok2"] = "pending"
	s.buy("gems_220")
	check("store: 409 pending keeps the purchase in the list (Payment pending…)", s.payment_pending() and r.billing.pending_list().size() == 1 and r.billing.pending_list()[0].token == "tok2" and r.log.size() == 1 and r.acc.profile_own.gems == 80, [r.billing.pending_list(), r.log])
	r.fake.iap_results.erase("tok2")
	var n: int = await s.verify_pending()
	check("store: verify_pending grants it once the payment went through", n == 1 and r.log.size() == 2 and r.log[1] == ["granted", 220, "gems_220"] and r.acc.profile_own.gems == 300 and not s.payment_pending(), [r.log, r.acc.profile_own.gems])
	# Play down (503) and offline keep it
	r.fake.iap_results["tok3"] = "unavailable"
	s.buy("gems_500")
	check("store: 503 unavailable keeps the purchase for the next try", s.payment_pending() and r.log.size() == 2, r.billing.pending_list())
	r.fake.iap_results.erase("tok3")
	r.fake.online = false
	r.acc._session = ""
	n = await s.verify_pending()
	check("store: offline keeps it too", n == 0 and s.payment_pending())
	r.fake.online = true
	n = await s.verify_pending()
	check("store: ...and it is verified when the connection is back", n == 1 and not s.payment_pending() and r.acc.profile_own.gems == 800, [n, r.acc.profile_own.gems])
	# an invalid purchase is dropped (and told)
	r.fake.iap_results["tok4"] = "invalid"
	s.buy("gems_80")
	check("store: invalid is removed from the list and reported", not s.payment_pending() and r.log[r.log.size() - 1] == ["rejected", "gems_80"] and r.acc.profile_own.gems == 800, r.log)
	# the same token verified again says duplicate: no second "+gems"
	var before: int = r.log.size()
	var d: Dictionary = await s.verify({product_id = "gems_80", token = "tok1"})
	check("store: a duplicate answer is removed from the list, with no new toast", d.ok and d.duplicate and r.log.size() == before and r.acc.profile_own.gems == 800, d)
	# canceled / slow payment method
	r.plugin.buy_result = "canceled"
	s.buy("gems_80")
	check("store: canceled -> nothing pending, not buying", not s.buying and not s.payment_pending())
	r.plugin.buy_result = "pending"
	s.buy("gems_80")
	check("store: a slow payment method (Play says pending) -> not buying, nothing granted", not s.buying and r.acc.profile_own.gems == 800)
	r.plugin.buy_result = "failed"
	s.buy("gems_80")
	check("store: a failed purchase -> not buying", not s.buying)
	free_store(r)
	# launch: what an earlier run left unverified + what Play still holds
	r = store_rig()
	await r.acc.sign_in_guest()
	r.billing.add_pending({product_id = "gems_80", token = "old1"})
	r.plugin.owned_list = [{product_id = "gems_220", token = "held1", order_id = "GPA.9", state = "purchased", account_id = "acc1"},
		{product_id = "gems_500", token = "wait1", order_id = "GPA.10", state = "pending", account_id = "acc1"}]
	await r.store.launch_check()
	check("launch: verifies the pending list, restores and verifies what Play holds", r.acc.profile_own.gems == 80 + 220 and r.plugin.calls.has("start_connection") and r.plugin.calls.has("query_purchases") and r.fake.iap_tokens.has("old1") and r.fake.iap_tokens.has("held1"), [r.acc.profile_own.gems, r.plugin.calls])
	check("launch: a purchase Play still processes is not sent to the server", not r.fake.iap_tokens.has("wait1") and r.billing.pending_list().is_empty(), r.billing.pending_list())
	check("launch: both grants were announced", r.log.size() == 2, r.log)
	r.plugin.calls.clear()
	await r.store.check()
	check("check (the Store opened): asks Play again for what it holds", r.plugin.calls.has("query_purchases"), r.plugin.calls)
	free_store(r)
	# off Android
	var f := Fake.new()
	var acc := make(f)
	var off := GemStore.new(Billing.new(), acc)
	_root.add_child(off)
	check("store: off Android there is no billing", not off.available())
	_root.remove_child(off)
	off.free()
	acc.free()


# ---------- the Store sheet ----------

func _store_sheet() -> void:
	var f := Fake.new()
	var acc := live(f)
	await acc.sign_in_guest()
	f.profile.gems = 10
	f.profile.coins = 700
	await acc.refresh_me()
	var plugin := FakeBilling.new()
	var billing := Billing.new(plugin, false)
	billing.use_save = false
	billing.prefs = {}
	billing.persist = func(): pass
	var store := GemStore.new(billing, acc)
	_root.add_child(store)
	var sheet := StoreSheet.new(store)
	_root.add_child(sheet)
	var tx := texts(sheet)
	check("store sheet: current balances on top", sheet.coins_chip.text() == "700" and sheet.gems_chip.text() == "10", [sheet.coins_chip.text(), sheet.gems_chip.text()])
	check("store sheet: opening it asks Play for the prices and what it holds", plugin.calls.has("query_products") and plugin.calls.has("query_purchases"), plugin.calls)
	check("store sheet: four packs with titles and the Play prices", tx.has("80 gems") and tx.has("1,200 gems") and tx.has("৳120.00") and tx.has("৳1,200.00"), tx)
	var btn: Button = sheet._pack_buttons["gems_80"]
	check("store sheet: a pack button is a 48 px target", btn.get_combined_minimum_size().y >= 40.0 and not btn.disabled, btn.get_combined_minimum_size())
	check("store sheet: the three swaps (10 -> 1K ...)", tx.has("1K") and tx.has("5.5K") and tx.has("14K"), tx)
	check("store sheet: with 10 gems only the first swap is on", sheet._swap_buttons[0].text == "Swap" and sheet._swap_buttons[1].text == "Need 40" and sheet._swap_buttons[2].text == "Need 110", [sheet._swap_buttons[0].text, sheet._swap_buttons[1].text])
	check("store sheet: no pending card without a pending payment", not sheet._pending.visible)
	# buy: the toast text goes through and the balance follows
	f.iap_results["tok1"] = "pending"
	sheet._on_pack("gems_80")
	check("store sheet: a payment in flight shows Payment pending…", sheet._pending.visible and texts(sheet._pending).has("Payment pending…"), texts(sheet._pending))
	f.iap_results.erase("tok1")
	await store.verify_pending()
	check("store sheet: when it goes through the gems arrive and the card goes away", Save.profile.gems == 90 and sheet.gems_chip.text() == "90" and not sheet._pending.visible, [Save.profile.gems, sheet.gems_chip.text()])
	check("store sheet: with 90 gems two swaps are on", sheet._swap_buttons[1].text == "Swap" and sheet._swap_buttons[2].text == "Need 30")
	# swapping through the account (the sheet's confirm is tested by the Shop's pattern; the call is the same)
	var r: Dictionary = await acc.exchange(0)
	check("store sheet: a swap moves the balances", r.ok and sheet.gems_chip.text() == "80" and sheet.coins_chip.text() == "1.7K", [sheet.gems_chip.text(), sheet.coins_chip.text()])
	# too few gems for a swap: says how many, charges nothing
	var calls: int = f.count("/v1/gems/exchange")
	Save.profile.gems = 3
	sheet.refresh()
	sheet._on_swap(0)
	check("store sheet: too few gems -> no call", f.count("/v1/gems/exchange") == calls and sheet._swap_buttons[0].text == "Need 7", sheet._swap_buttons[0].text)
	# buying is refused without an account session (the wallet is the server's)
	_root.remove_child(sheet)
	sheet.free()
	_root.remove_child(store)
	store.free()
	# off Android
	var off := GemStore.new(Billing.new(), acc)
	_root.add_child(off)
	var s2 := StoreSheet.new(off)
	_root.add_child(s2)
	var t2 := texts(s2)
	check("store sheet: off Android says the packs are in the Android app", t2.has("Gem packs are available in the Android app.") and s2._pack_buttons.is_empty() and t2.has("Swap gems for coins"), t2)
	_root.remove_child(s2)
	s2.free()
	_root.remove_child(off)
	off.free()
	drop(acc)
	Save.profile.clear()
	Save.profile.merge(Fake.base_profile())
	Save.normalize()


# ---------- gems in the Shop ----------

func _shop_gems() -> void:
	var f := Fake.new()
	f.profile.gems = 50
	f.prices["room_dream"] = 3000
	f.prices["dice_gold"] = 900
	var acc := live(f)
	await acc.sign_in_guest()
	var shop := ShopSheet.new("rooms")
	_root.add_child(shop)
	var gem_rows := shop.find_children("GemBuy", "Button", true, false)
	check("shop: every item with a price has a gem option", gem_rows.size() >= 3, gem_rows.size())
	var sale: Button = null
	for g: Button in gem_rows:
		if int(g.get_meta("gems", 0)) == 30:
			sale = g
	check("shop: Pastel Dream Room (3,000 coins) offers 30 gems, and the line says so", sale != null and sale.modulate.a == 1.0 and not sale.disabled and texts(sale).has("or") and texts(sale).has("30"), texts(shop))
	var owned_row: Button = null
	for g: Button in gem_rows:
		if g.modulate.a == 0.0:
			owned_row = g
	check("shop: a gem line that isn't for sale is hidden (and not tappable)", owned_row == null or owned_row.disabled)
	check("shop: the gem price is Catalog.gem_price", Catalog.gem_price(3000) == 30 and Catalog.gem_price(4000) == 40)
	var err: String = await shop._purchase("room", "dream", "gems")
	check("shop: buying with gems goes through the server (currency gems)", err == "" and f.last("/v1/shop/buy").body.currency == "gems" and Save.profile.gems == 20 and Save.profile.rooms.has("dream") and Save.profile.coins == 5000, [err, Save.profile.gems])
	f.profile.gems = 5
	await acc.refresh_me()
	err = await shop._purchase("dice", "gold", "gems")
	check("shop: ...9 gems needed, 5 held: the line says 4", err == ShopSheet.gems_need_text(4) and err.contains("4 more"), err)
	# the tap: not enough gems asks to open the Store (the confirm's text names the shortfall)
	var asked := [0]
	shop.store_requested.connect(func(): asked[0] += 1)
	shop._on_buy_gems("room", "studio", "Sunny Cozy Studio")        # 40 gems, 5 held (suspends at the confirm)
	var confirm: Sheet = null
	for s in shop.find_children("*", "Sheet", true, false):
		if s.has_meta("confirm"):
			confirm = s
	var ct := texts(confirm) if confirm else []
	check("shop: not enough gems -> a dialog with the shortfall and Open Store", confirm != null and ct.has("Not enough gems") and ct.has("Open Store") and ct.any(func(t): return str(t).contains("35 more")), ct)
	if confirm:
		confirm.get_parent().remove_child(confirm)
		confirm.free()
	shop.free()
	# offline: gems live on the server
	var shop2 := ShopSheet.new("rooms")
	_root.add_child(shop2)
	f.online = false
	acc._session = ""
	Account.set_instance(null)
	var coins_before: int = Save.profile.coins
	shop2._on_buy_gems("room", "cloud", "Cloudside Playroom")
	check("shop: without an account nothing is bought with gems", Save.profile.coins == coins_before and not Save.profile.rooms.has("cloud"))
	shop2.free()
	Account.set_instance(acc)
	drop(acc)
	Save.profile.clear()
	Save.profile.merge(Fake.base_profile())
	Save.normalize()


# ---------- the top bar ----------

func _top_bar() -> void:
	var frame := Control.new()
	frame.size = Vector2(390, 844)
	_root.add_child(frame)
	var h := HomeScreen.new()
	frame.add_child(h)
	h._layout()
	Save.profile.gems = 0
	Save.changed.emit()
	check("top bar: the gem balance sits under the coins", h.gem_amount != null and h.gem_amount.text() == "0" and h.gem_amount.icon_name == "gem")
	Save.profile.gems = 35
	Save.changed.emit()
	check("top bar: the gem label follows Save.changed", h.gem_amount.text() == "35", h.gem_amount.text())
	Save.profile.gems = 1234
	Save.changed.emit()
	check("top bar: big balances are written in full", h.gem_amount.text() == "1,234", h.gem_amount.text())
	check("top bar: ...next to the coins", h.coin_amount.text() == Fmt.coins(int(Save.profile.coins)), h.coin_amount.text())
	var tabs := []
	h.open_tab.connect(func(t: String): tabs.append(t))
	h._gems_button.pressed.emit()
	check("top bar: tapping the gems opens the Store", tabs == ["store"], tabs)
	check("top bar: tapping the coins still opens the coins hub", (h.coin_amount.get_parent().get_parent() as Button).name == "Coins" and (func():
		(h.coin_amount.get_parent().get_parent() as Button).pressed.emit()
		return tabs == ["store", "coins"]).call(), tabs)
	check("top bar: the bar still fits the 390 px width (name and XP bar shown)", h._chip_text.visible and h._top.size.x <= 358.5, [h._chip_text.visible, h._top.size])
	check("top bar: both rows are tap targets of at least 22 px inside a 52 px bar", h._gems_button.custom_minimum_size.y >= 22.0 and h._top.size.y == HomeScreen.BAR_H)
	_root.remove_child(frame)
	frame.free()
	Save.profile.gems = 0


# ---------- Rewards: Free with a video ----------

func _rewards_videos() -> void:
	var plain := RewardsSheet.new()
	_root.add_child(plain)
	check("rewards: no video section where ads can't run", plain._video_box == null and not texts(plain).has("Free with a video"), texts(plain))
	_root.remove_child(plain)
	plain.free()
	var f := Fake.new()
	var acc := live(f)
	await acc.sign_in_guest()
	RewardsSheet.force_videos = true
	var s := RewardsSheet.new()
	_root.add_child(s)
	RewardsSheet.force_videos = false
	var tx := texts(s)
	check("rewards: Free with a video, with the re-roll and the gems rows", tx.has("Free with a video") and tx.has("Free re-roll") and tx.has("+2 gems"), tx)
	check("rewards: each row says how many are left today", tx.has("3 left today") and tx.has("1 left today"), tx)
	f.ads_left.gems = 0
	await s.load_today()
	var gv: RewardsSheet.VideoRow = s.video_row("gems")
	check("rewards: no gems video left -> Done today, the Watch button is gone", gv.wait.visible and not gv.go.visible and gv.note.text == "Come back tomorrow", [gv.note.text, gv.wait_label.text])
	var rv: RewardsSheet.VideoRow = s.video_row("reroll")
	check("rewards: the re-roll row keeps its Watch button (3 left)", rv.go.visible and rv.note.text.begins_with("3 left today"))
	Save.profile.rerolls = 2
	s._refresh_videos()
	check("rewards: it also says how many re-rolls you hold", rv.note.text == "3 left today · you have 2", rv.note.text)
	check("rewards: the rows are 72 px tall like the others", rv.custom_minimum_size.y == 72.0 and (s.row("spin") as Control).custom_minimum_size.y == 72.0)
	Save.profile.rerolls = 0
	_root.remove_child(s)
	s.free()
	drop(acc)
	Save.profile.clear()
	Save.profile.merge(Fake.base_profile())
	Save.normalize()


# ---------- Privacy choices and the achievements' gems ----------

func _privacy_and_ach() -> void:
	var plugin := FakeAds.new()
	var ads := Ads.new(plugin, false)
	var plain := SettingsSheet.new()
	_root.add_child(plain)
	check("privacy: no Privacy choices row without ads", plain.find_child("PrivacyChoices", true, false) == null)
	_root.remove_child(plain)
	plain.free()
	Ads.set_instance(ads)
	var s0 := SettingsSheet.new()
	_root.add_child(s0)
	check("privacy: ...nor before the consent form has said so", s0.find_child("PrivacyChoices", true, false) == null)
	_root.remove_child(s0)
	s0.free()
	ads.request_consent()
	check("privacy: the consent form was asked for, and it says choices are required", plugin.calls.has("request_consent") and ads.privacy_options_required())
	var s := SettingsSheet.new()
	_root.add_child(s)
	var row := s.find_child("PrivacyChoices", true, false)
	check("privacy: a Privacy choices row under Help", row != null and texts(row).has("Privacy choices"), texts(s))
	if row:
		row.emit_signal("tapped")
	check("privacy: tapping it shows the privacy options form", plugin.calls.has("show_privacy_options"), plugin.calls)
	_root.remove_child(s)
	s.free()
	plugin.privacy = false
	ads.request_consent()
	var s2 := SettingsSheet.new()
	_root.add_child(s2)
	check("privacy: no row when the form says nothing is needed", s2.find_child("PrivacyChoices", true, false) == null)
	_root.remove_child(s2)
	s2.free()
	Ads.set_instance(null)
	ads.free()
	# achievements: +10 gems next to the coins, with an account
	var f := Fake.new()
	var acc := live(f)
	await acc.sign_in_guest()
	var ps := ProfileSheet.new()
	_root.add_child(ps)
	ps.show_pane("ach")
	var claim: Button = ps._claim_btns.get("first")
	check("achievements: the Claim button shows the coins and +10 gems", claim != null and texts(claim).has("Claim") and claim.find_child("Gems", true, false) != null and texts(claim).has("+10"), texts(claim) if claim else null)
	Save.profile.stats.wins = 1
	Save.profile.stats.played = 1
	var r: Dictionary = await acc.claim_ach("first")
	check("achievements: the server's answer has coins and gems", r.ok and r.gems == 10 and Save.profile.gems == 10, r)
	_root.remove_child(ps)
	ps.free()
	drop(acc)
	Save.profile.clear()
	Save.profile.merge(Fake.base_profile())
	Save.normalize()

