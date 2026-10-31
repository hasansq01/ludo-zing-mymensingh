extends "res://tests/test_suite.gd"
## The Bangla catalogue (locale/bn.po) against the scripts: every string marked for translation (tr, tr_n,
## L10n.t, the l10n markers: scripts/core/l10n.gd) has Bangla, keeps its placeholders and BBCode in order, keeps
## "Ludo Zing" in Latin letters, Latin digits, and never says "Ludo King"; the catalogue loads through
## project.godot; L10n picks the language as Settings and the phone say. To see what is missing:
##   godot --headless --path godot -s res://tools/l10n_sync.gd -- --check

const Extract := preload("res://tools/l10n_extract.gd")

var _ph := RegEx.create_from_string("%(?:%|[-+ 0]*\\*?\\d*(?:\\.\\d+)?[scdoxXfv])")
var _bb := RegEx.create_from_string("\\[/?[a-z_]+(?:=[^\\]]*)?\\]")
var _bn_digit := RegEx.create_from_string("[০-৯]")
var _bengali := RegEx.create_from_string("[ঀ-৿]")

func run() -> void:
	var found: Dictionary = Extract.new().extract()
	var po: Dictionary = Extract.read_po()
	check("scripts: every translation call has one literal msgid (translate first, then format)", found.warnings.is_empty(), found.warnings)
	check("catalogue: there is text to translate", found.order.size() > 100, found.order.size())

	var missing := []
	var not_synced := []
	var bad_ph := []
	var bad_bb := []
	var brand := []
	var digits := []
	var english := []
	for k: String in found.order:
		var e: Dictionary = found.entries[k]
		var p: Dictionary = po.entries.get(k, {})
		if p.is_empty() or p.get("obsolete", false):
			not_synced.append(e.refs[0] + " " + e.id)
		var bn := Extract.bn_of(p) if not p.is_empty() else ""
		if bn == "":
			missing.append(e.refs[0] + " " + e.id)
			continue
		var texts: Array = p.strs if e.plural != "" and p.strs.size() else [bn]
		for t: String in texts:
			if _all(_ph, e.id) != _all(_ph, t) and (e.plural == "" or _all(_ph, e.plural) != _all(_ph, t)):
				bad_ph.append([e.id, t])
			if _all(_bb, e.id) != _all(_bb, t):
				bad_bb.append([e.id, t])
			if t.to_lower().contains("ludo king") or (e.id.contains("Ludo Zing") and not t.contains("Ludo Zing")):
				brand.append([e.id, t])
			if _bn_digit.search(t):
				digits.append([e.id, t])
		if not _bengali.search(bn) and bn == e.id and not _same_ok(p):
			english.append(e.id)
	check("bn.po: every marked string has Bangla (run tools/l10n_sync.gd -- --check)", missing.is_empty(), missing.slice(0, 40))
	check("bn.po: in step with the scripts (run tools/l10n_sync.gd)", not_synced.is_empty(), not_synced.slice(0, 20))
	check("bn.po: the same %s / %d placeholders, in the same order", bad_ph.is_empty(), bad_ph)
	check("bn.po: the same BBCode tags", bad_bb.is_empty(), bad_bb)
	check("bn.po: \"Ludo Zing\" stays in Latin letters, never \"Ludo King\"", brand.is_empty(), brand)
	check("bn.po: digits stay Latin", digits.is_empty(), digits)
	check("bn.po: no English copied as Bangla (unless a \"# same in Bangla\" note says so)", english.is_empty(), english)
	var never := []
	for k: String in po.order:
		if Extract.bn_of(po.entries[k]).to_lower().contains("ludo king"):
			never.append(po.entries[k].id)
	check("bn.po: \"Ludo King\" nowhere (obsolete entries too)", never.is_empty(), never)

	# ---- the catalogue loads and switches ----
	var keep := TranslationServer.get_locale()
	var sample := ""
	var want := ""
	for k: String in found.order:
		var p: Dictionary = po.entries.get(k, {})
		if found.entries[k].ctx == "" and found.entries[k].plural == "" and Extract.bn_of(p) != "":
			sample = found.entries[k].id
			want = Extract.bn_of(p)
			break
	L10n.apply("bn")
	check("L10n.apply(bn): Bangla from project.godot's catalogue", sample != "" and L10n.t(sample) == want and L10n.lang() == "bn", [sample, L10n.t(sample)])
	L10n.apply("en")
	check("L10n.apply(en): the English source text", L10n.t(sample) == sample and L10n.lang() == "en" and not L10n.is_bn(), L10n.t(sample))
	TranslationServer.set_locale(keep)
	check("L10n.resolve: en / bn as picked, auto and anything else follow the phone", L10n.resolve("en") == "en" and L10n.resolve("bn") == "bn"
		and L10n.resolve("auto") == L10n.phone() and L10n.resolve(null) == L10n.phone() and L10n.resolve("fr") == L10n.phone())
	check("L10n.phone: bn or en", L10n.phone() in ["bn", "en"], L10n.phone())

	# ---- the lexer reads the forms the markers allow ----
	var toks := Extract.lex("x = tr(\"a\\\"b\\n\") # l10n\nvar s := &\"id\"\ny = '''t\nu'''")
	var strs := toks.filter(func(t: Dictionary) -> bool: return t.k == "s")
	check("lexer: escapes, StringName prefix, triple quotes and their lines", strs.size() == 3 and strs[0].v == "a\"b\n" and strs[1].pre == "&"
		and strs[2].v == "t\nu" and strs[2].line == 3, strs)

## Every match of `re` in `s`, in order.
func _all(re: RegEx, s: String) -> Array:
	return re.search_all(s).map(func(m: RegExMatch) -> String: return m.get_string())

## A translator comment can say the Bangla is the English on purpose ("# same in Bangla: 3D").
func _same_ok(p: Dictionary) -> bool:
	return p.get("comments", []).any(func(c: String) -> bool: return c.to_lower().contains("same in bangla"))
