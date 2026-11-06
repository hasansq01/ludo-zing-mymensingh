extends "res://tests/test_suite.gd"
## Pawn skins (Catalog.PAWNS, PawnSkins, PawnArt): the catalogue and its prices, buying (coins, never twice, nothing
## spent without the coins or when the save fails, gem-only skins refused for coins), equipping, Save's defaults, the
## gem path through the server wallet (the fake server), the Shop's Pawns tab, every skin's 3D build (a modest vertex
## budget, the board's glow / dim / halo / symbol parts kept, skins swapped per colour), the S&L board's skins, who
## wears what offline and online, and the hello / seats fields. Catalog runs on its own profile Dictionaries; the
## wallet part swaps Save for a throwaway profile with its write cut, so user://save.json is never touched.

const Fake := preload("res://tests/fake_accounts.gd")

var writes := 0
var _done := false
var _root: Node

func fresh(coins := 10000) -> Dictionary:
	return {coins = coins, pawns_owned = ["classic"], pawn = "classic", stats = {coinsEarned = 0}}

func use(p: Dictionary, fail := false) -> Dictionary:
	Catalog.profile_source = p
	writes = 0
	Catalog.writer = func(_prof: Dictionary) -> bool:
		writes += 1
		return not fail
	return p

func run() -> void:
	_root = (Engine.get_main_loop() as SceneTree).root
	var keep_src: Variant = Catalog.profile_source
	var keep_writer: Callable = Catalog.writer
	_catalogue()
	_buying()
	Catalog.profile_source = keep_src
	Catalog.writer = keep_writer
	_save_defaults()
	_who_wears_what()
	_skins_3d()
	_flat_art()
	_wallet()
	check("pawns: the suite ran to the end (nothing suspended for real)", _done)


# ---------- catalogue ----------

func _catalogue() -> void:
	var ids: Array = Catalog.PAWNS.map(func(d): return d.id)
	check("Classic first, then the coin skins by price, then the gem-only ones", ids == ["classic", "trim", "candy", "fruity", "blossom", "marble", "ice", "pirate", "robo", "wizard", "kitty", "space", "teacup", "dragon", "glitter", "crown", "knight"], ids)
	check("the skins people may already own are all still sold, at their old prices", Catalog.pawn("trim").price == 2000 and Catalog.pawn("marble").price == 3500 and Catalog.pawn("kitty").price == 5000
		and Catalog.pawn("teacup").price == 6000 and Catalog.pawn("glitter").gems == 80 and Catalog.pawn("crown").gems == 120 and Catalog.pawn("knight").gems == 150)
	check("every themed skin is on sale", PawnSkins.THEMED.all(func(id): return not Catalog.pawn(id).is_empty()))
	check("Classic is free", Catalog.pawn("classic").price == 0 and not Catalog.pawn_gems_only("classic") and Catalog.pawn_gems("classic") == 0)
	var coin: Array = Catalog.PAWNS.filter(func(d): return int(d.price) > 0)
	var gem: Array = Catalog.PAWNS.filter(func(d): return Catalog.pawn_gems_only(d.id))
	check("a mix: coin skins and gem-only skins", coin.size() >= 3 and gem.size() >= 2, [coin.size(), gem.size()])
	check("coin skins sit in the dice range (1,000-6,000 coins)", coin.all(func(d): return int(d.price) >= 1000 and int(d.price) <= 6000))
	check("coin skins also cost ceil(price / 100) gems", coin.all(func(d): return Catalog.pawn_gems(d.id) == Catalog.gem_price(int(d.price))))
	check("gem-only skins have their own gem price (and no coin price)", gem.all(func(d): return int(d.price) == 0 and Catalog.pawn_gems(d.id) >= 80))
	check("every skin has a line for its sheet", Catalog.PAWNS.all(func(d): return str(d.get("desc", "")).length() > 10))
	check("pawn(unknown) is empty", Catalog.pawn("rainbow").is_empty() and Catalog.pawn_gems("rainbow") == 0)
	check("the Shop keeps Pawns and Dice together under Pieces", ShopSheet.strip_key("pawns") == "pieces" and ShopSheet.strip_key("dice") == "pieces")
	check("the Pawns tab lists every skin as kind pawn", ShopSheet._sections("pawns")[0][1].map(func(it): return it.kind + ":" + it.id) == ids.map(func(id): return "pawn:" + id))
	check("Shop prices: coins, gems, gem-only", ShopSheet._price("pawn", "marble") == 3500 and ShopSheet._gems("pawn", "marble") == 35
		and ShopSheet._price("pawn", "crown") == 0 and ShopSheet._gems("pawn", "crown") == Catalog.pawn_gems("crown") and ShopSheet._gems_only("pawn", "crown")
		and not ShopSheet._gems_only("pawn", "marble") and not ShopSheet._gems_only("dice", "crown"))
	check("titles read as plurals", ShopSheet._title("pawn", "Marble") == "Marble pawns" and ShopSheet._yours("pawn", "Marble pawns") == "Marble pawns are yours!")
	check("a push link's shop:pawn opens the Pawns tab", Notifications.shop_tab("pawn") == "pawns")
	check("every skin has a baked Shop picture", Thumbnailer.ids("pawn") == ids and ids.all(func(id): return Thumbnailer.has_baked("pawn", id)))
	check("every skin has its row of four colours for the setup sheet", ids.all(func(id): return Thumbnailer.has_baked("pawnrow", id) and (Thumbnailer.pawn_cell(id, 2)[1] as Rect2).position.x == 2.0 * Thumbnailer.PAWN_CELL.x))


