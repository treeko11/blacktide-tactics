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

var units_root: Node2D = null
var fx: FxLayer = null

var _views: Dictionary = {}      ## uid -> UnitView
var _sim: Sim = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

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
	queue_redraw()


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
		return false

	set_drop_cell(cell)
	if data["kind"] == &"unit":
		return true

	if data["kind"] == &"item":
		var unit := GameState.unit_at(cell)
		if unit == null:
			preview_changed.emit("Drop on a pirate")
			return false
		var preview: Dictionary = GameState.preview_equip(data["id"], unit)
		preview_changed.emit(_describe_drop(preview, data["id"], unit))
		return preview.get("allowed", false)

	return false


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


# --- the grid ----------------------------------------------------------------

func _draw() -> void:
	draw_set_transform(board_offset, 0.0, Vector2.ONE * board_scale)
	for row in Hex.ROWS:
		for col in Hex.COLS:
			_draw_cell(Vector2i(col, row))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_cell(cell: Vector2i) -> void:
	var centre := Hex.to_pixel(cell)
	var points := _hex_points(centre, Hex.HEX_H * 0.5 - 1.5)

	var fill := UITheme.HEX_MINE if Hex.is_player_half(cell) else UITheme.HEX_ENEMY
	if cell == drop_cell:
		fill = UITheme.HEX_DROP
	elif cell == hover_cell and Hex.is_player_half(cell):
		fill = fill.lerp(UITheme.HEX_DROP, 0.45)

	draw_colored_polygon(points, fill)
	draw_polyline(_closed(points), UITheme.HEX_EDGE, 1.0)

	# A brighter rim on the halfway line, so the two halves read as two fleets.
	if cell.y == Hex.PLAYER_ROW_MIN:
		draw_line(points[4], points[5], Color(UITheme.LINE_2.r, UITheme.LINE_2.g,
			UITheme.LINE_2.b, 0.5), 1.5)


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
