class_name Billing
extends Node
## Google Play Billing for the gem packs (server/ECONOMY_V1.md sections 2 and 6): a thin wrapper over the
## "BillingPlugin" Android plugin singleton (godot/android/plugins/billing). Everywhere the plugin is missing (desktop,
## headless, web, the non-Gradle "Android Emulator" preset) it is a safe stub: available() is false, start / query / buy /
## consume answer failed(where, UNAVAILABLE, "unavailable"), restore() answers owned([]). Answers always arrive later
## (deferred), never inside the call that asked.
##
## Expected flow (the shop UI and the launch code do this; this class only relays and keeps the pending list):
##   var b := Billing.new(); add_child(b)
##   b.start()                                   # once; the plugin reconnects by itself if Play drops the service
##   b.query(PRODUCT_IDS)  -> products(list)     # [{id, title, description, price, price_micros, currency}] for the shop
##   b.buy("gems_80", Account.id())              # the account id is attached to the purchase (obfuscated account id)
##   -> purchased(p)       # {product_id, token, order_id, state, account_id}: b.add_pending(p) FIRST, then
##                         # POST /v1/iap/verify {product_id, token}; on {ok} or {duplicate} or 409 invalid:
##                         # b.remove_pending(token). On 409 pending / 503 / no network keep it (retried).
##                         # The server grants the gems and consumes the purchase; the game never consumes.
##   -> pending(product_id)   # slow payment (cash, carrier): tell the player; the token arrives later, as
##                            # owned() on the next restore() (or a later purchased)
##   -> canceled()            # the player closed the sheet: nothing to tell
##   -> failed("purchase", code, message)
## On launch (after start() reports connected, or after a failed purchase with code ITEM_ALREADY_OWNED = 7):
##   b.restore()  -> owned(list)                 # unconsumed purchases Play still holds
##   verify every entry of owned(list) and of b.pending_list() the same way (POST /v1/iap/verify, then remove_pending).
## consume(token) is only a fallback for a purchase the server can't consume; -> consumed(token).
## failed(where, code, message): where is "connect" | "query" (products and restore) | "purchase" | "consume"; code is
## a BillingClient.BillingResponseCode (1 user canceled -> canceled instead, 2 service unavailable, 3 billing
## unavailable, 4 item unavailable, 5 developer error, 6 error, 7 already owned, 8 not owned, -1 service disconnected,
## -2 feature not supported, -3 service timeout), or NOT_CONNECTED (-100) / UNKNOWN_PRODUCT (-101, buy() before
## query()) / UNAVAILABLE (-102, no plugin).

## Product list answer to query(): [{id, title, description, price, price_micros, currency}].
signal products(list: Array)
## Paid: {product_id, token, order_id, state, account_id}. Verify with the server, never grant locally.
signal purchased(purchase: Dictionary)
## A slow payment method is still processing for this product.
signal pending(product_id: String)
signal canceled
## Unconsumed purchases after restore(): same dictionaries as `purchased`.
signal owned(list: Array)
signal consumed(token: String)
signal failed(where: String, code: int, message: String)
## Play service connection (start()). The plugin reconnects with backoff after `disconnected`.
signal connected
signal disconnected

const SINGLETON := "BillingPlugin"
## Product ids of the gem packs (server/ECONOMY_V1.md section 2), cheapest first.
const PRODUCT_IDS := ["gems_80", "gems_220", "gems_500", "gems_1200"]
const NOT_CONNECTED := -100
const UNKNOWN_PRODUCT := -101
const UNAVAILABLE := -102
## Most entries kept in Save.prefs.iap_pending (the oldest is dropped past that).
const MAX_PENDING := 10

## Where the pending list lives. Default: Save.prefs (the Save autoload); tests (or a detached Save) set `prefs` and
## `persist` themselves and `use_save` false.
var use_save := true
var prefs: Dictionary = {}
var persist := Callable()
## Stub only: how many calls reached the stub, per method (tests).
var stub_calls: Array = []

var _pg: Object = null
var _deferred := true
var _defaults_done := false

## `singleton`: the Android plugin object; null = Engine.get_singleton("BillingPlugin") when it exists. Tests pass a fake
## with the same methods and signals, and `deferred` false to get the answers inside the call.
func _init(singleton: Object = null, deferred := true) -> void:
	_deferred = deferred
	if singleton == null and Engine.has_singleton(SINGLETON):
		singleton = Engine.get_singleton(SINGLETON)
	_pg = singleton
	if _pg == null:
		return
	_connect("connected", func(): connected.emit())
	_connect("disconnected", func(): disconnected.emit())
	_connect("connect_failed", func(c, m): failed.emit("connect", int(c), str(m)))
	_connect("products", _on_products)
	_connect("query_failed", func(c, m): failed.emit("query", int(c), str(m)))
	_connect("purchased", _on_purchased)
	_connect("pending", func(id): pending.emit(str(id)))
	_connect("purchase_failed", func(c, m): failed.emit("purchase", int(c), str(m)))
	_connect("canceled", func(): canceled.emit())
	_connect("owned", _on_owned)
	_connect("consumed", func(t): consumed.emit(str(t)))
	_connect("consume_failed", func(t, c, m): failed.emit("consume", int(c), "%s (%s)" % [str(m), str(t).left(8)]))

