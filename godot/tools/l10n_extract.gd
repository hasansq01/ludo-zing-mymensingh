extends RefCounted
## The translation catalogue's reader and writer (used by tools/l10n_sync.gd and tests/test_l10n.gd; not exported).
## extract() lexes every script under res://scripts/ (not scripts/debug/) and collects the text marked for
## translation (the forms are listed in scripts/core/l10n.gd): tr / tr_n / atr / atr_n / L10n.t / L10n.tn /
## TranslationServer.translate calls with a literal first argument, `# l10n` lines, `# l10n:begin` ... `# l10n:end`
## blocks and `## l10n-keys:` dictionary values. A call whose argument is a literal followed by more code
## (tr("Need " + x), tr("%d" % n)) is reported as a warning: that text can never match a msgid.
## read_po() / write_po() load and save a gettext catalogue (msgctxt, plurals, comments, obsolete #~ entries).

const SCRIPTS := "res://scripts/"
const SKIP_DIRS := ["res://scripts/debug/"]
const PO := "res://locale/bn.po"

## Where each script's text is seen, for the "#." comment of every entry (the reviewer's map). Scripts not listed
## use their file name.
const AREAS := {
	"main": "App (pause menu, dialogs, toasts)",
	"home_screen": "Home screen",
	"splash": "Splash screen",
	"welcome": "Welcome screen (first launch)",
	"sl_landing": "Snakes & Ladders landing",
	"setup_sheet": "Game setup sheet",
	"sheet": "Sheets (shared dialogs)",
	"ui_kit": "Shared widgets",
	"info": "Info bubbles and rules text",
	"coach_marks": "Tutorial coach marks",
	"tutorial": "Tutorial",
	"ludo_hud": "Ludo match HUD",
	"ludo_match": "Ludo match",
	"sl_match": "Snakes & Ladders match",
	"result_screen": "Result screen",
	"game_top_bar": "Match top bar",
	"player_tile": "Match player tiles",
	"toast": "Toasts",
	"notif_plan": "Local notifications",
	"fmt": "Numbers and times",
}

var _letters := RegEx.create_from_string("[A-Za-z]")


# =====================================================================================================================
# Extraction
# =====================================================================================================================

## Every marked string: {entries: {key: entry}, order: [key], warnings: [String]}. key = ctx + "\u0004" + msgid
## (just msgid without a context); entry = {ctx, id, plural, refs: ["scripts/x.gd:12"], wheres: [..], notes: [..]}.
## `only`: limit to these res:// script paths (empty: all).
func extract(only: PackedStringArray = PackedStringArray()) -> Dictionary:
	var res := {entries = {}, order = [], warnings = []}
	var files := scripts()
	files.sort()
	for path in files:
		if only.size() and not path in only:
			continue
		_extract_file(path, res)
	return res

## All .gd files under SCRIPTS except SKIP_DIRS.
func scripts(dir := SCRIPTS) -> PackedStringArray:
	var out := PackedStringArray()
	if dir in SKIP_DIRS:
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(scripts(dir + d + "/"))
	return out

static func key_of(ctx: String, id: String) -> String:
	return id if ctx == "" else ctx + "\u0004" + id

