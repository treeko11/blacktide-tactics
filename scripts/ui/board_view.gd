class_name BoardView
extends Control

## The hex board: the grid, the pirates standing on it, and the effects layer.
##
## Draws the grid itself and scales the whole thing to whatever space the layout
## gives it, so the board is the one part of the HUD that adapts to the window
## rather than the other way round.
##
## It reports what is under the cursor and highlights a drop target, but it does
## not move anything — dragging is owned by Main, which is the only place allowed
## to ask GameState to change the roster.

signal unit_dropped_on_cell(unit: RosterUnit, cell: Vector2i)
signal item_dropped_on_unit(item_id: StringName, unit: RosterUnit)
signal unit_sell_requested(unit: RosterUnit)
signal preview_changed(text: String)
## What the item being dragged would forge with, and where to anchor the answer.
## `forge_preview_cleared` is the other half: nothing under the cursor pairs any
## more, so the inspector describing a forge that is no longer on offer goes.
signal forge_previewed(item_id: StringName, with_id: StringName, unit: RosterUnit,
	at: Vector2, source: Control)
signal forge_preview_cleared()
signal unit_hovered(unit: RosterUnit, at: Vector2)
signal sim_unit_hovered(unit: SimUnit, at: Vector2)
signal unit_unhovered()

## Space kept around the board when fitting it to the panel.
const MARGIN := 12.0
const MAX_SCALE := 1.25

var board_scale: float = 1.0
var board_offset: Vector2 = Vector2.ZERO

## Cell currently highlighted as a drop target, or (-1, -1).
var drop_cell: Vector2i = Vector2i(-1, -1)
## Cell the cursor is over, highlighted more softly.
var hover_cell: Vector2i = Vector2i(-1, -1)

## The hexes this round's sea is going to touch, keyed by `Hex.key` so the draw
## loop is a lookup rather than a scan of an array eight rows deep.
##
## Marked during planning as well as during the fight, which is the entire point
## of the system: a lane that only lights up once the waves start arriving is a
## dice roll, not a decision. Set by Main from `Events.sea_changed` and re-read
## on a rebuild, because a panel built mid-run starts at its own defaults and
## the signal has already fired at a panel that no longer exists.
var sea_cells: Dictionary = {}
var sea_color: Color = UITheme.FOAM
var sea_boon: bool = false

var units_root: Node2D = null
var fx: FxLayer = null

var _views: Dictionary = {}      ## uid -> UnitView
var _sim: Sim = null

## Seconds, for the foam lapping at the hex edges.
var _clock: float = 0.0
var _foam_accum: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	# Behind everything, including this control's own `_draw`. Added first so it
	# is also first in the tree, which is what the sea being the sea depends on.
	var ocean := Ocean.new()
	ocean.name = "Ocean"
	add_child(ocean)

	units_root = Node2D.new()
	units_root.name = "Units"
	add_child(units_root)

	fx = FxLayer.new()
	fx.name = "Fx"
	fx.position_resolver = _live_position
	add_child(fx)

	resized.connect(_fit)
	_fit()


func _fit() -> void:
	var board := Hex.board_size()
	var usable := size - Vector2(MARGIN, MARGIN) * 2.0
	board_scale = minf(MAX_SCALE, minf(usable.x / board.x, usable.y / board.y))
	# The floor only guards against a degenerate zero while the layout settles.
	# It used to be 0.3, which on a sideways phone was larger than the space the
	# board had been given: the grid was drawn at 0.3 and clipped, and the back
	# rows could not be reached at all. A board too small to play is still better
	# than a board with rows missing, and no layout should reach either.
	board_scale = maxf(0.12, board_scale)
	board_offset = (size - board * board_scale) * 0.5

	var transform_scale := Vector2.ONE * board_scale
	units_root.position = board_offset
	units_root.scale = transform_scale
	fx.position = board_offset
	fx.scale = transform_scale
	for uid in _views:
		var view: UnitView = _views[uid]
		view.detail = _detail()
	queue_redraw()