func _ready() -> void:
	_defaults()

## True on Android with the plugin built in.
func available() -> bool:
	return _pg != null

## Connects to Google Play. -> connected | failed("connect", code, message).
func start() -> void:
	if _pg == null:
		_stub_fail("start", "connect")
		return
	_pg.call("start_connection")

## Prices and titles of the product ids (INAPP). -> products(list) | failed("query", ...). Call before buy().
func query(ids: PackedStringArray = PackedStringArray(PRODUCT_IDS)) -> void:
	if _pg == null:
		_stub_fail("query", "query")
		return
	_pg.call("query_products", ids)

## Opens Play's purchase sheet. `account_id` is attached to the purchase (the server's account id).
## -> purchased | pending | canceled | failed("purchase", ...).
func buy(product_id: String, account_id: String) -> void:
	if _pg == null:
		_stub_fail("buy:" + product_id, "purchase")
		return
	_pg.call("purchase", product_id, account_id)

## Unconsumed purchases (after a crash or a failed verify). -> owned(list) | failed("query", ...).
func restore() -> void:
	if _pg == null:
		stub_calls.append("restore")
		_later(owned.emit.bind([]))
		return
	_pg.call("query_purchases")

## Fallback: consume (and acknowledge) a purchase from the game. The server normally does it. -> consumed | failed.
func consume(token: String) -> void:
	if _pg == null:
		_stub_fail("consume", "consume")
		return
	_pg.call("consume", token)


# ---------- the pending-verification list (Save.prefs.iap_pending) ----------

## Remembers a purchase until the server has verified it: [{product_id, token, at}], at most MAX_PENDING (the oldest
## goes first), one per token (adding it again changes nothing). `p` is the `purchased` dictionary.
func add_pending(p: Dictionary) -> void:
	var token := str(p.get("token", ""))
	if token.is_empty():
		return
	var list := _list()
	for e in list:
		if str(e.token) == token:
			return
	list.append({product_id = str(p.get("product_id", "")), token = token, at = int(Time.get_unix_time_from_system())})
	while list.size() > MAX_PENDING:
		list.pop_front()
	_persist()

## Drops a verified (or rejected) purchase.
func remove_pending(token: String) -> void:
	var list := _list()
	for i in range(list.size() - 1, -1, -1):
		if str(list[i].token) == token:
			list.remove_at(i)
	_persist()

## A copy of the list: [{product_id, token, at}].
func pending_list() -> Array:
	return _list().duplicate(true)

func _list() -> Array:
	_defaults()
	var raw: Variant = prefs.get("iap_pending")
	var clean: Array = []
	if raw is Array:
		for e in raw:
			if e is Dictionary and str(e.get("token", "")) != "":
				clean.append({product_id = str(e.get("product_id", "")), token = str(e.token), at = int(e.get("at", 0))})
	if not (raw is Array) or clean.size() != raw.size():
		prefs.iap_pending = clean              # a missing or damaged entry is repaired
		return clean
	return raw

func _persist() -> void:
	if persist.is_valid():
		persist.call()

func _defaults() -> void:
	if _defaults_done:
		return
	_defaults_done = true
	var save := _save_node() if use_save else null
	if save and save.get("prefs") is Dictionary:
		prefs = save.get("prefs")
	if not persist.is_valid() and save and save.has_method("save"):
		persist = Callable(save, "save")

static func _save_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("Save") if tree and tree.root else null


# ---------- plugin signals ----------

func _on_products(list: Array) -> void:
	var out: Array = []
	for e in list:
		if e is Dictionary:
			out.append({id = str(e.get("id", "")), title = str(e.get("title", "")),
				description = str(e.get("description", "")), price = str(e.get("price", "")),
				price_micros = int(e.get("price_micros", 0)), currency = str(e.get("currency", ""))})
	products.emit(out)

func _on_purchased(p: Dictionary) -> void:
	purchased.emit(_purchase(p))

func _on_owned(list: Array) -> void:
	var out: Array = []
	for e in list:
		if e is Dictionary:
			out.append(_purchase(e))
	owned.emit(out)

func _purchase(p: Dictionary) -> Dictionary:
	return {product_id = str(p.get("product_id", "")), token = str(p.get("token", "")),
		order_id = str(p.get("order_id", "")), state = str(p.get("state", "purchased")),
		account_id = str(p.get("account_id", ""))}


# ---------- helpers ----------

func _stub_fail(call_name: String, where: String) -> void:
	stub_calls.append(call_name)
	_later(failed.emit.bind(where, UNAVAILABLE, "unavailable"))

func _connect(sig: String, fn: Callable) -> void:
	if _pg.has_signal(sig):
		_pg.connect(sig, fn, CONNECT_DEFERRED if _deferred else 0)
	else:
		push_warning("Billing: plugin has no signal %s" % sig)

func _later(fn: Callable) -> void:
	if _deferred:
		fn.call_deferred()
	else:
		fn.call()
