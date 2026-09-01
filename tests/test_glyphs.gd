extends TestCase

## Every character the game can print has to be one the *web export* can draw.
##
## There are no system fonts in a WASM sandbox. On Windows a missing glyph is
## quietly filled in by Segoe UI and nothing looks wrong; in the browser the font
## chain is Godot's own bundled fallback plus the one font this project ships —
## Noto Color Emoji — and anything in neither renders as a tofu box. That is how
## every price and every star rating shipped as a square: the symbols were chosen
## on Windows and checked nowhere else.
##
## The project rule was "check any new symbol in the web export", which means
## exporting and looking. This asks the fonts instead, so a symbol that cannot be
## drawn fails here rather than in a browser.
##
## What it does *not* catch: a glyph the fonts have but render badly, and text
## built entirely at runtime from something other than a literal. It catches the
## failure that has actually happened twice.

const EMOJI_FONT_PATH := "res://fonts/NotoColorEmoji.ttf"

## Zero-width characters that shape a neighbouring glyph rather than drawing one
## of their own. A variation selector or a zero-width joiner is never in a cmap
## and never needs to be: `⚔️` is U+2694 followed by U+FE0F, and it is the pair
## that Noto Color Emoji maps to the coloured sword.
const NON_PRINTING := [0x200D, 0xFE0E, 0xFE0F]


func test_every_printed_character_is_drawable() -> void:
	var fonts: Array[Font] = [ThemeDB.fallback_font, load(EMOJI_FONT_PATH)]
	assert_not_null(fonts[1], "the emoji font is missing from the project")

	var missing := PackedStringArray()
	var checked := 0
	for c in _printable_characters():
		var code := c.unicode_at(0)
		if NON_PRINTING.has(code):
			continue
		checked += 1
		var covered := false
		for font in fonts:
			if font != null and font.has_char(code):
				covered = true
				break
		if not covered:
			missing.append("U+%04X (%s)" % [code, c])

	assert_gt(checked, 0, "found nothing to check — has the source moved?")
	assert_true(missing.is_empty(),
		"the web export cannot draw: %s. Pick a character Noto Color Emoji covers "
		% ", ".join(missing) + "(see UITheme.COIN and UITheme.STAR for the pattern)")


## Every distinct non-ASCII character the HUD could print: the string literals in
## the scripts, and the icons and names in the authored resources.
func _printable_characters() -> PackedStringArray:
	var out := PackedStringArray()
	for path in _files("res://scripts", ".gd"):
		_collect(_literal_characters(FileAccess.get_file_as_string(path)), out)
	for path in _files("res://data", ".tres"):
		_collect(_non_ascii(FileAccess.get_file_as_string(path)), out)
	return out


func _collect(from: PackedStringArray, into: PackedStringArray) -> void:
	for c in from:
		if not into.has(c):
			into.append(c)


## Characters inside double-quoted strings only.
##
## Comments are skipped on purpose: UITheme names the two characters this test
## exists to keep out of the UI, in a comment explaining why they are banned.
func _literal_characters(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var in_string := false
	var in_comment := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if in_comment:
			if c == "\n":
				in_comment = false
		elif in_string:
			if c == "\\":
				i += 1                    # an escape, never a quote of its own
			elif c == "\"":
				in_string = false
			elif c.unicode_at(0) > 0x7F:
				out.append(c)
		elif c == "#":
			in_comment = true
		elif c == "\"":
			in_string = true
		i += 1
	return out


func _non_ascii(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for i in text.length():
		if text[i].unicode_at(0) > 0x7F:
			out.append(text[i])
	return out


func _files(root: String, suffix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for name in DirAccess.get_files_at(root):
		if name.ends_with(suffix):
			out.append(root.path_join(name))
	for name in DirAccess.get_directories_at(root):
		out.append_array(_files(root.path_join(name), suffix))
	return out