## How much of a figure's trim is worth drawing at the scale the board ended up
## at. A phone gives the board a 43-point hex at best and a 21-point one in a
## landscape column; a belt buckle and a row of teeth are draw calls producing
## one indistinct pixel each, eighteen times over, on the device least able to
## afford them.
func _detail() -> float:
	return clampf(board_scale / 0.85, 0.0, 1.0)


# --- coordinates -------------------------------------------------------------

## Board-space position for a point in this control's local space.
func to_board(local: Vector2) -> Vector2:
	return (local - board_offset) / board_scale


## The cell under a point in this control's local space, or (-1, -1).
func cell_at(local: Vector2) -> Vector2i:
	var board_point := to_board(local)
	var cell := Hex.from_pixel(board_point)
	# from_pixel returns the *nearest* cell, which off the edge of the board is
	# still a real cell. Reject anything the cursor is not actually inside.
	if board_point.distance_to(Hex.to_pixel(cell)) > Hex.HEX_H * 0.55:
		return Vector2i(-1, -1)
	return cell


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := cell_at(event.position)
		if cell != hover_cell:
			hover_cell = cell
			queue_redraw()
		_report_hover(event.position)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var unit := roster_unit_at(event.position)
			if unit != null:
				unit_sell_requested.emit(unit)


## Announces whatever the cursor is over, so the inspector can follow it. During
## a fight that is a live SimUnit — the one place item and trait effects are
## actually visible as numbers.
func _report_hover(local: Vector2) -> void:
	var at := global_position + local
	if _sim != null:
		var live := sim_unit_at(local)
		if live != null:
			sim_unit_hovered.emit(live, at)
		else:
			unit_unhovered.emit()
		return
	var unit := roster_unit_at(local)
	if unit != null:
		unit_hovered.emit(unit, at)
	else:
		unit_unhovered.emit()


## The player's fielded unit under a point, between fights.
func roster_unit_at(local: Vector2) -> RosterUnit:
	var cell := cell_at(local)
	if cell.x < 0:
		return null
	return GameState.unit_at(cell)


# --- drag and drop -----------------------------------------------------------
#
# The board reports and highlights; Main is the only thing that asks GameState to
# change anything, so a dropped unit is a signal rather than a mutation here.

func _get_drag_data(at: Vector2) -> Variant:
	if GameState.phase != GameState.Phase.PLAN:
		return null
	var unit := roster_unit_at(at)
	if unit == null:
		return null

	var preview := UnitView.new()
	preview.bind_roster(unit)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(64, 64)
	holder.add_child(preview)
	preview.position = Vector2(32, 32)
	set_drag_preview(holder)
	return { "kind": &"unit", "unit": unit }


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or GameState.phase != GameState.Phase.PLAN:
		return false
	var cell := cell_at(at)
	if cell.x < 0 or not Hex.is_player_half(cell):
		set_drop_cell(Vector2i(-1, -1))
		# Water, or the half of the board that is not yours. Nothing here pairs
		# with what is being carried, and the cursor has not left the board, so
		# nothing else is going to take the forge preview down.
		forge_preview_cleared.emit()
		return false

	set_drop_cell(cell)
	if data["kind"] == &"unit":
		return true

	if data["kind"] == &"item":
		var unit := GameState.unit_at(cell)
		if unit == null:
			preview_changed.emit("Drop on a pirate")
			forge_preview_cleared.emit()
			return false
		var preview: Dictionary = GameState.preview_equip(data["id"], unit)
		preview_changed.emit(_describe_drop(preview, data["id"], unit))
		_report_forge(preview, data["id"], unit, global_position + at)
		return preview.get("allowed", false)

	return false


## Puts the forged item's own inspector up while the cursor is over the pirate
## carrying the other half, and takes it down again over a pirate that is not.
##
## The line under the board names the result; this is the rest of the answer —
## what the thing it names actually does — which is the part somebody deciding
## whether to weld two components together is short of.
func _report_forge(preview: Dictionary, item_id: StringName, unit: RosterUnit,
		at: Vector2) -> void:
	var forged: StringName = preview.get("forges", &"")
	if forged == &"":
		forge_preview_cleared.emit()
		return
	forge_previewed.emit(item_id, preview["with"], unit, at, self)


