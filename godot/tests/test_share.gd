extends "res://tests/test_suite.gd"
## Sharing (res://scripts/net/share.gd): the texts that go with the win card and the lobby invite, the phone's share sheet
## when the plugin has one (a fake singleton with its `share(text, image_path)`), and the fallback to the clipboard
## (desktop, an older plugin build without `share`, a share sheet that could not open). The result screen's Share button:
## who gets it, and what it sends. The card itself (win_card.gd) is checked by eye: dev/share_shots.tscn.

## Stands in for the Kotlin NotificationsPlugin singleton.
class FakePlugin extends RefCounted:
	var calls: Array = []
	var ok := true
	func share(text: String, image_path: String) -> bool:
		calls.append([text, image_path])
		return ok

## A plugin build from before share(): other methods only.
class OldPlugin extends RefCounted:
	func schedule(_id: String) -> void:
		pass

const URL := "https://play.google.com/store/apps/details?id=com.flipfold.ludozing"


func run() -> void:
	Share.plugin = null
	# ---- the texts ----
	check("win text: coins", Share.win_text(228, "ludo") == "I just won 228 coins in Ludo Zing! Play with me: " + URL, Share.win_text(228, "ludo"))
	check("win text: thousands get commas", Share.win_text(1190, "sl").begins_with("I just won 1,190 coins in Ludo Zing!"))
	check("win text: a free game names the game", Share.win_text(0, "sl") == "I just won a game of Snakes & Ladders in Ludo Zing! Play with me: " + URL, Share.win_text(0, "sl"))
	check("win text: a podium place", Share.win_text(90, "ludo", 2).begins_with("I came 2nd and won 90 coins in Ludo Zing!"), Share.win_text(90, "ludo", 2))
	var inv := Share.invite_text("K7QX2M")
	check("invite: the room line and the store link", inv.begins_with(LobbySheet.invite_text("K7QX2M")) and inv.ends_with(URL), inv)
	check("invite: a friend can still paste it into Friends", FriendsSheet.code_from_text(inv) == "K7QX2M", FriendsSheet.code_from_text(inv))
	check("the store link is the app's package", Share.PLAY_URL.ends_with("id=com.flipfold.ludozing"))

	# ---- the share sheet or the clipboard ----
	check("desktop: no share sheet", not Share.available())
	check("desktop: send falls back to a copy", Share.send(null, "hello", "") == "copied")
	var fake := FakePlugin.new()
	Share.plugin = fake
	check("a plugin with share: available", Share.available())
	var how := Share.send(null, "hello", "/tmp/x.png")
	check("send: the share sheet gets the text and the picture", how == "shared" and fake.calls == [["hello", "/tmp/x.png"]], [how, fake.calls])
	fake.ok = false
	check("send: a sheet that could not open falls back to a copy", Share.send(null, "hello2") == "copied" and fake.calls.size() == 2)
	Share.plugin = OldPlugin.new()
	check("an older plugin (no share): not available, copy", not Share.available() and Share.send(null, "hello3") == "copied")

	# ---- the result screen's Share button ----
	Share.plugin = null
	var you := {color = 0, name = "You", kind = "you", place = 1, finished = true, progress = 1.0}
	var cpu := func(c: int, p: int) -> Dictionary: return {color = c, name = Palette.NAMES[c], kind = "cpu", place = p, finished = p == 1, progress = 0.4}
	var win := ResultScreen.new({game = "ludo", human_won = true, reward = 228, standings = [you, cpu.call(1, 2)]})
	check("share button: a win has one", win.share_button != null and win.can_share())
	var data := win.card_data()
	check("card data: place, title, coins, game", data.place == 1 and data.title == "You win!" and data.coins == 228 and data.game == "ludo", data)
	win.free()
	var free_win := ResultScreen.new({game = "sl", human_won = true, reward = 0, standings = [you, cpu.call(1, 2)]})
	check("share button: a win without coins has one", free_win.share_button != null and free_win.card_data().coins == 0 and free_win.card_data().game == "sl")
	free_win.free()
	var lost := ResultScreen.new({game = "ludo", human_won = false, reward = 0, standings = [cpu.call(1, 1), you.merged({place = 2}, true)]})
	check("share button: a loss in a 2-player game has none", lost.share_button == null and not lost.can_share())
	lost.free()
	var four := func(my_place: int, reward: int) -> ResultScreen:
		var st: Array = [you.merged({place = my_place}, true)]
		var others := [1, 2, 3, 4].filter(func(p): return p != my_place)
		for i in 3:
			st.append(cpu.call(i + 1, others[i]))
		return ResultScreen.new({game = "ludo", human_won = false, reward = reward, standings = st})
	var second: ResultScreen = four.call(2, 90)
	check("share button: 2nd of 4 with coins has one (a podium)", second.share_button != null)
	check("card data: a podium keeps its place", second.card_data().place == 2 and second.card_data().coins == 90, second.card_data())
	second.free()
	var second_free: ResultScreen = four.call(2, 0)
	check("share button: 2nd of 4 without coins has none", second_free.share_button == null)
	second_free.free()
	var third: ResultScreen = four.call(3, 30)
	check("share button: 3rd place has none", third.share_button == null)
	third.free()
	var pp := ResultScreen.new({game = "ludo", human_won = false, standings = [cpu.call(0, 1).merged({kind = "human"}, true), cpu.call(2, 2).merged({kind = "human"}, true)]})
	check("share button: Pass & Play (no 'you') has none", pp.share_button == null)
	pp.free()

	# pressing it: the card can't be drawn headless, so the text goes out alone
	var fake2 := FakePlugin.new()
	Share.plugin = fake2
	var r := ResultScreen.new({game = "ludo", human_won = true, reward = 228, standings = [you, cpu.call(1, 2)]})
	await r.share()
	check("share: the text with the coins goes to the sheet", fake2.calls.size() == 1 and (fake2.calls[0][0] as String).begins_with("I just won 228 coins in Ludo Zing!"), fake2.calls)
	check("share: the button is back for another go", not r.share_button.disabled)
	r._extra = 228
	await r.share()
	check("share: a doubled prize counts the extra coins", fake2.calls.size() == 2 and (fake2.calls[1][0] as String).begins_with("I just won 456 coins"), fake2.calls)
	r.free()
	Share.plugin = null

	# ---- the lobby's Share button ----
	var lobby := LobbySheet.new("K7QX2M", "m1")
	var fake3 := FakePlugin.new()
	Share.plugin = fake3
	lobby.share()
	check("lobby: Share opens the sheet with the invite, text only", fake3.calls == [[Share.invite_text("K7QX2M"), ""]], fake3.calls)
	Share.plugin = null
	check("lobby: without a sheet the invite is copied", lobby.share() == "copied")
	lobby.free()
