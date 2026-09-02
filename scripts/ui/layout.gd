class_name Layout
extends RefCounted

## Where the HUD decides how much room it actually has.
##
## The build shipped with one fixed 1600x900 design and `canvas_items` stretching
## set to `expand`. On a 375-point phone that resolves to a 0.23x scale and a
## 1600x3466 virtual viewport: a microscopic HUD stranded in a column of dead
## space. No uniform scale rescues that — a 12px font at 0.23x is three pixels
## tall — because the design is simply wider than a phone. So the phone gets its
## own layout rather than a shrunken copy of this one.
##
## The compact layout is measured in **CSS pixels**, the same unit the JavaScript
## build's media queries use, and one game unit is one CSS pixel there. That is
## what makes a 12px font arrive as a 12px font instead of a smear, and it means
## the breakpoints below can be read against `css/main.css` directly.
##
## Nothing here is allowed to name an autoload: `Events` is emitted by Main,
## which owns the rebuild.

enum Mode { WIDE, COMPACT }

## Below this many CSS pixels of width, the HUD reflows. The JS build breaks at
## 1080px; this one breaks lower because the Godot HUD has no fixed-width
## sidebars to fit — it collapses them instead.
const COMPACT_WIDTH := 900.0

## The design the wide layout is drawn against, unchanged from before.
const DESIGN := Vector2i(1600, 900)

## A compact layout shorter than this is a phone held sideways: the board has to
## give up room to the furniture rather than the other way round.
const SHORT_HEIGHT := 460.0

static var mode: Mode = Mode.WIDE

## The window in CSS pixels — the compact layout's coordinate space.
static var css_size: Vector2 = Vector2(DESIGN)

## Device pixels per CSS pixel: 1 on a desktop monitor, 2-3 on a phone.
static var pixel_ratio: float = 1.0

## Forces the answer `touch()` gives: -1 asks the display server, 0 is a mouse,
## 1 is a finger. For the tools only.
##
## `short()` turns on this answer now, and a desktop reports no touchscreen — so
## without a way to force it, screenshot.gd could not render a sideways phone at
## all, which is the case the change below exists to describe.
static var touch_override: int = -1

## The last size the window was at while upright, in CSS pixels. A touch device
## turned sideways keeps laying itself out at this, which is what makes the
## rotation a no-op — see `apply`.
static var _upright: Vector2 = Vector2.ZERO

## Whether the browser has been asked to stop rotating the page. Asked once.
static var _lock_tried: bool = false


static func compact() -> bool:
	return mode == Mode.COMPACT


## A short, narrow window driven by a mouse: wide, with barely any height. It
## gets a different shape entirely rather than a tighter version of portrait —
## see Main._build_landscape.
##
## **A touchscreen is excluded on purpose.** Landscape is not supported on a
## phone any more: a device that can be turned gets the portrait arrangement
## whichever way it is held, and the two-column build survives only for a window
## somebody chose to make that shape and can drag back to a sensible one.
static func short() -> bool:
	return mode == Mode.COMPACT and css_size.y < SHORT_HEIGHT and not touch()


## Whether a finger is driving rather than a mouse.
##
## Gated on the device having a touchscreen rather than on the layout being
## compact: a small window on a desktop is still driven by a mouse, and a mouse
## held down for a third of a second should not pop an inspector open.
static func touch() -> bool:
	if touch_override >= 0:
		return touch_override == 1
	return DisplayServer.is_touchscreen_available()