# ---------- buying and equipping ----------

func _buying() -> void:
	var p: Dictionary
	var err: String
	p = use({coins = 0})
	check("Classic is owned even without the list", Catalog.owns_pawn("classic") and not Catalog.owns_pawn("trim") and Catalog.pawn_in_use() == "classic")
	check("owned_pawns lists Classic", Catalog.owned_pawns().map(func(d): return d.id) == ["classic"])
	p = use(fresh(5000))
	err = Catalog.buy_pawn("marble")
	check("buy with coins: success, paid once, owned and in use, saved once", err == "" and p.coins == 1500 and p.pawns_owned == ["classic", "marble"] and p.pawn == "marble" and writes == 1, [err, p, writes])
	check("buying is not coins earned", p.stats.coinsEarned == 0)
	err = Catalog.buy_pawn("marble")
	check("no double buy: refused, nothing more spent", err == "You already own Marble." and p.coins == 1500 and (p.pawns_owned as Array).count("marble") == 1 and writes == 1, err)
	err = Catalog.buy_pawn("teacup")
	check("not enough coins: the shortfall, nothing spent", err == "Not enough coins — you need 4,500 more." and p.coins == 1500 and not (p.pawns_owned as Array).has("teacup") and p.pawn == "marble", err)
	err = Catalog.buy_pawn("crown")
	check("gem-only skins are never sold for coins", err == "Royal Crown is sold for gems only." and p.coins == 1500 and not (p.pawns_owned as Array).has("crown"), err)
	err = Catalog.buy_pawn("rainbow")
	check("unknown skins aren't sold", err != "" and p.coins == 1500, err)
	err = Catalog.buy_pawn("classic")
	check("Classic can't be bought (already owned)", err != "" and p.coins == 1500)
	p = use(fresh(5000))
	err = Catalog.buy_pawn("trim", false)
	check("buy without equipping keeps the skin in use", err == "" and p.pawn == "classic" and (p.pawns_owned as Array).has("trim"))
	check("equip an owned skin", Catalog.equip_pawn("trim") and p.pawn == "trim" and Catalog.pawn_in_use() == "trim")
	check("equip a skin not owned: refused", not Catalog.equip_pawn("knight") and p.pawn == "trim")
	check("equip Classic always works", Catalog.equip_pawn("classic") and p.pawn == "classic")
	check("equip unknown: refused", not Catalog.equip_pawn("rainbow"))
	p = use(fresh(5000), true)
	err = Catalog.buy_pawn("kitty")
	check("a failed save spends nothing", err == Catalog.SAVE_FAILED and p.coins == 5000 and p.pawns_owned == ["classic"] and p.pawn == "classic", p)
	p = use({coins = 9000, pawns_owned = ["classic", "kitty"], pawn = "knight"})
	check("a saved skin that isn't owned falls back to Classic", Catalog.pawn_in_use() == "classic")
	p = use({coins = 9000, pawns_owned = ["crown", "nope", "crown"], pawn = "crown"})
	check("owned_pawns: Classic first, known ones once, in buy order", Catalog.owned_pawns().map(func(d): return d.id) == ["classic", "crown"])


