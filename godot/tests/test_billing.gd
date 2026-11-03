extends "res://tests/test_suite.gd"
## Billing wrapper (res://scripts/net/billing.gd): the stub everywhere the Android plugin is missing (every call
## answers "unavailable" later than the call, restore() answers nothing owned), the mapping onto the plugin (through a
## fake singleton with the Kotlin plugin's methods and signals), the pending-verification list (cap, dedupe, repair;
## on injected prefs, never the real user://save.json) and the export plugin.

const B := preload("res://scripts/net/billing.gd")
const Export := preload("res://addons/billing/export_plugin.gd")

## Stands in for the Kotlin BillingPlugin singleton: same method and signal names, answers synchronously.
class FakePlugin extends RefCounted:
	signal connected
	signal disconnected
	signal connect_failed(code: int, message: String)
	signal products(list: Array)
	signal query_failed(code: int, message: String)
	signal purchased(purchase: Dictionary)
	signal pending(product_id: String)
	signal purchase_failed(code: int, message: String)
	signal canceled
	signal owned(list: Array)
	signal consumed(token: String)
	signal consume_failed(token: String, code: int, message: String)

	var calls: Array = []

	func start_connection() -> void:
		calls.append("start_connection")
		connected.emit()
	func query_products(ids: PackedStringArray) -> void:
		calls.append("query_products:" + ",".join(ids))
		products.emit([{id = "gems_80", title = "80 gems", description = "d", price = "৳120.00", price_micros = 120000000,
			currency = "BDT"}])
	func purchase(product_id: String, obfuscated_account_id: String) -> void:
		calls.append("purchase:%s:%s" % [product_id, obfuscated_account_id])
		match product_id:
			"gems_80": purchased.emit({product_id = product_id, token = "tok1", order_id = "GPA.1", state = "purchased",
				account_id = obfuscated_account_id})
			"gems_220": pending.emit(product_id)
			"gems_500": canceled.emit()
			_: purchase_failed.emit(7, "already owned")
	func query_purchases() -> void:
		calls.append("query_purchases")
		owned.emit([{product_id = "gems_80", token = "tokA", order_id = "GPA.A", state = "purchased", account_id = "u1"}])
	func consume(token: String) -> void:
		calls.append("consume:" + token)
		if token == "bad":
			consume_failed.emit(token, 8, "not owned")
		else:
			consumed.emit(token)

var _log: Array = []

func run() -> void:
	_stub()
	_stub_is_deferred()
	_plugin()
	_plugin_errors()
	_pending()
	_pending_repair()
	_export()

func make(singleton: Object = null, deferred := false) -> B:
	var b := B.new(singleton, deferred)
	b.use_save = false                      # never the real Save / user://save.json
	b.prefs = {}
	var saves := [0]
	b.persist = func(): saves[0] += 1
	b.set_meta("saves", saves)
	return b

func saves(b: B) -> int:
	return b.get_meta("saves")[0]

func watch(b: B) -> void:
	_log = []
	b.products.connect(func(l): _log.append(["products", l]))
	b.purchased.connect(func(p): _log.append(["purchased", p]))
	b.pending.connect(func(id): _log.append(["pending", id]))
	b.canceled.connect(func(): _log.append(["canceled"]))
	b.owned.connect(func(l): _log.append(["owned", l]))
	b.consumed.connect(func(t): _log.append(["consumed", t]))
	b.failed.connect(func(w, c, m): _log.append(["failed", w, c, m]))
	b.connected.connect(func(): _log.append(["connected"]))
	b.disconnected.connect(func(): _log.append(["disconnected"]))

func _stub() -> void:
	check("stub: no BillingPlugin singleton on desktop / headless", not Engine.has_singleton(B.SINGLETON))
	check("singleton name never shadows the class_name Billing", B.SINGLETON != "Billing")
	var b := make()
	watch(b)
	check("stub: not available", not b.available())
	b.start(); b.query(); b.buy("gems_80", "u1"); b.consume("t")
	check("stub: start / query / buy / consume -> failed(unavailable)", _log == [
		["failed", "connect", B.UNAVAILABLE, "unavailable"], ["failed", "query", B.UNAVAILABLE, "unavailable"],
		["failed", "purchase", B.UNAVAILABLE, "unavailable"], ["failed", "consume", B.UNAVAILABLE, "unavailable"]], _log)
	_log.clear(); b.restore()
	check("stub: restore -> owned([])", _log == [["owned", []]], _log)
	check("stub: calls recorded", b.stub_calls == ["start", "query", "buy:gems_80", "consume", "restore"], b.stub_calls)
	check("product ids: the four gem packs", B.PRODUCT_IDS == ["gems_80", "gems_220", "gems_500", "gems_1200"])
	b.free()

func _stub_is_deferred() -> void:
	var b := make(null, true)
	watch(b)
	b.start(); b.query(); b.restore()
	check("stub (default): answers are deferred, never inside the call", _log.is_empty(), _log)
	b.free()

