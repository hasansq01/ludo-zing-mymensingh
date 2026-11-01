class_name UpdateSheet
extends Sheet
## "Update required": the blocking screen that stands in for online play (quick match, friend rooms, joining by invite)
## when this version is below the server's minimum (AppUpdate.gate, server/PROTOCOL.md "App versions"). Its Update
## button runs Play's immediate update (the store page where Play can't); the X goes back to Home, where Vs Computer and
## Pass & Play still work, and the line says so.
##
##   UpdateSheet.new(app_update).open(layer)

var update_button: Button
var note_label: Label
var _u: AppUpdate


func _init(u: AppUpdate = null) -> void:
	_u = u
	super(L10n.t("Update required"), UIKit.W.form, true, Sheet.LOOK_PM)
	dismissable = true
	set_kicker(tr("Online play"))
	body.add_theme_constant_override("separation", UIKit.SPACE.md)
	var intro := UIKit.paragraph(tr("This version of Ludo Zing is too old to play online. Update to play with friends and in quick match."),
		UIKit.FS.body, Palette.INK, HORIZONTAL_ALIGNMENT_CENTER)
	intro.name = "Intro"
	body.add_child(intro)
	update_button = UIKit.btn(tr("Update"), "honey", "lg")
	update_button.name = "Update"
	UIKit.fit_text(update_button, 14)
	update_button.pressed.connect(func() -> void:
		if _u != null:
			_u.update_now())
	body.add_child(update_button)
	note_label = UIKit.paragraph(tr("Playing against the computer or passing the phone around still works."), UIKit.FS.small,
		Palette.SUB, HORIZONTAL_ALIGNMENT_CENTER)
	note_label.name = "Note"
	body.add_child(note_label)
	fit()
