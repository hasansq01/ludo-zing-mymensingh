class_name RerollFlow
extends RefCounted
## The re-roll offer and hold of an online match (server/ECONOMY_V1.md section 4), as pure state shared by LudoMatch and
## SLMatch (no nodes): after your bad roll the server sends you `reroll_offer {n, until, now, free, gems, cost}` and
## everyone `hold {c, until}`; the next player's roll waits until the hold ends; `rerolled` / `sync` end it early.
##
## Times: the server's clock is not ours. An offer carries its own `now`, so its length is until - now; a hold has no
## `now`, so it is until - net.server_now() (the clock offset NetClient keeps from `turn`; pass -1 when unknown).
## Both are clamped to 0..MAX_MS so a wrong clock can never freeze a roll. `end` is Time.get_ticks_msec() (local).
##
##   var rr := RerollFlow.new()
##   rr.on_offer(msg); rr.on_hold(msg, net.server_now())
##   rr.offer_open(ns.n)       # the "Roll again" button may show now (the bad roll's act has played)
##   rr.holds(me)              # the next player's dice wait
##   rr.hold_left_ms()

const WINDOW_MS := 3000.0                ## the server's re-roll window (ECON_V1.reroll_window_ms)
const MAX_MS := 4000.0

var offer := {}                          ## {n, end, total, free, gems, cost, sent}
var hold := {}                           ## {c, end}
var clock := Callable()                  ## tests: () -> ms in place of Time.get_ticks_msec()


func now_ms() -> float:
	return float(clock.call()) if clock.is_valid() else float(Time.get_ticks_msec())

## reroll_offer {n, until, now, free, gems, cost}.
func on_offer(msg: Dictionary) -> void:
	var left := clampf(float(msg.get("until", 0)) - float(msg.get("now", 0)), 0.0, MAX_MS)
	offer = {n = int(msg.get("n", -1)), end = now_ms() + left, total = maxf(left, WINDOW_MS), free = int(msg.get("free", 0)),
		gems = int(msg.get("gems", 0)), cost = int(msg.get("cost", 5)), sent = false}

## hold {c, until}: server_now is the server's clock now in ms (-1 / 0: unknown, the whole window is assumed).
func on_hold(msg: Dictionary, server_now := -1.0) -> void:
	var left := WINDOW_MS
	if server_now > 0.0 and msg.has("until"):
		left = clampf(float(msg.until) - server_now, 0.0, MAX_MS)
	hold = {c = int(msg.get("c", -1)), end = now_ms() + left}

func offer_left_ms() -> float:
	return maxf(0.0, float(offer.end) - now_ms()) if not offer.is_empty() else 0.0

func hold_left_ms() -> float:
	return maxf(0.0, float(hold.end) - now_ms()) if not hold.is_empty() else 0.0

## The button may show: an offer for the state at n that is still open and not taken.
func offer_open(n: int) -> bool:
	return not offer.is_empty() and int(offer.n) == n and offer_left_ms() > 0.0 and not bool(offer.sent)

## The next player's roll waits: a hold on someone else's re-roll is still running.
func holds(me: int) -> bool:
	return not hold.is_empty() and int(hold.c) != me and hold_left_ms() > 0.0

func mark_sent() -> void:
	if not offer.is_empty():
		offer.sent = true

func clear_offer() -> void:
	offer = {}

func clear_hold() -> void:
	hold = {}

func clear() -> void:
	offer = {}
	hold = {}

## "Free" while a free re-roll is held, else the gem price.
func is_free() -> bool:
	return not offer.is_empty() and int(offer.free) > 0

## Errors of the re-roll and the held roll, as a short toast ("" = nothing to say).
static func error_text(code: String) -> String:
	match code:
		"reroll_used":
			return L10n.t("You already rolled again this match.")
		"reroll_closed":
			return L10n.t("Too late to roll again.")
		"gems":
			return L10n.t("Not enough gems to roll again.")
	return L10n.t("")

## The codes the re-roll and the hold answer with.
static func is_error(code: String) -> bool:
	return code in ["reroll_used", "reroll_closed", "gems", "hold"]
