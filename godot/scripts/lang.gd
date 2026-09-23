# Player-facing language. English is the source language: every text in the code is English and
# res://locale/de.po carries the German translation (msgid English, msgstr German). The autoload
# `Language` installs one Catalogue per language before anything else runs and picks the saved
# language (English unless the player chose German in the settings, never the Windows locale).
#
# Three ways text reaches the screen:
# - A plain English literal on a Label, Button, RichTextLabel, Label3D, tooltip or OptionButton item.
#   Godot translates it on its own (auto-translate) and again whenever the language changes.
# - Lang.t(msgid, args) for anything built from pieces. It returns a portable segment that stays
#   language neutral until it is shown, so a message the co-op host builds for a client appears in
#   the client's language, and a label holding it re-translates live. Segments may be concatenated
#   with other text and nested as arguments; string arguments are translated too (weapon names...),
#   Lang.raw() keeps one as it is (player names).
# - Lang.text(value) resolves literals and segments into the current language for places Godot does
#   not translate by itself: draw_string, RenderingServer text, logic that needs the final wording.
class_name Lang
extends Node

const LANGUAGES := {"en": "English", "de": "Deutsch"}
const DEFAULT := "en"
const CATALOGUES := {"de": "res://locale/de.po"}
const SETTINGS := "user://settings.cfg"
# Segment framing: start, argument separator, end. Unicode noncharacters are reserved for internal use and
# never occur in real text, and Godot keeps them (a tooltip strips everything up to U+0020 from both ends,
# which is why control characters did not survive there). The arguments travel as base64, so a nested
# segment can never break the frame of the one around it.
const OPEN := "\uFDD0"
const SEP := "\uFDD1"
const CLOSE := "\uFDD2"

static var current := DEFAULT
static var _catalogues: Dictionary = {}
static var _closed := false

func _init() -> void:
	install()

# Registers the catalogues and applies the saved language. Safe to call more than once; scripts that run
# without the autoload (--script tools) get it lazily through t() / text().
static func install() -> void:
	if not _catalogues.is_empty() or _closed:
		return
	for code: String in LANGUAGES:
		var catalogue := Catalogue.new()
		catalogue.locale = code
		if CATALOGUES.has(code):
			var messages = load(CATALOGUES[code]) if ResourceLoader.exists(CATALOGUES[code]) else null
			if messages is Translation:
				catalogue.po = messages
			else:
				push_error("Language catalogue missing: " + CATALOGUES[code])
		_catalogues[code] = catalogue
		TranslationServer.add_translation(catalogue)
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root and not tree.root.tree_exiting.is_connected(uninstall):
		tree.root.tree_exiting.connect(uninstall)
	set_language(_startup_language())

# The catalogues are script objects: they have to leave the TranslationServer while scripting still runs.
# Freed later, together with the server, they took the engine down on exit.
static func uninstall() -> void:
	_closed = true
	for catalogue: Catalogue in _catalogues.values():
		TranslationServer.remove_translation(catalogue)
	_catalogues.clear()

static func set_language(code: String) -> void:
	if not LANGUAGES.has(code):
		code = DEFAULT
	current = code
	TranslationServer.set_locale(code)

# Tests and benchmarks always run in English unless they ask for a language with --lang=xx; the
# game itself uses what the settings saved and English when nothing was saved.
static func _startup_language() -> String:
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--lang="):
			return arg.trim_prefix("--lang=")
	for arg in args:
		if arg in ["--autotest", "--benchmark", "--smoke-test"] or arg.begins_with("--suite="):
			return DEFAULT
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS) == OK:
		return str(cfg.get_value("game", "language", DEFAULT))
	return DEFAULT

# Portable text: msgid is the English wording, args fill its %d / %s / %.1f slots.
static func t(msgid: String, args: Array = []) -> String:
	if _catalogues.is_empty():
		install()
	if msgid.is_empty() or (args.is_empty() and msgid.contains(OPEN)):
		return msgid
	if args.is_empty():
		return OPEN + msgid + CLOSE
	return OPEN + msgid + SEP + Marshalls.raw_to_base64(var_to_bytes(args)) + CLOSE

# An argument for t() that is shown exactly as given (player names, typed input).
static func raw(value: Variant) -> Dictionary:
	return {"raw": str(value)}

# Literal or segment(s) in the current language.
static func text(value: String) -> String:
	return resolve(value, current)

static func resolve(value: String, code: String = current) -> String:
	if _catalogues.is_empty():
		install()
	if _catalogues.is_empty():
		return value
	var catalogue: Catalogue = _catalogues.get(code, _catalogues[DEFAULT])
	if value.contains(OPEN):
		return catalogue.expand(value)
	return catalogue.lookup(value)

# Language names are always written in their own language, so a player can find theirs.
static func language_names() -> Array:
	return LANGUAGES.values()

static func language_codes() -> Array:
	return LANGUAGES.keys()


# One language as the TranslationServer sees it: plain English msgids come from the PO file (German) or
# stay as they are (English); segments are unpacked, their arguments translated and formatted.
class Catalogue extends Translation:
	var po: Translation   # the loaded de.po, null for English

	func _get_message(src_message: StringName, context: StringName) -> StringName:
		var value := String(src_message)
		if value.contains(Lang.OPEN):
			return StringName(expand(value))
		if po:
			return po.get_message(src_message, context)
		return &""

	func lookup(msgid: String) -> String:
		if po and not msgid.is_empty():
			var found := String(po.get_message(msgid))
			if not found.is_empty():
				return found
		return msgid

	func expand(value: String) -> String:
		var out := ""
		var at := 0
		while true:
			var start := value.find(Lang.OPEN, at)
			var stop := value.find(Lang.CLOSE, start + 1) if start >= 0 else -1
			if start < 0 or stop < 0:
				out += value.substr(at)
				break
			out += value.substr(at, start - at)
			out += _segment(value.substr(start + 1, stop - start - 1))
			at = stop + 1
		return out

	func _segment(body: String) -> String:
		var cut := body.find(Lang.SEP)
		if cut < 0:
			return lookup(body)
		var msgid := body.substr(0, cut)
		var args = bytes_to_var(Marshalls.base64_to_raw(body.substr(cut + 1)))
		if not args is Array:
			return lookup(msgid)
		var values: Array = []
		for arg in args:
			if arg is String:
				values.append(expand(arg) if arg.contains(Lang.OPEN) else lookup(arg))
			elif arg is Dictionary and arg.has("raw"):
				values.append(str(arg["raw"]))
			else:
				values.append(arg)
		var pattern := lookup(msgid)
		if _slots(pattern) == values.size():
			return pattern % values
		if _slots(msgid) == values.size():
			return msgid % values
		return msgid

	# Number of % placeholders; %% is a literal percent sign.
	static func _slots(pattern: String) -> int:
		var count := 0
		var at := pattern.find("%")
		while at >= 0:
			if pattern.substr(at + 1, 1) == "%":
				at = pattern.find("%", at + 2)
				continue
			count += 1
			at = pattern.find("%", at + 1)
		return count
