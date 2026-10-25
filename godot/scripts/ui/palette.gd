class_name Palette
extends RefCounted
## Colours: player colours (index.html COLORS) and the design tokens of index.html :root plus the web component
## styles (.pm, .pm-btn, .x-btn, .seg, .toast, .gtabs ...). This is the ONLY file with Color("#...") literals for
## the interface (art files excepted: brand_logo, splash, dice_3d skins, world/*).
##
## Naming: a role, not a hue (INK, MUTED, CARD, HONEY_LIP ...). Pairs are [face, lip/deep]. The phase-0 aliases are
## gone except CREAM (marked "alias": dev previews still use it).

# ---------- players ----------
const PLAYER := [Color("#e5484d"), Color("#2fa86b"), Color("#f4c430"), Color("#3b7be0")]       ## red, green, yellow, blue
const PLAYER_DARK := [Color("#b8282d"), Color("#1f8a52"), Color("#c99a12"), Color("#2a63bf")]
const TINT := [Color("#f9d4d2"), Color("#cdebd9"), Color("#fbedbd"), Color("#cfdcf6")]
const NAMES := ["Red", "Green", "Yellow", "Blue"]
## Colour-blind symbol per colour index (assets/ui/sym_<name>.svg): red circle, green square, yellow triangle,
## blue diamond. UIKit.symbol(c) loads the texture.
const SYMBOL := ["circle", "square", "triangle", "diamond"]

# ---------- text ----------
const INK := Color("#4a2b3d")          ## --ink: all primary text, icon strokes
const INK_DEEP := Color("#563044")     ## tab labels, icon fills (web tab icons)
const INK_STRONG := Color("#3a1830")   ## bold names inside status text
const MUTED := Color("#8c6b78")        ## --muted: secondary text (the one muted grey)
const SUB := Color("#8a6a5c")          ## warm secondary on cream rows (.pane-note, settings notes)
const CREMA := Color("#a0717f")        ## --crema: small-caps captions and kickers
const RUST := Color("#9a4a2e")         ## warm heading accent (profile id, achievement titles)
const ON_HONEY := Color("#4a2a00")     ## --on-accent: text and icons on honey / gold
const DANGER := Color("#d64545")       ## error text, destructive labels

# ---------- surfaces ----------
const CARD := Color("#fffaf4")         ## --card: sheets, dialogs, cards
const CREAM := CARD                    ## alias (was #fffaf3); still used by dev/preview_ui.gd, dev/splash_preview.gd
const SURFACE_2 := Color("#fff3e8")    ## --surface-2: raised tiles inside cards
const GLASS := Color(1.0, 0.98, 0.957, 0.9)          ## --panel: glassy chips over the 3D room
const GLASS_PRESSED := Color(0.96, 0.92, 0.88, 0.95)
const NIGHT_GLASS := Color(0.17, 0.09, 0.15, 0.62)   ## dark glass chips on the lobby
const ROW := Color("#fdf0d4")          ## cream row cards (settings, profile, how-to)
const ROW_EDGE := Color("#f3dcb8")
const PANE := Color("#fdf5e8")         ## .pm-inner pane
const PANE_EDGE := Color("#dc9f6c")
const PM := Color("#f8e8cf")           ## .pm modal card face
const PM_RIM := Color("#fff9f0")       ## .pm inner white rim
const PM_RING := Color("#d98f56")      ## .pm orange outer ring
const CHIP := Color("#f4e6dc")         ## --chip: segmented track, disabled buttons, wells
const CHIP_DIM := Color("#f1e3d6")     ## empty / claimed wells
const TAB := Color("#ede0d2")          ## .gtabs inactive tab and baseline
const TAB_HOVER := Color("#e6d6c5")
const TRACK := Color("#efdfd5")        ## --track: progress tracks, slider tracks
const LINE := Color(0.478, 0.282, 0.376, 0.14)         ## --line: hairlines
const LINE_STRONG := Color(0.478, 0.282, 0.376, 0.26)  ## --line-strong
const LINE_SOLID := Color("#ead3bf")   ## opaque hairline (was Palette.LINE)
const LIP_CREAM := Color("#e4cdb8")    ## lip under white / cream buttons
const TAN := Color("#e2b896")          ## warm tan edges
const TAN_DEEP := Color("#c7a98a")     ## switch off, claimed tile lip

