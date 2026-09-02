class_name DeckPlate
extends Control

## The planked timber the bench is drawn on.
##
## The bench used to be another blue panel with nine blue holes in it, which said
## nothing about whose pirates those were. This draws the deck they stand on:
## caulked planks running the width, butt joints staggered along them, and two
## nail heads at every joint. Nothing here is an asset — there is no image file in
## this project and there is not going to be one — so it is a few dozen lines and
## some arithmetic, like every pirate on the board.
##
## **It must never take a click.** `Control.mouse_filter` defaults to STOP, so a
## full-panel Control laid under the slots is an invisible sheet over the bench
## that eats every press meant for it: no dragging a pirate out to the board, no
## dropping an item on one, and nothing on screen to say why. That is the Ocean
## rule in a smaller place, and `test_hud.gd` checks it rather than trusting this
## comment.
##
## **It is a plain child, not `show_behind_parent`.** `Ocean` is behind its parent
## because `BoardView` paints the grid in its own `_draw`; the bench's background
## is a `StyleBox`, which a PanelContainer paints *for* itself, so a plate behind
## the parent would be covered by it. Added first instead, and drawn under its
## siblings the ordinary way.
##
## It repaints only when the panel resizes. A rotation or a rebuild is a handful
## of draw calls; a still window is none.

## Plank depth. A phone gets shallower ones so the deck still reads as several
## boards rather than as two, in a panel less than half the height.
const PLANK_DEPTH := 15.0
const PLANK_DEPTH_COMPACT := 10.0

## Grain lines and nail heads stop below this panel height, the same trade
## `Pose.detail` makes on the board: at a 40-point bench slot each of them is one
## indistinct pixel, drawn a few hundred times, on the device least able to
## afford it.
const DETAIL_HEIGHT := 56.0


func _ready() -> void:
	# The one line this class exists to guarantee.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return

	var depth := PLANK_DEPTH_COMPACT if Layout.compact() else PLANK_DEPTH
	var detail := size.y >= DETAIL_HEIGHT
	var planks := maxi(2, int(ceil(size.y / depth)))
	depth = size.y / float(planks)

	draw_rect(Rect2(Vector2.ZERO, size), UITheme.DECK_TIMBER)

	for i in planks:
		var top := i * depth
		var tone := _scatter(i * 7 + 1)
		draw_rect(Rect2(0.0, top, size.x, depth),
			UITheme.DECK_TIMBER.lerp(UITheme.DECK_TIMBER_LIT, 0.15 + tone * 0.55))

		if detail:
			# Two grain lines per plank, at their own depths, so no two boards
			# come out looking like the same board twice.
			for g in 2:
				var at := top + depth * (0.24 + 0.42 * _scatter(i * 13 + g * 5))
				draw_line(Vector2(0.0, at), Vector2(size.x, at),
					Color(UITheme.DECK_GRAIN, 0.35), 1.0)

		# The caulking between this plank and the next.
		var seam := top + depth
		if i < planks - 1:
			draw_line(Vector2(0.0, seam), Vector2(size.x, seam), UITheme.DECK_SEAM, 1.0)

		_draw_joints(i, top, depth, detail)

	# The gunwale: the deck sits inside a rail, lit along the top edge and dark
	# along the bottom, which is what stops it reading as a flat brown rectangle.
	draw_line(Vector2.ZERO, Vector2(size.x, 0.0), Color(UITheme.DECK_NAIL, 0.5), 1.0)
	draw_line(Vector2(0.0, size.y - 1.0), Vector2(size.x, size.y - 1.0),
		Color(UITheme.DECK_SEAM, 0.8), 1.0)


## The vertical joints where one board ends and the next begins, staggered along
## the plank so they never line up into a grid, with a nail either side.
func _draw_joints(plank: int, top: float, depth: float, detail: bool) -> void:
	var span := maxi(1, int(size.x / 150.0) + 1)
	for j in span:
		var at := size.x * (float(j) + 0.15 + 0.7 * _scatter(plank * 31 + j * 3)) / float(span)
		if at < 6.0 or at > size.x - 6.0:
			continue
		draw_line(Vector2(at, top + 1.0), Vector2(at, top + depth - 1.0),
			Color(UITheme.DECK_SEAM, 0.7), 1.0)
		if detail:
			# Dim: at full strength two dots beside a seam read as grit on the
			# lens rather than as ironwork.
			var mid := top + depth * 0.5
			draw_circle(Vector2(at - 3.0, mid), 0.9, Color(UITheme.DECK_NAIL, 0.45))
			draw_circle(Vector2(at + 3.0, mid), 0.9, Color(UITheme.DECK_NAIL, 0.45))


## A repeatable number in 0..1 for an index.
##
## Deliberately not `randf()`: the plate repaints on every resize, and a deck
## whose grain reshuffles each time the window is dragged reads as static rather
## than as timber.
func _scatter(seed_value: int) -> float:
	var n := sin(float(seed_value) * 12.9898) * 43758.5453
	return n - floor(n)