func _save_defaults() -> void:
	var s: Node = load("res://scripts/core/save.gd").new()
	s.profile = {}
	s.prefs = {}
	s._ensure()
	check("a new profile owns and uses Classic", s.profile.pawns_owned == ["classic"] and s.profile.pawn == "classic", s.profile)
	s.profile = {pawns_owned = "x", pawn = 5}
	s._ensure()
	check("a damaged pawn field is repaired", s.profile.pawns_owned == ["classic"] and s.profile.pawn == "classic")
	s.profile = {pawns_owned = ["marble"], pawn = "marble"}
	s._ensure()
	check("an owned skin is kept (Classic added first)", s.profile.pawns_owned == ["classic", "marble"] and s.profile.pawn == "marble")
	s.profile = {pawns_owned = ["marble"], pawn = "crown"}
	s._ensure()
	check("an unowned equipped skin goes back to Classic", s.profile.pawn == "classic")
	s.free()


# ---------- who wears what ----------

func _who_wears_what() -> void:
	check("Ludo offline: your skin on your colour, Classic for the computer",
		LudoMatch.skins_of(["human", "cpu", "cpu", "cpu"], null, "crown") == ["crown", "", "", ""])
	check("Ludo offline: you on another colour",
		LudoMatch.skins_of(["cpu", "off", "human", "cpu"], null, "marble") == ["", "", "marble", ""])
	check("dice: yours on your colour, Classic for the computer", LudoMatch.skins_of(["human", "cpu", "cpu", "cpu"], null, "gold", "dice") == ["gold", "", "", ""])
	check("dice online: each seat's own", LudoMatch.skins_of(["human", "human", "human", "off"], [{color = 0, dice = "neon"}, {color = 1, dice = ""}, {color = 2, dice = "gold"}], "crema", "dice") == ["neon", "", "gold", ""])
	check("dice in S&L: by player", SLMatch.skins_of([{c = 0, cpu = false}, {c = 1, cpu = true}], null, "gold", "dice") == ["gold", ""])
	check("hello: only a die you own is sent", NetClient.dice_of({dice = "gold", dice_owned = ["classic", "gold"]}) == "gold" and NetClient.dice_of({dice = "gold", dice_owned = ["classic"]}) == "" and NetClient.dice_of({dice = "classic", dice_owned = ["classic"]}) == "")
	check("Ludo Pass & Play: the first player (this device's profile) wears it, the others Classic",
		LudoMatch.skins_of(["human", "human", "human", "off"], null, "kitty") == ["kitty", "", "", ""])
	var seats := [{color = 0, pawn = "trim"}, {color = 2, pawn = ""}, {color = 1, pawn = "knight"}]
	check("Ludo online: each seat's own skin, by colour", LudoMatch.skins_of(["human", "human", "human", "off"], seats, "crown") == ["trim", "knight", "", ""])
	var sl_players := [{c = 2, cpu = false}, {c = 0, cpu = true}, {c = 1, cpu = true}]
	check("S&L offline: your skin, the computer Classic", SLMatch.skins_of(sl_players, null, "teacup") == ["teacup", "", ""])
	check("S&L Pass & Play: the first player", SLMatch.skins_of([{c = 0, cpu = false}, {c = 1, cpu = false}], null, "glitter") == ["glitter", ""])
	check("S&L online: by seat colour", SLMatch.skins_of([{c = 0, cpu = false}, {c = 1, cpu = false}], [{color = 1, pawn = "crown"}, {color = 0, pawn = "marble"}], "") == ["marble", "crown"])
	check("hello: only an owned skin is sent", NetClient.pawn_of({pawn = "crown", pawns_owned = ["classic", "crown"]}) == "crown"
		and NetClient.pawn_of({pawn = "crown", pawns_owned = ["classic"]}) == "" and NetClient.pawn_of({pawn = "classic"}) == ""
		and NetClient.pawn_of({pawn = "nope", pawns_owned = ["nope"]}) == "" and NetClient.pawn_of({}) == "")
	var net := NetClient.new()
	net.use_save = false
	var prof: Dictionary = net._profile()
	check("the client's profile for hellos carries a pawn field", prof.has("pawn"), prof)
	net.free()