# ---------- honey / gold ----------
const HONEY := Color("#ffc94a")        ## .pm-btn.honey: primary buttons, sliders, focus
const HONEY_LIP := Color("#e39a1d")    ## .pm-btn.honey inset lip
const HONEY_RIM := Color("#fff3d6")    ## .pm-btn.honey 2 px border
const HONEY_TINT := Color("#ffe3a8")   ## honey-tinted chips (balance chip, selected chip)
const HONEY_TINT_EDGE := Color("#f3cf8e")
const GOLD := Color("#f7a928")         ## --gold: equipped rings, gold tags
const GOLD_HI := Color("#ffd45e")      ## --gold-hi: close-button rim, highlights
const GOLD_DEEP := Color("#d9800d")    ## --gold-deep
const GOLD_FILL := Color("#ffc93c")    ## XP bar fill (the old GOLD)
const GOLD_RING := Color("#e8901c")    ## .x-btn outer ring
const SILVER := Color("#c3ccd8")       ## 2nd-place badge face (1st is GOLD)
const BRONZE := Color("#dd9c62")       ## 3rd-place badge face

# ---------- teal ----------
const TEAL := Color("#2fb39c")         ## .pm-btn.teal: secondary positive, Pass & Play identity
const TEAL_LIP := Color("#1d8a78")
const TEAL_INK := Color("#1f9483")     ## success text on cream
const TEAL_OUTLINE := Color("#1a6e5e") ## outline of white text on teal
const TEAL_SOFT := Color("#4fcab8")    ## --teal: progress fills
const TEAL_GLOW := Color("#9ff0dc")

# ---------- red ----------
const RED := Color("#ef5350")          ## destructive buttons, notification badge
const RED_PRESSED := Color("#d8403d")
const RED_DEEP := Color("#b8282d")     ## red button lip
const RED_OUTLINE := Color("#8f1c20")
const X_HI := Color("#ff8f80")         ## .x-btn radial gradient: highlight, middle, edge
const X_MID := Color("#f2453c")
const X_EDGE := Color("#c41d27")
const X_LIP := Color("#9e1520")        ## .x-btn lip

# ---------- accents (web :root) ----------
const PEACH := Color("#ffb98a")
const CORAL := Color("#ff7f7a")        ## active lobby tab, web .badge
const LAVENDER := Color("#b49cff")
const SKY := Color("#7cc4ff")
const PINK := Color("#ff9ec7")
const PLUM_NIGHT := Color("#24163a")
const INFO := Color("#7b5cc4")         ## the info (i) disc
const INFO_DEEP := Color("#5a3f99")
const RIBBON := Color("#f47a52")       ## .pm-title ribbon
const RIBBON_LIP := Color("#cf5532")
const RIBBON_RIM := Color("#fff4e6")
const RIBBON_SHADOW := Color(0.59, 0.2, 0.1, 0.5)

## Lobby tile colour pairs [face, lip].
const LOBBY := {
	spin = [Color("#8f6cf0"), Color("#6a47c9")],
	gift = [Color("#ff9aa8"), Color("#e0607a")],
	coins = [HONEY, Color("#e09a14")],
	tab_on = [Color("#ff8f5a"), Color("#d9663a")],
}
## Category colours for .gtabs tabs and tags [tc, tc2] (index.html --tc / --tc2).
const CAT := {
	rooms = [Color("#e09478"), Color("#b5624a")],
	chars = [Color("#e09478"), Color("#b5624a")],
	scenes = [Color("#8fb8de"), Color("#5a86b0")],
	dice = [Color("#91b58a"), Color("#5f8a57")],
	emotes = [Color("#d6a3d0"), Color("#a56d9f")],
	coins = [Color("#e7b85f"), Color("#b98a2e")],
	avatars = [Color("#e7b85f"), Color("#b98a2e")],
	frames = [Color("#e3a3b4"), Color("#b86e84")],
	plates = [Color("#b9aedb"), Color("#8676b4")],
	badges = [Color("#93c2b6"), Color("#5e9488")],
}

# ---------- depth ----------
const SHADOW := Color(0.43, 0.24, 0.35)          ## rgb(110,60,90): --shadow-sm / --shadow / --press colour
const SHADOW_DEEP := Color(0.196, 0.098, 0.157)  ## rgb(50,25,40): .pm drop shadow
const SCRIM := Color(0.29, 0.17, 0.24, 0.5)      ## dim behind sheets (.ppage)
const TOAST := Color(0.29, 0.17, 0.24, 0.94)     ## .toast background
const HALO := Color(0.17, 0.09, 0.15, 0.75)      ## outline of white text over the 3D room
const VEIL := Color(0.13, 0.07, 0.16, 0.62)
const GLOW_GOLD := Color(0.97, 0.66, 0.16, 0.25) ## equipped-card glow
const GLOSS := Color(1, 1, 1, 0.35)              ## white highlight on glossy faces
## Disabled button faces are lerped toward these (UIKit.style_button).
const DISABLED_FACE := Color("#d9cfc6")
const DISABLED_LIP := Color("#bfb3a8")
const DISABLED_TEXT := Color("#9a8f86")

## The web shadow colour (rgb 110,60,90) at alpha `a` (.16 = --shadow-sm, .2 = --shadow, .22 = --press).
static func shadow(a := 0.16) -> Color:
	return Color(SHADOW, a)
