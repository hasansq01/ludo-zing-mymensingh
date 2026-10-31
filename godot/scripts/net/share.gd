class_name Share
extends RefCounted
## The phone's share sheet, with today's copy-to-clipboard as the way out. The win card and the lobby invite go
## through here:
##
##   var how := Share.send(self, Share.win_text(228, "ludo"), path_of_a_png)   # "shared" | "copied"
##
## Android with the notifications plugin (its `share(text, image_path)`, godot/android/plugins/notifications/Share.kt)
## opens the system chooser. Everywhere else (desktop, headless, the non-Gradle "Android Emulator" preset, an older
## plugin build without `share`) the text goes to the clipboard and a toast says so, as the lobby always did.
## `send` answers "shared" when the chooser was asked for (the player may still cancel it) and "copied" otherwise.

const PLAY_URL := "https://play.google.com/store/apps/details?id=com.flipfold.ludozing"
const SINGLETON := "NotificationsPlugin"
const COPIED := "Copied. Paste it in a chat."
const GAMES := {ludo = "Ludo", sl = "Snakes & Ladders"}

## Tests: a fake with a `share(text, image_path)` method stands in for the plugin singleton.
static var plugin: Object = null

## The plugin object when it can share (a build that has `share`), else null.
static func native() -> Object:
	var p := plugin
	if p == null and Engine.has_singleton(SINGLETON):
		p = Engine.get_singleton(SINGLETON)
	if p == null:
		return null
	# a JNISingleton (the real plugin) answers has_java_method; a fake or a script object has the method itself
	var can := p.has_method("share") or (p.has_method("has_java_method") and bool(p.call("has_java_method", "share")))
	return p if can else null

static func available() -> bool:
	return native() != null

## "Ludo" / "Snakes & Ladders" for a game id.
static func game_name(game: String) -> String:
	return str(GAMES.get(game, GAMES.ludo))

## What goes with the win card: "I just won 228 coins in Ludo Zing! Play with me: <link>". A podium finish says its
## place ("I came 2nd and won 90 coins ..."), a free game has no coins ("I just won a game of Ludo in Ludo Zing!").
static func win_text(coins: int, game: String, place := 1) -> String:
	var what := ""
	if place > 1:
		what = TranslationServer.translate("I came %s and won %s coins in Ludo Zing!") % [ResultScreen.ordinal(place), Fmt.coins_full(coins)]
	elif coins > 0:
		what = TranslationServer.translate("I just won %s coins in Ludo Zing!") % Fmt.coins_full(coins)
	else:
		what = TranslationServer.translate("I just won a game of %s in Ludo Zing!") % game_name(game)
	return "%s %s %s" % [what, TranslationServer.translate("Play with me:"), PLAY_URL]

## The lobby invite: the room line (LobbySheet.invite_text, which a friend can paste into Friends) and the store link,
## on one line so the pasted text still gives the code (FriendsSheet.code_from_text).
static func invite_text(code: String) -> String:
	return "%s. %s %s" % [LobbySheet.invite_text(code), TranslationServer.translate("Get the game:"), PLAY_URL]

## Opens the share sheet with `text` (and the PNG at `image_path`, an absolute path such as
## ProjectSettings.globalize_path("user://x.png"); "" = text only). Without a share sheet: the text to the clipboard
## and `host` shows a toast. Returns "shared" | "copied".
static func send(host: Node, text: String, image_path := "") -> String:
	var p := native()
	if p != null and bool(p.call("share", text, image_path)):
		return "shared"
	DisplayServer.clipboard_set(text)
	Toast.show(host, TranslationServer.translate(COPIED), null, 2.0, "info")
	return "copied"
