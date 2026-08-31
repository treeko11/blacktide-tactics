class_name UITheme
extends RefCounted

## The palette and the small widget factories, in one place.
##
## Ported from the old build's CSS custom properties so the game still looks like
## itself. Everything that draws reads from here rather than carrying its own
## colour literals, because "the gold used in four places drifted into four
## slightly different golds" is the failure mode of a hand-themed UI.

const BG := Color("050b11")
const BG_2 := Color("08131c")
const PANEL := Color("0c1922")
const PANEL_2 := Color("102532")
const LINE := Color("1d3b4e")
const LINE_2 := Color("2b5a75")

const INK := Color("dce8f0")
const MUTED := Color("7c93a4")
const GOLD := Color("e8b44a")
const GOLD_BRIGHT := Color("ffd98a")
const SEA := Color("2f8fbb")
const FOAM := Color("7fe3ff")
const BLOOD := Color("c8394a")
const GOOD := Color("4bd08a")

## Health bar colours, ours and theirs.
const HP_MINE := Color("5fe08a")
const HP_THEIRS := Color("ff7d7d")
const MANA := Color("7fd8ff")
const SHIELD := Color("cfe9ff")

## Board.
const HEX_MINE := Color("0f2d3f")
const HEX_ENEMY := Color("141d28")
const HEX_DROP := Color("1f5a76")
const HEX_EDGE := Color("18384a")

## Damage number colours.
const DMG_PHYSICAL := Color("ffffff")
const DMG_MAGIC := Color("c9a2ff")
const DMG_TRUE := Color("ffd27a")
const DMG_CRIT := Color("ff9d5c")
const HEAL := Color("7dffb0")
const MISS := Color("9fb8c8")
const PROC := Color("ffe9a8")

## Warning colour for the shop clock as it runs out.
const WARNING := Color("ff8a5c")

const FONT_TINY := 10
const FONT_SMALL := 12
const FONT_BODY := 14
const FONT_TITLE := 18
const FONT_HUGE := 34


# --- fonts -------------------------------------------------------------------

static var _emoji_font: Font = null
static var _ui_font: Font = null


## A font that can actually draw the champion and item icons.
##
## Every pirate, monster and item is identified by an emoji, carried straight
## over from the web build, so this is not decoration — without it the entire
## roster is blank boxes.
##
## **It is bundled rather than asked for from the system.** A `SystemFont` naming
## "Segoe UI Emoji" works on Windows and produces nothing at all in the web
## export, which runs in a WASM sandbox with no system fonts: every unit, item
## and trait rendered as tofu. Shipping the font also means a Mac player sees the
## same icons as a Windows one instead of Apple's completely different set.
##
## Noto Color Emoji is SIL Open Font License 1.1 — see fonts/LICENSE-*.txt.
## The project's MSDF font rendering is off because it cannot represent colour
## glyphs.
const EMOJI_FONT_PATH := "res://fonts/NotoColorEmoji.ttf"

static func emoji_font() -> Font:
	if _emoji_font == null:
		if ResourceLoader.exists(EMOJI_FONT_PATH):
			_emoji_font = load(EMOJI_FONT_PATH)
		else:
			# Only reachable if the font is missing from the project; better a
			# system font than nothing, even though the web build has none.
			push_warning("UITheme: %s is missing, falling back to a system font"
				% EMOJI_FONT_PATH)
			var font := SystemFont.new()
			font.font_names = PackedStringArray([
				"Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji",
			])
			font.allow_system_fallback = true
			_emoji_font = font
	return _emoji_font


static func ui_font() -> Font:
	if _ui_font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Arial"])
		font.allow_system_fallback = true
		_ui_font = font
	return _ui_font


## Border colour for a champion of a given cost.
static func cost_color(cost: int) -> Color:
	match cost:
		0: return Color("6b7a86")
		1: return Color("9aa7b4")
		2: return Color("3fbf7f")
		3: return Color("4a9dff")
		4: return Color("c46bff")
		5: return Color("ffb32e")
	return Color("9aa7b4")


## Badge colour for a trait at a tier: bronze, silver, gold, prismatic.
static func tier_color(style: StringName) -> Color:
	match style:
		&"bronze": return Color("8a5a26")
		&"silver": return Color("93a8b6")
		&"gold": return GOLD
		&"prism": return Color("9fe8ff")
	return Color("20404f")


static func log_color(style: StringName) -> Color:
	match style:
		&"good": return Color("a8e0c2")
		&"bad": return Color("e8a8b0")
	return MUTED


# --- widget factories --------------------------------------------------------

## A panel background in the game's style.
static func panel_style(fill: Color = PANEL, border: Color = LINE,
		radius: int = 6) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


static func label(text: String, size: int = FONT_BODY, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	return node


## A section heading: small, spaced, muted.
static func heading(text: String) -> Label:
	var node := label(text.to_upper(), FONT_TINY, MUTED)
	node.add_theme_constant_override("line_spacing", 2)
	return node


static func button(text: String, size: int = FONT_SMALL) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_stylebox_override("normal", panel_style(PANEL_2, LINE, 5))
	node.add_theme_stylebox_override("hover", panel_style(Color("17415a"), FOAM, 5))
	node.add_theme_stylebox_override("pressed", panel_style(Color("0a1c26"), FOAM, 5))
	node.add_theme_stylebox_override("disabled", panel_style(Color("0a141b"), Color("15242e"), 5))
	node.add_theme_color_override("font_disabled_color", Color("41525e"))
	return node


static func spacer(minimum: float = 0.0) -> Control:
	var node := Control.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.custom_minimum_size = Vector2(minimum, 0)
	return node
