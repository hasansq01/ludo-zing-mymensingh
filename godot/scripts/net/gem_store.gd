class_name GemStore
extends Node
## The gem packs' payment flow (server/ECONOMY_V1.md sections 2 and 6): Google Play Billing on one side, POST
## /v1/iap/verify on the other. Main owns one for the whole run (so a payment that is still unverified is retried at the
## next launch), the Store sheet reads it.
##
##   buy(product_id)  -> Play's sheet -> purchased(p) -> Billing.add_pending(p) FIRST -> iap_verify -> remove_pending
##                       after ok / duplicate / invalid -> granted(gems, product_id) ("+80 gems")
##   Left in the list (retried at launch and when the Store opens): 409 pending (not paid yet), 503 unavailable,
##   offline. `payment_pending` is true while any purchase waits ("Payment pending..." in the Store).
##   launch_check() / check(): verify Billing.pending_list(), then Billing.restore() and verify what Play still holds.
##
## Tests pass a Billing built on a fake plugin (use_save = false, its own prefs) and an Account on the fake server.

## A purchase was verified and its gems added (never emitted for `duplicate`: those gems were shown before).
signal granted(gems: int, product_id: String)
## The server refused a purchase for good (409 invalid): it was dropped from the list.
signal rejected(product_id: String)
## Something changed that the Store shows: products, the pending list, a purchase in flight.
signal changed

static var _inst: GemStore = null

var billing: Billing
var products: Array = []                 ## Billing.query answer: [{id, title, description, price, price_micros, currency}]
var buying := false                      ## Play's purchase sheet is open
var last_error := ""                     ## the last Billing failure ("" none), for a "try again" line
var verifying := 0                       ## verifies in flight
var _acc: Account = null
var _tokens := {}                        # tokens being verified now (a token never goes twice at once)
var _owns_billing := false
var _started := false


func _init(billing_: Billing = null, acc: Account = null) -> void:
	billing = billing_
	_acc = acc

func _enter_tree() -> void:
	_inst = self

func _exit_tree() -> void:
	if _inst == self:
		_inst = null

## The GemStore of this run (main owns it), or null.
static func instance() -> GemStore:
	return _inst if is_instance_valid(_inst) else null

## Tests: make this the current one (null clears it).
static func set_instance(g: GemStore) -> void:
	_inst = g

func _ready() -> void:
	if billing == null:
		billing = Billing.new()
		_owns_billing = true
		add_child(billing)
	billing.products.connect(_on_products)
	billing.purchased.connect(_on_purchased)
	billing.pending.connect(_on_pending)
	billing.canceled.connect(_on_canceled)
	billing.owned.connect(_on_owned)
	billing.failed.connect(_on_failed)
	billing.connected.connect(_on_connected)

func account() -> Account:
	return _acc if _acc != null else Account.instance()

## True on Android with Play Billing built in (the Store shows the packs only then).
func available() -> bool:
	return billing != null and billing.available()

## True while a payment is waiting to be verified or Play still processes one.
func payment_pending() -> bool:
	return billing != null and not billing.pending_list().is_empty()

## "gems_80" -> 80 (the id says how many gems the pack gives); 0 for an unknown id.
static func gems_of(product_id: String) -> int:
	return int(product_id.get_slice("_", 1)) if product_id.begins_with("gems_") else 0

## The product dictionary of an id (from query()), or {}.
func product(id: String) -> Dictionary:
	for p: Dictionary in products:
		if str(p.id) == id:
			return p
	return {}


# ---------- launch / opening the Store ----------

## Launch: connect to Play (restore runs once it is connected) and verify what an earlier run left unverified.
func launch_check() -> void:
	if not _started:
		_started = true
		billing.start()
	await verify_pending()

## The Store opened: prices, the pending list, and what Play still holds.
func check() -> void:
	if not _started:
		_started = true
		billing.start()
	if products.is_empty():
		billing.query()
	billing.restore()                        # -> owned -> verified in _on_owned
	await verify_pending()

## Verifies every entry of Billing.pending_list(), one after the other. How many were granted.
func verify_pending() -> int:
	var n := 0
	for e: Dictionary in billing.pending_list():
		var r: Dictionary = await verify(e)
		if r.get("ok", false) and not r.get("duplicate", false):
			n += 1
	return n

## Starts a purchase (Play's sheet). The rest goes through purchased / pending / canceled / failed.
func buy(product_id: String) -> void:
	if buying or not available():
		return
	var acc := account()
	buying = true
	last_error = ""
	changed.emit()
	billing.buy(product_id, str(acc.account.get("id", "")) if acc else "")

## Sends one purchase ({product_id, token}) to the server. {ok, gems, duplicate?, error, keep}: `keep` is true when
## the purchase stays in the pending list (not paid yet, Play unavailable, offline).
func verify(p: Dictionary) -> Dictionary:
	var token := str(p.get("token", ""))
	var acc := account()
	if token == "" or acc == null:
		return {ok = false, error = "offline", keep = true}
	if _tokens.has(token):
		return {ok = false, error = "busy", keep = true}
	_tokens[token] = true
	verifying += 1
	changed.emit()
	var r: Dictionary = await acc.iap_verify(str(p.get("product_id", "")), token)
	_tokens.erase(token)
	verifying = maxi(0, verifying - 1)
	if not is_instance_valid(self):
		return {ok = false, error = "gone", keep = true}
	var out := {ok = bool(r.get("ok", false)), error = str(r.get("error", "")), keep = true}
	if out.ok:
		out.gems = Account._int(r.get("gems"), gems_of(str(p.get("product_id", ""))))
		out.duplicate = bool(r.get("duplicate", false))
		out.keep = false
		billing.remove_pending(token)
		if not out.duplicate:
			granted.emit(int(out.gems), str(p.get("product_id", "")))
	elif out.error == "invalid":
		out.keep = false
		billing.remove_pending(token)
		rejected.emit(str(p.get("product_id", "")))
	changed.emit()
	return out


# ---------- Billing's answers ----------

func _on_products(list: Array) -> void:
	# the packs in the order of PRODUCT_IDS (cheapest first), whatever order Play answers in
	var ordered: Array = []
	for id in Billing.PRODUCT_IDS:
		for p: Dictionary in list:
			if str(p.id) == id:
				ordered.append(p)
	products = ordered
	changed.emit()

func _on_purchased(p: Dictionary) -> void:
	buying = false
	billing.add_pending(p)                   # BEFORE the server call: a crash now still finds it at the next launch
	changed.emit()
	verify(p)

func _on_pending(_product_id: String) -> void:
	buying = false                           # a slow payment method: the token arrives later, as owned()
	changed.emit()

func _on_canceled() -> void:
	buying = false
	changed.emit()

func _on_owned(list: Array) -> void:
	for p: Dictionary in list:
		if str(p.get("state", "purchased")) == "pending":
			continue                         # Play hasn't been paid yet
		billing.add_pending(p)
		verify(p)
	changed.emit()

func _on_failed(where: String, code: int, message: String) -> void:
	buying = false
	last_error = "%s:%d" % [where, code]
	if where == "purchase" and code == 7:    # ITEM_ALREADY_OWNED: a purchase Play still holds: verify it
		billing.restore()
	if code != Billing.UNAVAILABLE and where in ["connect", "query", "purchase"]:
		push_warning("GemStore: %s failed (%d) %s" % [where, code, message])
	changed.emit()

func _on_connected() -> void:
	billing.query()
	billing.restore()