func _extract_file(path: String, res: Dictionary) -> void:
	var src := FileAccess.get_file_as_string(path)
	var toks := lex(src)
	var rel := path.trim_prefix("res://")
	var stem := path.get_file().get_basename()
	var area := str(AREAS.get(stem, ""))
	# comments: markers by line
	var mark_lines := {}
	var notes := {}                      # line -> note (TRANSLATORS:)
	var blocks: Array = []               # [from_line, to_line]
	var keys := PackedStringArray()
	var open := -1
	for t: Dictionary in toks:
		if t.k != "c":
			continue
		var c: String = t.v
		if c.begins_with("##") and not c.contains("l10n-keys:"):
			continue                         # doc comments describe the markers, they aren't markers
		if c.contains("l10n:begin"):
			open = t.line
		elif c.contains("l10n:end"):
			if open >= 0:
				blocks.append([open, t.line])
			open = -1
		elif c.contains("l10n-keys:"):
			for k in c.get_slice("l10n-keys:", 1).split(","):
				if k.strip_edges() != "":
					keys.append(k.strip_edges())
		elif _is_line_marker(c):
			mark_lines[t.line] = true
		if c.contains("TRANSLATORS:"):
			notes[t.line] = c.get_slice("TRANSLATORS:", 1).strip_edges()
	if open >= 0:
		res.warnings.append("%s:%d: l10n:begin without l10n:end" % [rel, open])
	var code: Array = toks.filter(func(t: Dictionary) -> bool: return t.k != "c")
	var fn := ""
	var depth := 0                       # { } nesting (l10n-keys look inside dictionaries only)
	var taken := {}                      # token index -> true (a call's arguments)
	var i := 0
	while i < code.size():
		var t: Dictionary = code[i]
		if t.k == "id" and t.v == "func" and i + 1 < code.size() and code[i + 1].k == "id":
			fn = code[i + 1].v
		elif t.k == "p" and t.v == "{":
			depth += 1
		elif t.k == "p" and t.v == "}":
			depth = maxi(0, depth - 1)
		var call := _call_at(code, i)
		if not call.is_empty():
			var a: int = call.arg
			var s: Dictionary = code[a]
			if not call.ok:
				res.warnings.append("%s:%d: %s() needs one string literal (translate first, then format)" % [rel, s.line, call.name])
			else:
				taken[a] = true
				if call.has("plural_at"):
					taken[call.plural_at] = true
				_add(res, call.ctx, s.v, call.get("plural", ""), rel, s.line, area, fn, _note(notes, s.line))
		elif t.k == "s" and not taken.has(i) and t.pre == "":
			var by_line: bool = mark_lines.has(t.line) or blocks.any(func(b: Array) -> bool: return t.line > b[0] and t.line < b[1])
			var by_key := false
			if keys.size() and depth > 0 and i >= 2:
				var prev: Dictionary = code[i - 1]
				var k: Dictionary = code[i - 2]
				by_key = prev.k == "p" and (prev.v == "=" or prev.v == ":") and (k.k == "id" or k.k == "s") and str(k.v) in keys
			if by_line or by_key:
				_add(res, "", t.v, "", rel, t.line, area, fn, _note(notes, t.line))
		i += 1

static func _is_line_marker(c: String) -> bool:
	var at := c.find("l10n")
	while at >= 0:
		var after := c.substr(at + 4, 1)
		var before := c.substr(at - 1, 1) if at > 0 else " "
		if not (after in [":", "-", "_"] or after.is_valid_identifier()) and not (before.is_valid_identifier() or before == "."):
			return true
		at = c.find("l10n", at + 4)
	return false

static func _note(notes: Dictionary, line: int) -> String:
	return str(notes.get(line, notes.get(line - 1, "")))

