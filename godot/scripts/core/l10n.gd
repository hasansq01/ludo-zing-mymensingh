class_name L10n
extends RefCounted
## The interface language: English (the text written in the scripts) or Bangla (locale/bn.po, registered in
## project.godot). Settings picks Auto / English / বাংলা (Save.prefs.lang "auto" | "en" | "bn"); Auto follows the
## phone: Bangla when its language is bn, else English. main.gd applies it at launch and rebuilds what is on screen
## when it changes (Main.set_language).
##
## Marking text (godot/tools/l10n_sync.gd collects it into locale/bn.po; tests/test_l10n.gd fails when a marked
## string has no Bangla):
##   tr("Play")  tr_n("%d game", "%d games", n)          in methods (any Object has them)
##   L10n.t("Play")  L10n.tn("%d game", "%d games", n)   in static functions
##   tr("Home", "nav")                                   a context (msgctxt) when one English text needs two Banglas
## Translate first, then format: tr("Free coins in %s") % t (never tr("Free coins in %s" % t)). The Bangla keeps
## the placeholders in the same order (GDScript's % has no positional arguments).
## Text that can't be wrapped where it is written (const tables, default arguments) is collected by markers and
## translated where it is shown (tr(item.name), L10n.t(no)):
##   `# l10n` at the end of a line            every string literal on that line
##   `# l10n:begin` ... `# l10n:end`          every string literal between the two lines
##   `## l10n-keys: name, desc` (anywhere)    the literal values of these keys inside { } in that file
##   `# TRANSLATORS: ...` on the line or the line above: a note for the translator, copied into bn.po
## (markers are plain # comments; ## doc comments like these are never read as markers, except l10n-keys)
## Translating twice is harmless (a Bangla text is no msgid), so helpers may translate what callers pass them.
## Never translate what is saved or sent (ids, protocol codes, save values, names): only what is shown. Digits stay
## Latin. "Ludo Zing" stays in Latin letters.

## Save.prefs.lang values, in Settings order.
const LANGS := ["auto", "en", "bn"]
## The interface languages there is text for.
const CODES := ["en", "bn"]
## How each language names itself (the Settings switch shows these whatever the current language).
const NATIVE := {en = "English", bn = "বাংলা"}


## The language the phone asks for, if there is text for it: "bn" or "en".
static func phone() -> String:
	return "bn" if OS.get_locale_language() == "bn" else "en"

## The language a Save.prefs.lang value means: "auto" (or anything unknown) follows the phone.
static func resolve(pref: Variant) -> String:
	var p := str(pref)
	return p if p in CODES else phone()

## Switch the interface to a Save.prefs.lang value; returns the language now in use ("en" | "bn"). Controls with
## a plain msgid as text follow at once; text built with tr() is rebuilt by its owner (Main.set_language).
static func apply(pref: Variant) -> String:
	var code := resolve(pref)
	if TranslationServer.get_locale() != code:
		TranslationServer.set_locale(code)
	return code

## The language in use: "bn" or "en".
static func lang() -> String:
	return "bn" if TranslationServer.get_locale().begins_with("bn") else "en"

static func is_bn() -> bool:
	return lang() == "bn"

## The names the game makes up for seats (match state, saves and the server keep them in English).
const SEAT_NAMES := ["You", "Red", "Green", "Yellow", "Blue", "Player"]  # l10n

## A seat's name as shown: a made-up one ("You", a colour, "Player 2") in the interface language; a player's own
## name or a bot's name as it is.
static func seat_name(n: String) -> String:
	if n in SEAT_NAMES:
		return t(n)
	if n.begins_with("Player ") and n.trim_prefix("Player ").is_valid_int():
		return t("Player %d") % int(n.trim_prefix("Player "))
	return n

## tr() for static functions.
static func t(msg: String, ctx := "") -> String:
	return String(TranslationServer.translate(msg, ctx))

## tr_n() for static functions.
static func tn(msg: String, plural: String, n: int, ctx := "") -> String:
	return String(TranslationServer.translate_plural(msg, plural, n, ctx))