func _plugin() -> void:
	var fake := FakePlugin.new()
	var b := make(fake)
	watch(b)
	check("plugin: available", b.available())
	b.start()
	check("plugin: start -> connected", _log == [["connected"]] and fake.calls == ["start_connection"], [_log, fake.calls])
	_log.clear(); b.query(PackedStringArray(["gems_80", "gems_220"]))
	check("plugin: query passes the ids and normalises the products", fake.calls.back() == "query_products:gems_80,gems_220"
		and _log == [["products", [{id = "gems_80", title = "80 gems", description = "d", price = "৳120.00",
			price_micros = 120000000, currency = "BDT"}]]], [_log, fake.calls])
	_log.clear(); b.buy("gems_80", "acct-1")
	check("plugin: buy passes the account id; purchased relayed with every key", fake.calls.back() == "purchase:gems_80:acct-1"
		and _log == [["purchased", {product_id = "gems_80", token = "tok1", order_id = "GPA.1", state = "purchased",
			account_id = "acct-1"}]], [_log, fake.calls])
	_log.clear(); b.buy("gems_220", "acct-1"); b.buy("gems_500", "acct-1")
	check("plugin: pending and canceled relayed", _log == [["pending", "gems_220"], ["canceled"]], _log)
	_log.clear(); b.restore()
	check("plugin: restore -> owned(list)", fake.calls.back() == "query_purchases" and _log == [["owned", [{
		product_id = "gems_80", token = "tokA", order_id = "GPA.A", state = "purchased", account_id = "u1"}]]], _log)
	_log.clear(); b.consume("tokA")
	check("plugin: consume -> consumed(token)", _log == [["consumed", "tokA"]] and fake.calls.back() == "consume:tokA", _log)
	check("plugin: the wrapper never consumes by itself", fake.calls.filter(func(c): return c.begins_with("consume")).size() == 1,
		fake.calls)
	fake.disconnected.emit()
	check("plugin: disconnected relayed", _log.back() == ["disconnected"], _log)
	b.free()

func _plugin_errors() -> void:
	var fake := FakePlugin.new()
	var b := make(fake)
	watch(b)
	b.buy("gems_1200", "u")
	check("plugin: purchase_failed -> failed(purchase, code, message)", _log == [["failed", "purchase", 7, "already owned"]], _log)
	_log.clear(); b.consume("bad")
	check("plugin: consume_failed -> failed(consume, code, ...)", _log.size() == 1 and _log[0].slice(0, 3) == ["failed", "consume", 8], _log)
	_log.clear()
	fake.connect_failed.emit(3, "billing unavailable")
	fake.query_failed.emit(2, "service unavailable")
	check("plugin: connect_failed / query_failed -> failed(connect | query)", _log == [["failed", "connect", 3, "billing unavailable"],
		["failed", "query", 2, "service unavailable"]], _log)
	b.free()

func _pending() -> void:
	var b := make()
	check("pending: starts empty", b.pending_list().is_empty())
	b.add_pending({product_id = "gems_80", token = "t1", order_id = "x", state = "purchased", account_id = "u"})
	var l := b.pending_list()
	check("pending: one entry {product_id, token, at}", l.size() == 1 and l[0].product_id == "gems_80" and l[0].token == "t1"
		and int(l[0].at) > 1_700_000_000 and l[0].keys().size() == 3, l)
	check("pending: stored in prefs.iap_pending and persisted", b.prefs.iap_pending.size() == 1 and saves(b) == 1, [b.prefs, saves(b)])
	b.add_pending({product_id = "gems_80", token = "t1"})
	check("pending: the same token twice = one entry (not persisted again)", b.pending_list().size() == 1 and saves(b) == 1, b.pending_list())
	b.add_pending({product_id = "gems_80"})
	check("pending: no token = ignored", b.pending_list().size() == 1)
	l[0].token = "changed"
	check("pending: pending_list() is a copy", b.pending_list()[0].token == "t1")
	b.remove_pending("t1")
	check("pending: remove", b.pending_list().is_empty() and saves(b) == 2, saves(b))
	b.remove_pending("nope")
	check("pending: removing an unknown token is harmless", b.pending_list().is_empty())
	for i in 13:
		b.add_pending({product_id = "gems_80", token = "c%d" % i})
	var l2 := b.pending_list()
	check("pending: capped at 10, the oldest dropped", l2.size() == B.MAX_PENDING and l2[0].token == "c3" and l2[9].token == "c12",
		l2.map(func(e): return e.token))
	b.free()

func _pending_repair() -> void:
	var b := make()
	b.prefs = {iap_pending = [{product_id = "gems_80", token = "ok", at = 5}, "junk", {product_id = "x"}, {token = 7}]}
	var l := b.pending_list()
	check("pending: damaged entries are dropped, good ones kept (strings)", l.size() == 2 and l[0].token == "ok" and l[0].at == 5
		and l[1].token == "7", l)
	var b2 := make()
	b2.prefs = {iap_pending = "nope"}
	check("pending: a non-array value is replaced by an empty list", b2.pending_list().is_empty() and b2.prefs.iap_pending is Array)
	b.free(); b2.free()

func _export() -> void:
	check("export: Maven dependency pinned", Export.BILLING_DEPENDENCY.begins_with("com.android.billingclient:billing-ktx:")
		and Export.BILLING_DEPENDENCY.get_slice(":", 2).split(".").size() == 3, Export.BILLING_DEPENDENCY)
	check("export: plugin name matches the singleton", Export.PLUGIN_NAME == B.SINGLETON)
	check("export: built AARs present", FileAccess.file_exists("res://addons/billing/bin/debug/Billing-debug.aar")
		and FileAccess.file_exists("res://addons/billing/bin/release/Billing-release.aar"))