## A translation call starting at code[i]: {} when none, else {name, arg (token index of the msgid), ok, ctx,
## plural?, plural_at?}. ok = false when the first argument is a literal with more code after it.
func _call_at(code: Array, i: int) -> Dictionary:
	var t: Dictionary = code[i]
	if t.k != "id":
		return {}
	var name := ""
	var j := i + 1
	if t.v in ["tr", "atr", "tr_n", "atr_n"] and not (i > 0 and code[i - 1].k == "id" and code[i - 1].v == "func"):
		name = t.v
	elif t.v in ["L10n", "TranslationServer"] and j + 1 < code.size() and code[j].v == "." and code[j + 1].k == "id":
		var m: String = code[j + 1].v
		if (t.v == "L10n" and m in ["t", "tn"]) or (t.v == "TranslationServer" and m in ["translate", "translate_plural"]):
			name = t.v + "." + m
			j += 2
	if name == "" or j + 1 >= code.size() or code[j].v != "(" or code[j].k != "p" or code[j + 1].k != "s":
		return {}
	var plural := name in ["tr_n", "atr_n", "L10n.tn", "TranslationServer.translate_plural"]
	var a := j + 1
	var out := {name = name, arg = a, ok = true, ctx = ""}
	var nx: Dictionary = code[a + 1] if a + 1 < code.size() else {}
	if nx.is_empty() or nx.k != "p" or not nx.v in [",", ")"]:
		out.ok = false
		return out
	if not plural:
		if nx.v == "," and a + 3 < code.size() and code[a + 2].k == "s" and code[a + 3].v == ")":
			out.ctx = code[a + 2].v
		return out
	# plural: (msgid, plural, n [, ctx])
	if nx.v != "," or a + 2 >= code.size() or code[a + 2].k != "s":
		out.ok = false
		return out
	out.plural = code[a + 2].v
	out.plural_at = a + 2
	var k := a + 3                       # skip ", n" to the next top-level comma / close
	var d := 0
	var commas := 0
	while k < code.size():
		var c: Dictionary = code[k]
		if c.k == "p" and c.v in ["(", "[", "{"]:
			d += 1
		elif c.k == "p" and c.v in [")", "]", "}"]:
			if d == 0:
				break
			d -= 1
		elif c.k == "p" and c.v == "," and d == 0:
			commas += 1
			if commas == 2 and k + 1 < code.size() and code[k + 1].k == "s":
				out.ctx = code[k + 1].v
		k += 1
	return out

func _add(res: Dictionary, ctx: String, id: String, plural: String, rel: String, line: int, area: String, fn: String, note: String) -> void:
	if id.strip_edges() == "" or not _letters.search(id):
		return
	var key := key_of(ctx, id)
	if not res.entries.has(key):
		res.entries[key] = {ctx = ctx, id = id, plural = plural, refs = [], wheres = [], notes = []}
		res.order.append(key)
	var e: Dictionary = res.entries[key]
	var ref := "%s:%d" % [rel, line]
	if not ref in e.refs:
		e.refs.append(ref)
	var where := "%s%s%s" % [(area + " · ") if area != "" else "", rel.get_file(), (" " + fn + "()") if fn != "" else ""]
	if not where in e.wheres:
		e.wheres.append(where)
	if note != "" and not note in e.notes:
		e.notes.append(note)
	if plural != "" and e.plural == "":
		e.plural = plural


# =====================================================================================================================
# A small GDScript lexer: strings (with their values), identifiers, punctuation and comments, each with its line
# =====================================================================================================================

## Tokens {k: "s" | "id" | "p" | "c", v, line, pre}: k "s" = string literal (v = its value; pre "&" StringName,
## "^" NodePath, "r" raw), "id" identifier or keyword, "p" one punctuation character, "c" comment (v = its text
## from the #). Numbers are skipped.
static func lex(src: String) -> Array:
	var out := []
	var n := src.length()
	var i := 0
	var line := 1
	while i < n:
		var ch := src.unicode_at(i)
		if ch == 10:
			line += 1
			i += 1
		elif ch == 32 or ch == 9 or ch == 13:
			i += 1
		elif ch == 92 and i + 1 < n and src.unicode_at(i + 1) == 10:   # line continuation
			line += 1
			i += 2
		elif ch == 35:                                                  # comment
			var e := src.find("\n", i)
			if e < 0:
				e = n
			out.append({k = "c", v = src.substr(i, e - i), line = line, pre = ""})
			i = e
		elif ch == 34 or ch == 39:
			var pre := ""
			if i > 0 and src.unicode_at(i - 1) in [38, 94]:
				pre = src.substr(i - 1, 1)
			var r := _read_string(src, i, false)
			out.append({k = "s", v = r.v, line = line, pre = pre})
			line += int(r.lines)
			i = r.end
		elif _ident_start(ch):
			var s := i
			while i < n and (_ident_start(src.unicode_at(i)) or (src.unicode_at(i) >= 48 and src.unicode_at(i) <= 57)):
				i += 1
			var word := src.substr(s, i - s)
			if word == "r" and i < n and src.unicode_at(i) in [34, 39]:       # raw string r"..."
				var r := _read_string(src, i, true)
				out.append({k = "s", v = r.v, line = line, pre = "r"})
				line += int(r.lines)
				i = r.end
			else:
				out.append({k = "id", v = word, line = line, pre = ""})
		elif ch >= 48 and ch <= 57:
			while i < n and (_ident_start(src.unicode_at(i)) or (src.unicode_at(i) >= 48 and src.unicode_at(i) <= 57) or src.unicode_at(i) == 46):
				i += 1
		else:
			out.append({k = "p", v = src.substr(i, 1), line = line, pre = ""})
			i += 1
	return out

