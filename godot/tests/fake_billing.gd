extends RefCounted
## A stand-in for the Kotlin BillingPlugin singleton (Billing's `singleton` argument): the plugin's method and signal
## names, answers synchronous (build the Billing with deferred = false). `buy_result` picks what purchase() does.

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

const PRICES := {gems_80 = "৳120.00", gems_220 = "৳300.00", gems_500 = "৳600.00", gems_1200 = "৳1,200.00"}

var calls: Array = []
var buy_result := "purchased"            ## purchased | pending | canceled | failed
var owned_list: Array = []               ## what query_purchases() answers
var holds_query := false                 ## true: query_products() never answers (the prices are still loading)
var _n := 0

func start_connection() -> void:
	calls.append("start_connection")
	connected.emit()

func query_products(ids: PackedStringArray) -> void:
	calls.append("query_products")
	if holds_query:
		return
	var list: Array = []
	for id in ids:
		list.append({id = id, title = "%s gems (Ludo Zing)" % id.get_slice("_", 1), description = "", price = PRICES.get(id, "৳1.00"),
			price_micros = 1000000, currency = "BDT"})
	products.emit(list)

func purchase(product_id: String, account_id: String) -> void:
	calls.append("purchase:%s:%s" % [product_id, account_id])
	match buy_result:
		"purchased":
			_n += 1
			purchased.emit({product_id = product_id, token = "tok%d" % _n, order_id = "GPA.%d" % _n, state = "purchased", account_id = account_id})
		"pending":
			pending.emit(product_id)
		"canceled":
			canceled.emit()
		_:
			purchase_failed.emit(6, "error")

func query_purchases() -> void:
	calls.append("query_purchases")
	owned.emit(owned_list.duplicate(true))

func consume(token: String) -> void:
	calls.append("consume:" + token)
	consumed.emit(token)
