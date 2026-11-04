class_name UpdateSheet
extends Sheet
## The update sheets (AppUpdate, server/PROTOCOL.md "App versions"), one look for both:
## - "Update required" (required = true): the blocking screen that stands in for online play (quick match, friend
##   rooms, joining by invite) when this version is below the server's minimum (AppUpdate.gate). Its Update button runs
##   Play's immediate update (the store page where Play can't); the X goes back to Home, where Vs Computer and Pass &
##   Play still work, and the line says so.
## - "New version available" (required = false): the soft offer on a quiet Home. Update runs Play's full-screen
##   update (AppUpdate.accept_offer; the store page where Play can't); Later puts that version off for two days
##   (decline_offer), and so does closing it (the X, Back: AppUpdate's `closed` hook).
##
##   UpdateSheet.new(app_update).open(layer)           # required
##   UpdateSheet.new(app_update, false).open(layer)    # the offer

var update_button: Button
var later_button: Button                 ## the offer only
var note_label: Label
var required := true
var _u: AppUpdate


func _init(u: AppUpdate = null, required_ := true) -> void:
	_u = u
	required = required_
	super(L10n.t("Update required") if required else L10n.t("New version available"), UIKit.W.form, true, Sheet.LOOK_PM)
	dismissable = true
	set_kicker(tr("Online play") if required else tr("Update"))
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	var intro := UIKit.paragraph(tr("This version of Ludo Zing is too old to play online. Update to play with friends and in quick match.")
		if required else tr("Get the latest fixes and features. It only takes a minute, and the game opens again by itself."),
		UIKit.FS.body, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER)
	intro.name = "Intro"
	body.add_child(intro)
	update_button = UIKit.btn(tr("Update"), "honey", "lg")
	update_button.name = "Update"
	UIKit.fit_text(update_button, 14)
	update_button.pressed.connect(func() -> void:
		if _u == null:
			return
		if required:
			_u.update_now()
		else:
			_u.accept_offer())                   # (it closes this sheet as the state moves on)
	body.add_child(update_button)
	if required:
		note_label = UIKit.paragraph(tr("Playing against the computer or passing the phone around still works."), UIKit.FS.small,
			Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
		note_label.name = "Note"
		body.add_child(note_label)
	else:
		later_button = UIKit.btn(tr("Later"), "ghost", "md")
		later_button.name = "Later"
		later_button.pressed.connect(func() -> void:
			if _u != null:
				_u.decline_offer()               # at once (the X / Back: AppUpdate's `closed` hook, after the fade)
			close())
		body.add_child(later_button)
	fit()