## Names the outcome before the drop. Equipping cannot be undone, and welding a
## component onto the wrong pirate costs the rest of the run.
func _describe_drop(preview: Dictionary, item_id: StringName, unit: RosterUnit) -> String:
	if not preview.get("allowed", false):
		return preview.get("reason", "")
	var forged: StringName = preview.get("forges", &"")
	if forged != &"":
		var made: ItemDef = GameState.content.item_def(forged)
		return "Forges %s %s on %s" % [made.icon, made.display_name,
			unit.champion.display_name]
	var item: ItemDef = GameState.content.item_def(item_id)
	return "Give %s to %s" % [item.display_name, unit.champion.display_name]


func _drop_data(at: Vector2, data: Variant) -> void:
	var cell := cell_at(at)
	set_drop_cell(Vector2i(-1, -1))
	preview_changed.emit("")
	forge_preview_cleared.emit()
	if cell.x < 0:
		return
	if data["kind"] == &"unit":
		unit_dropped_on_cell.emit(data["unit"], cell)
	elif data["kind"] == &"item":
		var unit := GameState.unit_at(cell)
		if unit != null:
			item_dropped_on_unit.emit(data["id"], unit)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hover_cell = Vector2i(-1, -1)
		unit_unhovered.emit()
		queue_redraw()
	elif what == NOTIFICATION_DRAG_END:
		set_drop_cell(Vector2i(-1, -1))
		preview_changed.emit("")
		forge_preview_cleared.emit()


# --- the grid ----------------------------------------------------------------

## How often the grid is repainted for the foam alone.
##
## The water itself is a shader and animates without anybody redrawing anything;
## this is only the foam breaking along the hex rims, which has to be drawn in
## board space and therefore costs a repaint of fifty-six outlines. Fifteen times
## a second is enough for a lap and a fraction of the cost of matching the
## monitor. Anything the player *does* — a hover, a drop target — still redraws
## the instant it changes, because those call `queue_redraw` themselves.
const FOAM_FRAME := 1.0 / 15.0


func _process(delta: float) -> void:
	_clock += delta
	_foam_accum += delta
	if _foam_accum >= FOAM_FRAME:
		_foam_accum = 0.0
		queue_redraw()


func _draw() -> void:
	draw_set_transform(board_offset, 0.0, Vector2.ONE * board_scale)
	for row in Hex.ROWS:
		for col in Hex.COLS:
			_draw_cell(Vector2i(col, row))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_cell(cell: Vector2i) -> void:
	var centre := Hex.to_pixel(cell)
	var points := _hex_points(centre, Hex.HEX_H * 0.5 - 1.5)

	# Translucent, so the sea underneath shows through and a crest visibly runs
	# across the grid. The two halves are two depths of the same water rather
	# than two colours: your half is lit and shallow, theirs is dark and deep.
	var fill := UITheme.HEX_WATER_MINE if Hex.is_player_half(cell) 		else UITheme.HEX_WATER_ENEMY
	if cell == drop_cell:
		fill = UITheme.HEX_DROP
	elif cell == hover_cell and Hex.is_player_half(cell):
		fill = fill.lerp(UITheme.HEX_DROP, 0.5)

	draw_colored_polygon(points, fill)

	# The weather, over the water and under everything else.
	if sea_cells.has(Hex.key(cell)):
		_draw_sea_mark(points, cell)

	# Foam lapping the rim, out of phase cell by cell so it travels across the
	# board instead of the whole grid pulsing at once.
	var phase: float = float(cell.x * 3 + cell.y * 5)
	var lap: float = 0.5 + 0.5 * sin(_clock * 1.6 + phase)
	draw_polyline(_closed(points), UITheme.HEX_EDGE, 1.0)
	draw_polyline(_closed(points),
		Color(UITheme.FOAM.r, UITheme.FOAM.g, UITheme.FOAM.b, 0.05 + lap * 0.11), 1.0)

	# A brighter rim on the halfway line, so the two halves read as two fleets.
	if cell.y == Hex.PLAYER_ROW_MIN:
		draw_line(points[4], points[5], Color(UITheme.LINE_2.r, UITheme.LINE_2.g,
			UITheme.LINE_2.b, 0.5), 1.5)


