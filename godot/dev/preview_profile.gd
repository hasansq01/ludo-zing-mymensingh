extends Control
## Dev preview: the Player Profile over a warm background, a few scripted actions, a screenshot, quit.
## Never writes the save: the flush timer is unhooked, Collection / Catalog writes go to a no-op writer, the real
## save file is backed up first and put back at the end, Save.profile is restored before quitting.
##   godot --path . --resolution 390x844 res://dev/preview_profile.tscn -- [new|claimable] [ach] [claim] [copy]
##       [edit] [bad] [scroll] [customise] [narrow] [out_dir]
##   new: a fresh profile; claimable: two achievements ready to claim; ach: the Achievements tab; claim: claim the
##   first claimable one (mid-flight shot + landed shot); edit: type
##   a new name (Save shows); bad: type spaces (error); scroll: scroll the pane to the end; customise: open the Shop.

const OUT := "/private/tmp/claude-501/-Users-shihabshaharia-Coding-ludo-zing-mymensingh/d8feebe6-eee1-4f48-a116-aa2f313481c9/scratchpad/agent_profile"

var _file_backup := ""
var _had_file := false
var _profile_backup: Dictionary
var _out := OUT
var _tag := ""


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(_finish)   # never hang on a script error
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	var bg := ColorRect.new()
	bg.color = Palette.PLUM_NIGHT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var layer := Control.new()
	layer.name = "Layer"
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)

	_had_file = FileAccess.file_exists("user://save.json")
	if _had_file:
		_file_backup = FileAccess.get_file_as_string("user://save.json")
	if Save._timer.timeout.is_connected(Save.flush):
		Save._timer.timeout.disconnect(Save.flush)
	_profile_backup = Save.profile.duplicate(true)
	var nowrite := func(_p: Dictionary) -> bool:
		Save.changed.emit()
		return true
	Collection.writer = nowrite
	Catalog.writer = nowrite

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("/"):
			_out = a
	DirAccess.make_dir_recursive_absolute(_out)
	if args.has("narrow"):
		get_tree().root.content_scale_size = Vector2i(320, 844)
		await get_tree().process_frame
		_tag += "_narrow"
	var p := Save.profile
	p.name = "Shihab"; p.coins = 10500; p.xp = 520
	p.stats = {played = 12, wins = 7, losses = 5, streak = 1, bestStreak = 3, coinsEarned = 6400, pairsFormed = 10, ppGames = 2, slPlayed = 3, slWins = 1}
	p.claimed = ["first"]; p.av_owned = ["ch-rafi"]; p.avatar = "ch-nadia"; p.frame = "mint"; p.plate = "ruby"; p.badge = "streak"
	if args.has("new"):
		p.name = "You"; p.coins = 5000; p.xp = 0
		for k in p.stats: p.stats[k] = 0
		p.claimed = []; p.av_owned = []; p.avatar = "pawn-red"; p.frame = "classic"; p.plate = "plain"; p.badge = ""
		_tag += "_new"
	if args.has("claimable"):
		p.claimed = []          # first + streak done, not claimed
		_tag += "_claimable"

	var sheet := ProfileSheet.new()
	sheet.profile_changed.connect(func(): print("profile_changed"))
	sheet.open(layer)
	await _sleep(0.8)
	if args.has("ach"):
		sheet._tabs.tap("ach")
		await _sleep(0.4)
		_tag += "_ach"
	if args.has("edit"):
		sheet._name_edit.text = "Mina Rahman"
		sheet._name_edit.text_changed.emit(sheet._name_edit.text)
		print("save visible: ", sheet._save_btn.visible, " disabled: ", sheet._save_btn.disabled)
		_tag += "_edit"
		await _sleep(0.2)
	if args.has("bad"):
		sheet._name_edit.text = "   "
		sheet._name_edit.text_changed.emit(sheet._name_edit.text)
		print("save visible: ", sheet._save_btn.visible, " disabled: ", sheet._save_btn.disabled)
		_tag += "_bad"
		await _sleep(0.2)
	if args.has("scroll"):
		await get_tree().process_frame
		sheet.scroll_box.scroll_vertical = 100000
		await _sleep(0.3)
		_tag += "_scroll"
	if args.has("claim"):
		var before := int(p.coins)
		for a: Dictionary in Collection.ACH:
			var pr := Collection.ach_progress(a.id)
			if pr.done and not pr.claimed:
				sheet._claim(a.id)
				break
		print("claimed: coins ", before, " -> ", p.coins, " claimed=", p.claimed, " earned=", p.stats.coinsEarned)
		await _sleep(0.45)
		await _shot("_claim_flying")
		await _sleep(1.4)
		_tag += "_claimed"
	if args.has("customise"):
		sheet._customise()
		await _sleep(1.0)
		_tag += "_customise"
	await _shot("")
	_finish()

func _sleep(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _shot(extra: String) -> void:
	await RenderingServer.frame_post_draw
	var vs := get_viewport_rect().size
	var path := "%s/profile%s%s_%dx%d.png" % [_out, _tag, extra, int(vs.x), int(vs.y)]
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _finish() -> void:
	Save.profile.clear()
	Save.profile.merge(_profile_backup)
	Save._dirty = false
	Collection.writer = Callable()
	Catalog.writer = Callable()
	if _had_file:
		var f := FileAccess.open("user://save.json", FileAccess.WRITE)
		if f:
			f.store_string(_file_backup)
			f.close()
	get_tree().quit()