# ---------- the 3D skins ----------

## The vertices of one mesh (surface 0).
static func _verts(m: Mesh) -> int:
	return 0 if m == null else (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

## The triangles of one mesh (surface 0).
static func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var a := m.surface_get_arrays(0)
	return (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3

## The colour of a colour-table cell.
static func _table_px(t: ImageTexture, key: String) -> Color:
	var uv := PawnSkins._cell(key)
	return t.get_image().get_pixel(int(uv.x * t.get_width()), int(uv.y * t.get_height()))

static func _all_uv(m: Mesh, uv: Vector2) -> bool:
	for u: Vector2 in m.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
		if not u.is_equal_approx(uv):
			return false
	return true

func _skins_3d() -> void:
	var worst := 0
	var bad := []
	var heavy := []
	var wide := []
	var calls := []
	for d: Dictionary in Catalog.PAWNS:
		for seat: Color in Palette.PLAYER:                 # (only the fruity skin differs by seat)
			var sk := PawnSkins.meshes(d.id, seat)
			var n := _verts(sk.body) + _verts(sk.head)
			var tris := _tris(sk.body) + _tris(sk.head)
			var parts: Array = [sk.body, sk.head]
			for a: Dictionary in sk.accents:
				n += _verts(a.mesh)
				tris += _tris(a.mesh)
				parts.append(a.mesh)
			worst = maxi(worst, n)
			if tris > 3600:
				heavy.append([d.id, tris])
			if parts.filter(func(m): return m != null).size() > 4:
				calls.append(d.id)
			if sk.body == null or float(sk.top) < 0.6 or float(sk.top) > 1.16:
				bad.append(d.id)
			if d.id in PawnSkins.THEMED:
				for m: Mesh in parts.filter(func(x): return x != null):
					for v: Vector3 in m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
						if Vector2(v.x, v.z).length() > 0.4:
							wide.append(d.id)
							break
	check("every skin builds a body and a height that fits a square", bad.is_empty(), bad)
	check("no pawn is over 3,600 triangles", heavy.is_empty(), heavy)
	check("a pawn is at most four draw calls", calls.is_empty(), calls)
	check("the themed skins keep inside the classic pawn's square", wide.is_empty(), wide)
	var themed_mats := []
	for id: String in PawnSkins.THEMED:
		var host := Node3D.new()
		var look := PawnSkins.dress(host, id, Palette.PLAYER[0])
		themed_mats.append(look.mat)
		for a: Dictionary in look.accents:
			themed_mats.append(a.mat)
		host.free()
	check("themed skins add no shader variant: the pawn material, with a texture or without", themed_mats.all(func(m: StandardMaterial3D):
		return (m.clearcoat_enabled and m.emission_enabled and not m.vertex_color_use_as_albedo
			and m.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
			and m.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)))
	var table := PawnSkins.palette(Palette.PLAYER[1])
	check("the colour table is one small texture per seat colour", table == PawnSkins.palette(Palette.PLAYER[1]) and table != PawnSkins.palette(Palette.PLAYER[2]) and table.get_width() == PawnSkins.PALETTE_SIZE)
	check("... and has room for every colour", PawnSkins._cell_keys().size() <= PawnSkins.PALETTE_CELLS * PawnSkins.PALETTE_ROWS, PawnSkins._cell_keys().size())
	check("... each cell in its colour", _table_px(table, "gold").is_equal_approx(Color(str(PawnSkins.INKS.gold)))
		and _table_px(PawnSkins.palette(Palette.PLAYER[0]), "petal") != _table_px(PawnSkins.palette(Palette.PLAYER[3]), "petal"), _table_px(table, "gold"))
	check("the fruit differs by seat, one set of meshes per fruit", PawnSkins.meshes("fruity", Palette.PLAYER[0]) != PawnSkins.meshes("fruity", Palette.PLAYER[1])
		and is_same(PawnSkins.meshes("fruity", Palette.PLAYER[3]), PawnSkins.meshes("fruity", Palette.PLAYER[3])))
	for kind: String in ["stripes", "scales"]:
		var tex := PawnSkins.texture(kind, Palette.PLAYER[3])
		var im: Image = tex.get_image()
		var solid: Color = im.get_pixel(40, int(im.get_height() * (PawnSkins.SOLID_UV.y)))
		check("%s: small, the head's spot is the plain seat colour" % kind, im.get_width() <= 96 and im.get_height() <= 96 and solid.is_equal_approx(Palette.PLAYER[3]), solid)
		check("%s: made once" % kind, tex == PawnSkins.texture(kind, Palette.PLAYER[3]))
	check("the head of a scaly or striped pawn points at the plain part of its texture", _all_uv(PawnSkins.meshes("dragon").head, PawnSkins.SOLID_UV) and _all_uv(PawnSkins.meshes("candy").head, PawnSkins.SOLID_UV))
	# Top View: the head tips back about its own height, in 3D View it stays upright
	var host := Node3D.new()
	var robo := PawnSkins.dress(host, "robo", Palette.PLAYER[0])
	PawnSkins.pose(robo, 0.0, 1.29)
	check("pose, 3D View: on the stretched body, the face tipped part of the way up", is_equal_approx((robo.head as Node3D).rotation.x, -float(robo.look) * PawnSkins.TIP_3D) and (robo.head as Node3D).position.y >= PawnSkins.HEAD_Y * 1.29)
	PawnSkins.pose(robo, 1.0)
	check("pose, Top View: the head tips back", is_equal_approx((robo.head as Node3D).rotation.x, -float(robo.look)))
	var turning := (robo.head as Node3D).transform * Vector3(0, float(robo.pivot) - PawnSkins.HEAD_Y, 0)
	check("... about its turning height", turning.is_equal_approx(Vector3(0, float(robo.pivot), 0)), turning)
	var plain := PawnSkins.dress(host, "classic", Palette.PLAYER[0])
	PawnSkins.pose(plain, 1.0, 1.0)
	check("... Classic has no face to show: never tips", is_zero_approx((plain.head as Node3D).rotation.x) and is_equal_approx((plain.head as Node3D).position.y, PawnSkins.HEAD_Y))
	host.free()
	var classic := _verts(PawnSkins.meshes("classic").body) + _verts(PawnSkins.meshes("classic").head)
	check("no skin is much heavier than the classic pawn (< 4x its vertices)", worst < classic * 4.0, [worst, classic])
	check("meshes are built once per skin and shared", is_same(PawnSkins.meshes("crown"), PawnSkins.meshes("crown")))
	check("an unknown skin is Classic", is_same(PawnSkins.meshes("rainbow"), PawnSkins.meshes("classic")))
	var m := PawnSkins.material("marble", Palette.PLAYER[2])
	check("finishes: a texture of the seat colour, white albedo (dims through albedo_color)", m.albedo_texture != null and m.albedo_color == Color.WHITE)
	var px: Color = (m.albedo_texture as ImageTexture).get_image().get_pixel(5, 5)
	check("... the marble keeps the seat colour dominant", _close_hue(px, Palette.PLAYER[2]), [px, Palette.PLAYER[2]])
	var gl := PawnSkins.material("glitter", Palette.PLAYER[3])
	var img: Image = (gl.albedo_texture as ImageTexture).get_image()
	var near := 0
	for y in 24:
		for x in 24:
			if _close_hue(img.get_pixel(x, y), Palette.PLAYER[3]):
				near += 1
	check("... the glitter is mostly the seat colour", near > 24 * 24 * 0.75, near)
	check("glitter drifts (a twinkle seed); the others don't", gl.has_meta("twinkle") and not m.has_meta("twinkle"))
	check("no skin uses a shader of its own", [m, gl, PawnSkins.material("crown", Color.RED), PawnSkins.accent_material("gold", Color.GOLD)].all(func(x): return x is StandardMaterial3D))
	check("textures are made once per finish and colour", PawnSkins.texture("marble", Palette.PLAYER[2]) == m.albedo_texture)
	check("the teacup's froth stays its colour (Top View)", PawnSkins.froth(Palette.PLAYER[3]).s > 0.3, PawnSkins.froth(Palette.PLAYER[3]))

	# the Ludo board
	var board := LudoBoard.new()
	_root.add_child(board)
	check("the board starts Classic", board.skins == ["classic", "classic", "classic", "classic"] and board.toks[0][0].skin == "classic")
	var halo: Node = board.toks[1][2].halo
	var look_before: Dictionary = board.toks[0][0].look
	board.set_skins(["", "crown", "knight", "teacup"])
	check("set_skins dresses each colour's four pawns", board.skins == ["classic", "crown", "knight", "teacup"]
		and board.toks[1].all(func(t): return t.skin == "crown") and board.toks[3].all(func(t): return t.skin == "teacup"))
	check("a colour whose skin didn't change isn't rebuilt", is_same(board.toks[0][0].look, look_before))
	check("the glow / halo / ring / badge / symbol parts stay on the pawn", is_same(board.toks[1][2].halo, halo)
		and board.toks[1][2].node.get_node_or_null("Body") != null and board.toks[1][2].node.get_node_or_null("Head") != null
		and board.toks[1][2].node.get_children().filter(func(c): return c.name == "Body").size() == 1)
	check("every pawn has its own seat-colour material (it glows / dims alone)", not is_same(board.toks[1][0].mat, board.toks[1][1].mat)
		and (board.toks[1][0].mat as StandardMaterial3D).albedo_color == Palette.PLAYER[1])
	check("accents (the crown's gold) dim with the pawn", board.toks[1][0].accents.size() >= 1 and board.toks[3][0].accents.size() >= 1)
	check("taller skins lift the chevron and the colour-blind symbol", float(board.toks[2][0].over) > 0.1 and float(board.toks[3][0].over) < 0.0)
	var total := 0
	for row in board.toks:
		for t in row:
			for mi in (t.node as Node).find_children("*", "MeshInstance3D", true, false):
				if mi.get_parent().name in ["Body", "Head"]:
					total += _verts((mi as MeshInstance3D).mesh)
	check("16 pawns in a heavy mix stay modest (< 70k vertices)", total < 70000, total)
	board.set_movable([4, 5], 1)
	board._process(0.5)
	check("a dimmed skin darkens its accents too", (board.toks[1][2].accents[0].mat as StandardMaterial3D).albedo_color != PawnSkins.GOLD)
	board.set_skins([])
	check("set_skins([]): Classic again", board.skins == ["classic", "classic", "classic", "classic"] and board.toks[3][0].accents.is_empty())
	_root.remove_child(board)
	board.free()

	# Snakes & Ladders
	var sl := SLBoard.new()
	_root.add_child(sl)
	sl.reduce_motion = 1
	sl.setup_players([0, 1, 2], ["knight", "", "teacup"])
	check("S&L: each player in their skin", sl.pawns.map(func(t): return t.skin) == ["knight", "classic", "teacup"])
	check("S&L: pops sit over the taller knight", sl.pawn_top(0).y > sl.pawn_top(1).y)
	sl.setup_players([0, 1])
	check("S&L: no skins given -> Classic", sl.pawns.all(func(t): return t.skin == "classic"))
	_root.remove_child(sl)
	sl.free()

static func _close_hue(a: Color, b: Color) -> bool:
	var dh := absf(a.h - b.h)
	return minf(dh, 1.0 - dh) < 0.06 or (a.s < 0.2 and b.s < 0.2)


# ---------- the flat pawn ----------

func _flat_art() -> void:
	check("flat heights: taller shapes, the short teacup", PawnArt.height("knight") > PawnArt.height("classic") and PawnArt.height("teacup") < PawnArt.height("classic")
		and PawnArt.height("crown") > PawnArt.TOP)
	check("flat outlines close on the axis for every shape", Catalog.PAWNS.all(func(d): return PawnArt._outline(d.id).size() >= 8))
	var low := []
	for d: Dictionary in Catalog.PAWNS:
		if absf(PawnArt.height(d.id) - float(PawnSkins.meshes(d.id, Palette.PLAYER[0]).top)) > 0.12:
			low.append(d.id)
	check("flat heights match the 3D skins", low.is_empty(), low)


# ---------- the gem path (server wallet) ----------

func _wallet() -> void:
	var sp: Dictionary = Save.profile
	var spf: Dictionary = Save.prefs
	Save.profile = Fake.base_profile()
	Save.prefs = {}
	Save.normalize()
	var cut := Save._timer.timeout.is_connected(Save.flush)
	if cut:
		Save._timer.timeout.disconnect(Save.flush)
	var f := Fake.new()
	f.prices["pawn_trim"] = 2000
	f.gem_only["pawn_crown"] = Catalog.pawn_gems("crown")
	f.profile.gems = 200
	var acc := Account.new()
	acc.url_base = "ws://fake"
	acc.http_fn = f.http
	acc.persist = Callable()
	_root.add_child(acc)
	await acc.sign_in_guest()
	var shop := ShopSheet.new("pawns")
	_root.add_child(shop)
	var coin_view := PawnSheet.new("trim")
	var gem_view := PawnSheet.new("crown")
	check("the preview of a coin skin offers its gems too", coin_view._gem != null and int(coin_view._gem.get_meta("gems")) == 20)
	check("the preview of a gem-only skin has no second line (its Buy pays gems)", gem_view._gem == null)
	coin_view.free()
	gem_view.free()
	var err: String = await ShopSheet._purchase("pawn", "crown")
	check("a gem-only skin bought with coins: the server refuses, nothing changes", err != "" and not Save.profile.pawns_owned.has("crown") and int(Save.profile.gems) == 200, err)
	err = await ShopSheet._purchase("pawn", "crown", "gems")
	check("bought with gems: the server sells it, the profile owns and wears it", err == "" and f.last("/v1/shop/buy").body == {kind = "pawn", id = "crown", currency = "gems", catalog = 2}
		and Save.profile.pawns_owned.has("crown") and Save.profile.pawn == "crown" and int(Save.profile.gems) == 200 - Catalog.pawn_gems("crown"), [err, Save.profile.get("pawns_owned"), Save.profile.get("gems")])
	err = await ShopSheet._purchase("pawn", "trim")
	check("a coin skin through the server: coins paid, worn", err == "" and Save.profile.pawn == "trim" and int(Save.profile.coins) == 3000, [err, Save.profile.coins])
	await shop._on_use("pawn", "crown")
	check("Use goes through the server's equip", f.last("/v1/shop/equip").body == {kind = "pawn", id = "crown"} and Save.profile.pawn == "crown")
	check("the hello of this profile carries the skin", NetClient.pawn_of(Save.profile) == "crown")
	_root.remove_child(shop)
	shop.free()
	if acc.get_parent():
		acc.get_parent().remove_child(acc)
	Account.set_instance(null)
	acc.free()
	Save._dirty = false
	Save.profile = sp
	Save.prefs = spf
	if cut:
		Save._timer.timeout.connect(Save.flush)
	_done = true