static func _ident_start(c: int) -> bool:
	return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 or c > 127

## Reads the literal starting at src[i] (a quote): {v, end, lines}.
static func _read_string(src: String, i: int, raw: bool) -> Dictionary:
	var n := src.length()
	var q := src.substr(i, 1)
	var triple := src.substr(i, 3) == q + q + q
	i += 3 if triple else 1
	var buf := ""
	var lines := 0
	while i < n:
		var c := src.substr(i, 1)
		if c == "\\" and not raw and i + 1 < n:
			var x := src.substr(i + 1, 1)
			i += 2
			match x:
				"n": buf += "\n"
				"t": buf += "\t"
				"r": buf += "\r"
				"\n": lines += 1
				"u":
					buf += char(src.substr(i, 4).hex_to_int())
					i += 4
				"U":
					buf += char(src.substr(i, 6).hex_to_int())
					i += 6
				_: buf += x
			continue
		if triple and src.substr(i, 3) == q + q + q:
			return {v = buf, end = i + 3, lines = lines}
		if not triple and c == q:
			return {v = buf, end = i + 1, lines = lines}
		if c == "\n":
			lines += 1
			if not triple:
				return {v = buf, end = i, lines = lines - 1}
		buf += c
		i += 1
	return {v = buf, end = n, lines = lines}


# =====================================================================================================================
# The .po file
# =====================================================================================================================

## {header: String (the header msgstr), entries: {key: entry}, order: [key]}; entry = {ctx, id, plural, str (or
## strs: [..] for plurals), comments: [translator "# " lines], flags: [..], obsolete: bool}.
static func read_po(path := PO) -> Dictionary:
	var out := {header = "", entries = {}, order = []}
	if not FileAccess.file_exists(path):
		return out
	var cur := {}
	var field := ""
	var flush := func() -> void:
		if cur.is_empty() or not cur.has("id"):
			cur.clear()
			return
		if cur.id == "" and cur.get("ctx", "") == "":
			out.header = cur.get("str", "")
		else:
			var e := {ctx = cur.get("ctx", ""), id = cur.id, plural = cur.get("plural", ""), str = cur.get("str", ""),
				strs = cur.get("strs", []), comments = cur.get("comments", []), flags = cur.get("flags", []),
				obsolete = cur.get("obsolete", false)}
			var k := key_of(e.ctx, e.id)
			if not out.entries.has(k):
				out.order.append(k)
			out.entries[k] = e
		cur.clear()
	for raw_line in FileAccess.get_file_as_string(path).split("\n"):
		var l := raw_line.strip_edges()
		var obsolete := false
		if l.begins_with("#~"):
			obsolete = true
			l = l.substr(2).strip_edges()
		elif l.begins_with("#"):
			if cur.has("id") and field != "":
				flush.call()
				field = ""
			if l.begins_with("#,"):
				if not cur.has("flags"):
					cur.flags = []
				for f in l.substr(2).split(","):
					cur.flags.append(f.strip_edges())
			elif l == "#" or l.begins_with("# "):
				if not cur.has("comments"):
					cur.comments = []
				cur.comments.append(l.substr(2) if l.length() > 1 else "")
			continue
		if l == "":
			continue
		if obsolete:
			cur.obsolete = true
		if l.begins_with("\""):
			_po_append(cur, field, _unq(l))
			continue
		var sp := l.find(" ")
		if sp < 0:
			continue
		var kw := l.substr(0, sp)
		var val := _unq(l.substr(sp + 1).strip_edges())
		if kw == "msgctxt" or (kw == "msgid" and cur.has("id")):
			if cur.has("id"):
				var keep_comments: Array = []
				flush.call()
				cur.comments = keep_comments
		match kw:
			"msgctxt": field = "ctx"
			"msgid": field = "id"
			"msgid_plural": field = "plural"
			"msgstr": field = "str"
			_:
				if kw.begins_with("msgstr["):
					field = "strs"
					if not cur.has("strs"):
						cur.strs = []
					cur.strs.append("")
				else:
					continue
		if field == "strs":
			cur.strs[cur.strs.size() - 1] = val
		else:
			cur[field] = val
	flush.call()
	return out