## Sizes the window's content scale for the screen it is actually on, and reports
## whether that changed which layout the HUD should be built as.
##
## Called on every resize, so it must be cheap and must not rebuild anything
## itself — Main owns that decision.
static func apply(window: Window) -> bool:
	var px := Vector2(window.size)
	if px.x < 1.0 or px.y < 1.0:
		return false

	var was_mode := mode
	var was_short := short()

	pixel_ratio = _pixel_ratio()
	var seen := px / pixel_ratio

	# **Turning a phone sideways does nothing.** The game is played upright, so a
	# rotation is not a different layout and not a prompt — it is ignored. The HUD
	# keeps the size it had while upright, and the extra width becomes bars either
	# side rather than something to reflow into, so `mode` and `short()` come out
	# unchanged and Main is told there is nothing to rebuild.
	#
	# `_lock_orientation` is the half that means most players never see the bars:
	# a browser that honours it simply never reports a landscape window. It cannot
	# be relied on — it needs fullscreen, and iOS Safari refuses outright — which
	# is why the layout has to hold the line by itself as well.
	_lock_orientation()
	var sideways := touch() and seen.x > seen.y
	if sideways:
		# Nothing remembered means the page was *loaded* sideways, so there is no
		# upright size to go back to. The same screen turned the other way is it.
		if _upright == Vector2.ZERO:
			_upright = Vector2(seen.y, seen.x)
		css_size = _upright
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	else:
		css_size = seen
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		if seen.y >= seen.x:
			_upright = seen

	mode = Mode.COMPACT if css_size.x < COMPACT_WIDTH else Mode.WIDE

	# Crossing *either* breakpoint is a rebuild. Watching only WIDE/COMPACT meant
	# a phone turned sideways kept its portrait arrangement — two rows of bench, a
	# three-wide shop, the strips stacked — in a window with no height for any of
	# it, because both orientations are "compact".
	var changed := mode != was_mode or short() != was_short

	if mode == Mode.COMPACT:
		# One game unit per CSS pixel. With aspect `expand` the resulting scale is
		# exactly the device pixel ratio, so the HUD is laid out at phone-native
		# sizes and drawn at full device resolution.
		window.content_scale_size = Vector2i(maxi(1, roundi(css_size.x)),
			maxi(1, roundi(css_size.y)))
	else:
		window.content_scale_size = DESIGN

	return changed


## Asks the browser to keep the page upright, once.
##
## This is the real answer to a phone being turned: with the lock honoured the
## window never becomes landscape and nothing downstream has to cope. It throws
## when the page is not fullscreen and iOS Safari does not implement it at all,
## so the promise and the call are both swallowed — a refusal is expected, not an
## error, and `apply` above holds the line either way.
static func _lock_orientation() -> void:
	if _lock_tried or not OS.has_feature("web"):
		return
	_lock_tried = true
	JavaScriptBridge.eval("try{if(screen.orientation&&screen.orientation.lock)"
		+ "screen.orientation.lock('portrait').catch(function(){});}catch(e){}", true)


## Device pixels per CSS pixel.
##
## The browser is the only place this is not 1, and it is the only place that can
## answer it: Godot's window size on the web is in device pixels, so without this
## a phone at 375 CSS pixels looks like a 1125-pixel tablet and gets the wide
## layout at an unreadable third of a size.
static func _pixel_ratio() -> float:
	if OS.has_feature("web"):
		var value: Variant = JavaScriptBridge.eval("window.devicePixelRatio", true)
		if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
			var ratio := float(value)
			if ratio > 0.0:
				return ratio
	var scale := DisplayServer.screen_get_scale()
	return scale if scale > 0.0 else 1.0


# --- sizes that differ between the two layouts -------------------------------
#
# Kept here rather than as literals in each panel so the compact pass is one
# file to read, and so a widget cannot end up compact in one dimension and not
# the other.

## Body text. The compact layout does not shrink it — a phone is held closer, but
## not that much closer, and the JS build settled on the same sizes.
static func font_body() -> int:
	return UITheme.FONT_SMALL if compact() else UITheme.FONT_BODY


static func bench_slot() -> Vector2:
	if short():
		return Vector2(40, 40)
	return Vector2(46, 46) if compact() else Vector2(64, 64)


static func item_chip() -> Vector2:
	if short():
		return Vector2(28, 28)
	return Vector2(30, 30) if compact() else Vector2(36, 36)


## Minimum size of a shop card. The compact one is a *floor*, not a size: five of
## them share whatever width there is, and the height is whatever the name and
## traits need. What matters here is that five minimum widths still fit across a
## narrow phone, or the row overflows the screen.
static func shop_card() -> Vector2:
	if short():
		return Vector2(60, 50)
	return Vector2(60, 62) if compact() else Vector2(126, 92)


## How many shop cards sit on a row: always all five.
##
## Wrapping to three, as the JS build does, costs a whole second row — and on a
## phone that row comes out of the board, which was left at 24% of the screen and
## a 21-point hex. A hex has to be big enough to drop a pirate on.
static func shop_columns() -> int:
	return 5


## How many bench slots sit on a row. Two rows of five keeps every slot
## thumb-sized on a phone; nine across a 375-point screen is a 36-point slot,
## under the smallest comfortable touch target.
##
## Sideways counts as a phone too, even though the screen is wide: there the
## bench is in a column beside the board, not across the bottom.
static func bench_columns() -> int:
	return 5 if compact() else 9


## Gap between the major blocks of the HUD.
static func gap() -> int:
	return 4 if compact() else 8