## A hex this round's sea will reach.
##
## It breathes rather than sitting still, and the phase runs along the lane so
## the mark reads as water moving through it rather than as a highlighted
## region. A boon pulses from the inside out and a hazard burns at the rim,
## because "stand here" and "do not stand here" cannot look the same at a
## glance — and on a phone a glance is all this gets.
func _draw_sea_mark(points: PackedVector2Array, cell: Vector2i) -> void:
	var phase := float(cell.x * 2 + cell.y * 4)
	var pulse: float = 0.5 + 0.5 * sin(_clock * 2.2 - phase * 0.5)

	if sea_boon:
		draw_colored_polygon(points, Color(sea_color, 0.14 + pulse * 0.16))
		draw_polyline(_closed(points), Color(sea_color, 0.45), 1.5)
	else:
		draw_colored_polygon(points, Color(sea_color, 0.12 + pulse * 0.14))
		draw_polyline(_closed(points), Color(sea_color, 0.35 + pulse * 0.45), 2.0)


## Pointy-top hexagon: a vertex straight up, flats on the left and right.
func _hex_points(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(-90.0 + 60.0 * i)
		points.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	out.append(points[0])
	return out


## Tells the board what this round's sea is touching.
##
## A null def, or one that marks nothing, clears the board — fog is the whole
## ocean and has no lane to point at, so marking every hex would say "everywhere
## is dangerous", which is the same as saying nothing while costing fifty-six
## extra polygons a frame.
func show_sea(def: SeaDef, cells: Array[Vector2i]) -> void:
	sea_cells.clear()
	if def != null and def.marks_cells:
		for cell in cells:
			sea_cells[Hex.key(cell)] = true
		sea_color = def.mark_color
		sea_boon = def.boon
	queue_redraw()


# --- units -------------------------------------------------------------------

func clear_units() -> void:
	UITheme.clear_children(units_root)
	_views.clear()
	_sim = null


## Shows the player's fielded roster, between fights.
func show_roster(board: Array[RosterUnit]) -> void:
	clear_units()
	for unit in board:
		var view := UnitView.new()
		view.detail = _detail()
		units_root.add_child(view)
		view.bind_roster(unit)
		view.position = Hex.to_pixel(unit.cell)
		_views[unit.uid] = view


## Swaps to the live fight, showing both fleets.
func show_battle(sim: Sim) -> void:
	clear_units()
	_sim = sim
	fx.clear()
	for unit in sim.units:
		var view := UnitView.new()
		view.detail = _detail()
		units_root.add_child(view)
		view.bind_sim(unit)
		view.position = unit.pos
		_views[unit.uid] = view


## Called each frame during a fight: moves the views and drains the effects the
## sim queued up since the last frame.
func follow_battle(speed: float) -> void:
	if _sim == null:
		return
	fx.speed = speed
	for uid in _views:
		var view: UnitView = _views[uid]
		# The figures animate at battle speed for the same reason the effects do:
		# a swing that takes a quarter of a second at 4x has to take a quarter of
		# a *battle* second, or every unit is still winding up when it dies.
		view.anim_speed = speed
		view.follow_sim()
	for entry in _sim.fx_queue:
		fx.add_effect(entry)
	_sim.fx_queue.clear()


## Where a unit is right now, for effects that need to follow a moving target.
## Returns null once the fight is over or the unit is gone.
func _live_position(uid: int) -> Variant:
	if _sim == null:
		return null
	for unit in _sim.units:
		if unit.uid == uid:
			return unit.pos
	return null


## The SimUnit under a point, for inspecting a pirate mid-fight.
func sim_unit_at(local: Vector2) -> SimUnit:
	if _sim == null:
		return null
	var board_point := to_board(local)
	var closest: SimUnit = null
	var closest_distance := UnitView.BODY_RADIUS + 6.0
	for unit in _sim.units:
		if not unit.alive:
			continue
		var distance := board_point.distance_to(unit.pos)
		if distance < closest_distance:
			closest_distance = distance
			closest = unit
	return closest


func set_drop_cell(cell: Vector2i) -> void:
	if cell == drop_cell:
		return
	drop_cell = cell
	queue_redraw()
