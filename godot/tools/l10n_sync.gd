extends SceneTree
## Keeps the Bangla catalogue (res://locale/bn.po) in step with the scripts. Run from the repo root:
##   godot --headless --path godot -s res://tools/l10n_sync.gd                  # rewrite bn.po, list what is missing
##   godot --headless --path godot -s res://tools/l10n_sync.gd -- --check       # change nothing; exit 1 when a marked
##                                                                              # string has no Bangla (or on warnings)
##   ... -- --dump=<out.json> [--files=scripts/ui/a.gd,scripts/ui/b.gd]         # the marked strings as JSON (no write)
##   ... -- --import=<drafts.json>[,<more.json>]                                # take Bangla from JSON lists, then sync
## The marking forms are in scripts/core/l10n.gd; the lexer and the .po reader / writer in tools/l10n_extract.gd.
## Sync: every marked string gets an entry (English msgid, a "#." line saying where it is shown, "#:" file:line
## references, the TRANSLATORS: notes of the code), in script order; existing Bangla, translator comments ("# ")
## and flags are kept; entries no longer in the code move to the end as obsolete (#~), so nothing translated is lost.
## JSON for --dump / --import: [{"id": "Play", "ctx": "", "plural": "", "bn": "খেলো", "note": "..."}]; "note"
## becomes a translator comment, an empty "bn" changes nothing.

const Extract := preload("res://tools/l10n_extract.gd")

const HEADER := "Project-Id-Version: Ludo Zing\nMIME-Version: 1.0\nContent-Type: text/plain; charset=UTF-8\nContent-Transfer-Encoding: 8bit\nLanguage: bn\nPlural-Forms: nplurals=2; plural=(n != 1);\n"
const INTRO := [
	"Ludo Zing: the Bangla interface text.",
	"msgid = the English text in the scripts; msgstr = the Bangla shown when the phone (or Settings) picks বাংলা.",
	"Each entry: #. where it is shown, #: the script lines, # notes for the reviewer.",
	"Keep %s / %d placeholders in the same order, digits Latin, \"Ludo Zing\" in Latin letters.",
	"Regenerate with: godot --headless --path godot -s res://tools/l10n_sync.gd (keeps every translation).",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var check := "--check" in args
	var dump := ""
	var imp := ""
	var files := PackedStringArray()
	for a in args:
		if a.begins_with("--dump="):
			dump = a.trim_prefix("--dump=")
		elif a.begins_with("--import="):
			imp = a.trim_prefix("--import=")
		elif a.begins_with("--files="):
			for f in a.trim_prefix("--files=").split(","):
				if f.strip_edges() != "":
					files.append("res://" + f.strip_edges().trim_prefix("godot/").trim_prefix("res://"))
	var ex = Extract.new()
	var found: Dictionary = ex.extract(files)
	for w: String in found.warnings:
		print("WARNING ", w)
	var po: Dictionary = Extract.read_po()
	if dump != "":
		var arr := []
		for k: String in found.order:
			var e: Dictionary = found.entries[k]
			var old: Dictionary = po.entries.get(k, {})
			arr.append({id = e.id, ctx = e.ctx, plural = e.plural, refs = e.refs, bn = Extract.bn_of(old) if not old.is_empty() else "", note = ""})
		var f := FileAccess.open(dump, FileAccess.WRITE)
		f.store_string(JSON.stringify(arr, "  "))
		f.close()
		print("l10n: %d strings -> %s" % [arr.size(), dump])
		quit(0)
		return
	for path in imp.split(",", false):
		_import(po, path)
	# merge
	var out := {header = po.header if po.header != "" else HEADER, entries = {}, order = []}
	var missing := []
	for k: String in found.order:
		var e: Dictionary = found.entries[k]
		var old: Dictionary = po.entries.get(k, {})
		var m := e.duplicate()
		m.comments = old.get("comments", [])
		m.flags = old.get("flags", [])
		m.str = old.get("str", "")
		m.strs = old.get("strs", [])
		if e.plural != "" and m.strs.is_empty() and m.str != "":
			m.strs = [m.str, m.str]
		out.entries[k] = m
		out.order.append(k)
		if Extract.bn_of(m) == "":
			missing.append(m)
	var gone := 0
	for k: String in po.order:
		if not out.entries.has(k):
			var e: Dictionary = po.entries[k]
			if Extract.bn_of(e) == "":
				continue                          # an untranslated string that left the code: just dropped
			e.obsolete = true
			out.entries[k] = e
			out.order.append(k)
			gone += 1
	for e: Dictionary in missing:
		print("MISSING %s  %s%s" % [e.refs[0], ("[" + e.ctx + "] ") if e.ctx != "" else "", JSON.stringify(e.id)])
	print("l10n: %d strings, %d without Bangla, %d obsolete, %d warnings" % [found.order.size(), missing.size(), gone, found.warnings.size()])
	if check:
		quit(1 if missing.size() or found.warnings.size() else 0)
		return
	_write(out)
	print("l10n: wrote ", Extract.PO)
	quit(0)

## Bangla (and notes) from a JSON draft list into the catalogue read from disk.
func _import(po: Dictionary, path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Array:
		push_error("l10n: %s is not a JSON list" % path)
		return
	var n := 0
	for d in data:
		if not d is Dictionary or str(d.get("bn", "")) == "":
			continue
		var ctx := str(d.get("ctx", ""))
		var id := str(d.get("id", ""))
		var k := Extract.key_of(ctx, id)
		var e: Dictionary = po.entries.get(k, {ctx = ctx, id = id, plural = str(d.get("plural", "")), str = "", strs = [], comments = [], flags = []})
		var bn := str(d.bn)
		if str(e.get("plural", "")) != "":
			e.strs = [bn, bn]
		e.str = bn
		e.obsolete = false
		var note := str(d.get("note", "")).strip_edges()
		if note != "" and not note in e.comments:
			e.comments.append(note)
		if not po.entries.has(k):
			po.order.append(k)
		po.entries[k] = e
		n += 1
	print("l10n: imported %d translations from %s" % [n, path])

func _write(po: Dictionary) -> void:
	var s := ""
	for l in INTRO:
		s += "# " + l + "\n"
	s += "msgid \"\"\n" + Extract._field("msgstr", po.header) + "\n"
	var obsolete := ""
	for k: String in po.order:
		var e: Dictionary = po.entries[k]
		if e.get("obsolete", false):
			var keep := e.duplicate()
			keep.wheres = []
			keep.refs = []
			keep.notes = []
			var body := Extract.entry_text(keep, "#~ ")
			obsolete += body + "\n"
		else:
			s += Extract.entry_text(e) + "\n"
	s += obsolete
	DirAccess.make_dir_recursive_absolute(Extract.PO.get_base_dir())
	var f := FileAccess.open(Extract.PO, FileAccess.WRITE)
	f.store_string(s.strip_edges() + "\n")
	f.close()