static func _po_append(cur: Dictionary, field: String, s: String) -> void:
	if field == "":
		return
	if field == "strs":
		cur.strs[cur.strs.size() - 1] += s
	else:
		cur[field] = str(cur.get(field, "")) + s

static func _unq(s: String) -> String:
	if s.length() < 2 or not s.begins_with("\"") or not s.ends_with("\""):
		return s
	s = s.substr(1, s.length() - 2)
	var out := ""
	var i := 0
	while i < s.length():
		var c := s.substr(i, 1)
		if c == "\\" and i + 1 < s.length():
			var x := s.substr(i + 1, 1)
			out += {"n": "\n", "t": "\t", "r": "\r", "\"": "\"", "\\": "\\"}.get(x, x)
			i += 2
			continue
		out += c
		i += 1
	return out

static func _q(s: String) -> String:
	return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n") + "\""

## A po field: one line, or "" then one line per \n-ended piece for multi-line text.
static func _field(kw: String, s: String, prefix := "") -> String:
	if not s.contains("\n") or s.split("\n").size() <= 1 or (s.count("\n") == 1 and s.ends_with("\n")):
		return prefix + kw + " " + _q(s) + "\n"
	var out := prefix + kw + " \"\"\n"
	var parts := s.split("\n")
	for k in parts.size():
		var piece := parts[k] + ("\n" if k < parts.size() - 1 else "")
		if piece != "":
			out += prefix + _q(piece) + "\n"
	return out

## The text of one entry. Plural entries keep msgstr[0] / msgstr[1] (Bangla uses the same text for both).
static func entry_text(e: Dictionary, prefix := "") -> String:
	var out := ""
	for c: String in e.get("comments", []):
		out += ("# " + c).strip_edges() + "\n" if c != "" else "#\n"
	for w: String in e.get("wheres", []):
		out += "#. " + w + "\n"
	for n: String in e.get("notes", []):
		out += "#. TRANSLATORS: " + n + "\n"
	var refs: Array = e.get("refs", [])
	if refs.size():
		out += "#: " + " ".join(refs) + "\n"
	var flags: Array = e.get("flags", [])
	if flags.size():
		out += "#, " + ", ".join(flags) + "\n"
	if e.ctx != "":
		out += _field("msgctxt", e.ctx, prefix)
	out += _field("msgid", e.id, prefix)
	if e.plural != "":
		out += _field("msgid_plural", e.plural, prefix)
		var strs: Array = e.get("strs", [])
		if strs.is_empty() and str(e.get("str", "")) != "":
			strs = [e.str, e.str]
		for k in 2:
			out += _field("msgstr[%d]" % k, str(strs[k]) if k < strs.size() else "", prefix)
	else:
		out += _field("msgstr", str(e.get("str", "")), prefix)
	return out

## The Bangla of an entry ("" when untranslated): msgstr, or msgstr[0] for a plural.
static func bn_of(e: Dictionary) -> String:
	if e.get("plural", "") != "":
		var strs: Array = e.get("strs", [])
		return str(strs[0]) if strs.size() and strs.all(func(s) -> bool: return str(s) != "") else ""
	return str(e.get("str", ""))
