extends RefCounted
## Base for the rule test suites: check(name, ok, got) records one result, like the browser tests' check().

var results := []

func check(name: String, ok: bool, got: Variant = null) -> void:
	results.append({name = name, ok = ok, got = "" if ok else JSON.stringify(got)})

func run() -> void:
	pass

const Ludo := preload("res://scripts/core/ludo_rules.gd")
const SL := preload("res://scripts/core/snakes_ladders_rules.gd")

## Colours: 0 red (start abs 0), 1 green (13), 2 yellow (26), 3 blue (39). abs = (start + progress) % 52.
func prog(c: int, abs_sq: int) -> int:
	return (abs_sq - Ludo.OFF[c] + 52) % 52

func base() -> Array:
	return [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]]

## A Ludo state for a test: four humans unless `extra` says otherwise, Individual mode.
func state(tok: Array, pairs: Array = [], extra: Dictionary = {}) -> Dictionary:
	var s := {players = ["human", "human", "human", "human"], names = ["Red", "Green", "Yellow", "Blue"], view = 0,
		tok = tok, pairs = pairs, turn = 0, dice = 0, sixes = 0, phase = "roll", winner = -1, pick = "",
		teams = false, free = [false, false, false, false], pending = {}}
	s.merge(extra, true)
	return s

## One real roll the way the game drives it: a computer picks with pick_ai; a human's only option (or a move
## from base) goes by itself, otherwise `pick` names the token. Like play() in the browser tests.
func play(s: Dictionary, v: int, pick := -1) -> void:
	Ludo.apply_roll(s, v)
	if s.phase != "choose":
		return
	if not Ludo.is_human(s, s.turn):
		Ludo.move(s, Ludo.pick_ai(s, Ludo.movables(s)))
		return
	var a := Ludo.auto_move_token(s)
	if a >= 0:
		Ludo.move(s, a)
	elif pick >= 0:
		Ludo.move(s, pick)
