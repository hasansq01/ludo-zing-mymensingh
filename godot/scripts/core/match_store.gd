class_name MatchStore
extends RefCounted
## The match in progress, kept in user://match.json so a game survives the app being closed or killed ("Continue
## match" on Home). One match at a time: Ludo (LudoMatch saves after every turn) or Snakes & Ladders (SLMatch, by
## game key "sl"). Cleared when the game ends or the player leaves it.
##
##   MatchStore.save("ludo", state, "Ludo vs Computer · 35%")   # state: a JSON-safe Dictionary
##   if MatchStore.has_saved(): var p := MatchStore.peek()      # {game, summary, saved_at}
##   var state := MatchStore.load()                            # {} when there is none (or it is unreadable)
##   MatchStore.clear()            # or clear("ludo"): only if the stored match is a Ludo one
##
## JSON turns every number into a float; load() gives whole numbers back as ints (game states hold ints only), so
## the rules code can use the state as it was saved. The file is replaced atomically (written to .tmp, renamed).

const PATH := "user://match.json"
const VERSION := 1

## Tools and dev previews switch writing off (reads still work).
static var enabled := true
## The file in use (tests point it elsewhere).
static var path := PATH


## Stores `state` for `game` ("ludo" | "sl"); `summary` is a short line for the Continue card.
static func save(game: String, state: Dictionary, summary := "") -> void:
	if not enabled or state.is_empty():
		return
	var data := {v = VERSION, game = game, summary = summary, saved_at = int(Time.get_unix_time_from_system()), state = state}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("MatchStore: can't write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_string(JSON.stringify(data))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))

## A saved match is waiting.
static func has_saved() -> bool:
	return not _read().is_empty()

## What is saved, without the state: {game, summary, saved_at}; {} when nothing is.
static func peek() -> Dictionary:
	var d := _read()
	if d.is_empty():
		return {}
	return {game = str(d.get("game", "")), summary = str(d.get("summary", "")), saved_at = int(d.get("saved_at", 0))}

## The saved state (whole numbers as ints), or {}.
static func load() -> Dictionary:
	var d := _read()
	if d.is_empty():
		return {}
	var st: Variant = ints(d.get("state", {}))
	return st if st is Dictionary else {}

## Which game the saved match is ("" when none).
static func game() -> String:
	return str(_read().get("game", ""))

## Forgets the saved match; with `game` only when the saved one is that game.
static func clear(game_ := "") -> void:
	if not enabled or not FileAccess.file_exists(path):
		return
	if game_ != "" and game() != game_:
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## A deep copy with integral floats turned back into ints (JSON gives every number back as a float).
static func ints(v: Variant) -> Variant:
	match typeof(v):
		TYPE_FLOAT:
			var f: float = v
			return int(f) if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15 else f
		TYPE_ARRAY:
			var out := []
			for x in v:
				out.append(ints(x))
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = ints(v[k])
			return d
	return v

static func _read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var d: Dictionary = parsed
	if not d.get("state") is Dictionary or str(d.get("game", "")) == "":
		return {}
	return d
