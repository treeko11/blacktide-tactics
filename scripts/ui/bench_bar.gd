class_name BenchBar
extends PanelContainer

## The deck: nine bench slots and the sell zone.
##
## It is drawn as a ship's deck rather than as another blue panel, because this
## is the one panel holding *your* crew rather than the world — `DeckPlate`
## paints the planking, every slot is a rope ring the pirate standing there is
## seated in, and the sell zone is the water past the gunwale. None of it is an
## asset. See `DeckPlate` for why it is a plain child rather than
## `show_behind_parent`, and why nothing added in here may take a click.
##
## Dragging uses Godot's own drag-and-drop rather than a hand-rolled one, so a
## drop target only has to answer "can I take this?" and "here it is". The
## payload is a dictionary: `{ "kind": "unit"|"item", ... }`.
##
## Every drop target also reports what a drop *would* do before it happens —
## which unit would be sold and for how much, which item two components would
## forge into. Both are irreversible, and both used to be guesses.
##
## On a phone the nine slots wrap into two rows of five rather than one row of
## nine. Nine across a 375-point screen is a 36-point slot, which is under the
## smallest comfortable touch target; five across is 64 and stays thumb-sized.

signal preview_changed(text: String)
## The forged item under the cursor, for the inspector Main puts up — and the
## other half, for when whatever is under the cursor stops pairing.
signal forge_previewed(item_id: StringName, with_id: StringName, unit: RosterUnit,
	at: Vector2, source: Control)
signal forge_preview_cleared()
signal unit_dropped(unit: RosterUnit, slot: int)
signal item_dropped(item_id: StringName, unit: RosterUnit)
signal unit_sold(unit: RosterUnit)
signal unit_hovered(unit: RosterUnit, at: Vector2)
signal unit_unhovered()

var _slots: Array[BenchSlot] = []
var _sell_zone: SellZone = null


func _ready() -> void:
	add_theme_stylebox_override("panel",
		UITheme.panel_style(UITheme.DECK_TIMBER, UITheme.ROPE_DARK, 8))

	var compact := Layout.compact()

	# First child, so the planking is drawn under the slots standing on it.
	add_child(DeckPlate.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4 if compact else 5)
	add_child(row)

	if not compact:
		var heading := UITheme.heading("Deck")
		# Reads as part of the ship rather than as another sea-blue caption.
		heading.add_theme_color_override("font_color", UITheme.ROPE)
		row.add_child(heading)

	# One row of nine on a desktop; two rows of five on a phone, where nine
	# across would put every slot below a comfortable touch target.
	var slots: Container
	if compact:
		var grid := GridContainer.new()
		grid.columns = Layout.bench_columns()
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		slots = grid
	else:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 5)
		slots = line
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slots)

	for i in GameState.BENCH_SIZE:
		var slot := BenchSlot.new()
		slot.index = i
		if compact:
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.preview_changed.connect(func(text): preview_changed.emit(text))
		slot.forge_previewed.connect(func(item_id, with_id, unit, at, source):
			forge_previewed.emit(item_id, with_id, unit, at, source))
		slot.forge_preview_cleared.connect(func(): forge_preview_cleared.emit())
		slot.unit_dropped.connect(func(unit): unit_dropped.emit(unit, slot.index))
		slot.item_dropped.connect(func(item_id, unit): item_dropped.emit(item_id, unit))
		slot.unit_hovered.connect(func(unit, at): unit_hovered.emit(unit, at))
		slot.unit_unhovered.connect(func(): unit_unhovered.emit())
		slots.add_child(slot)
		_slots.append(slot)

	if not compact:
		row.add_child(UITheme.spacer(8))

	_sell_zone = SellZone.new()
	_sell_zone.unit_sold.connect(func(unit): unit_sold.emit(unit))
	_sell_zone.preview_changed.connect(func(text): preview_changed.emit(text))
	row.add_child(_sell_zone)

	Events.board_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for i in _slots.size():
		var unit: RosterUnit = GameState.bench[i] if i < GameState.bench.size() else null
		_slots[i].show_unit(unit)


# =============================================================================

class BenchSlot extends PanelContainer:
	signal preview_changed(text: String)
	signal forge_previewed(item_id: StringName, with_id: StringName, unit: RosterUnit,
		at: Vector2, source: Control)
	signal forge_preview_cleared()
	signal unit_dropped(unit: RosterUnit)
	signal item_dropped(item_id: StringName, unit: RosterUnit)
	signal unit_hovered(unit: RosterUnit, at: Vector2)
	signal unit_unhovered()

	var index: int = 0
	var unit: RosterUnit = null

	var _view: UnitView = null
	var _ring: SlotRing = null

	func _init() -> void:
		var slot := Layout.bench_slot()
		custom_minimum_size = slot
		mouse_filter = Control.MOUSE_FILTER_STOP
		# Translucent on purpose. An opaque slot covers the planking it is
		# standing on, and nine of them across the bench leave the deck showing
		# only in the margins — which is the whole thing this is for.
		add_theme_stylebox_override("panel",
			UITheme.panel_style(Color(UITheme.DECK_HATCH, 0.55),
				Color(UITheme.ROPE_DARK, 0.6), 7))

		# Added before the pirate, so the ring is under their feet rather than
		# over their head: a CanvasItem paints its children in order.
		_ring = SlotRing.new()
		add_child(_ring)

		_view = UnitView.new()
		# The pirate is drawn at a fixed size, so a smaller slot needs a smaller
		# pirate or it draws outside its own panel.
		var view_scale := 0.72 * slot.y / 64.0
		_view.scale = Vector2(view_scale, view_scale)
		# The same gate the board and the portraits apply, for the same reason:
		# a 40-point phone slot draws the figure at 0.45, where a belt buckle and
		# a row of teeth are a draw call each producing one indistinct pixel —
		# ten slots over, on the device least able to afford them.
		_view.detail = clampf(view_scale * 1.2, 0.0, 1.0)
		add_child(_view)

		resized.connect(_centre_view)
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(func(): unit_unhovered.emit())

	func _centre_view() -> void:
		_view.position = size * 0.5

	func _on_enter() -> void:
		if unit != null:
			unit_hovered.emit(unit, global_position + Vector2(size.x * 0.5, 0))

	func show_unit(next: RosterUnit) -> void:
		unit = next
		_ring.set_crewed(next != null)
		_view.visible = next != null
		if next != null:
			_view.bind_roster(next)
		_centre_view()

	func _get_drag_data(_at: Vector2) -> Variant:
		if unit == null or GameState.phase != GameState.Phase.PLAN:
			return null
		var preview := UnitView.new()
		preview.bind_roster(unit)
		var holder := Control.new()
		var slot := Layout.bench_slot()
		holder.custom_minimum_size = slot
		holder.add_child(preview)
		preview.position = slot * 0.5
		set_drag_preview(holder)
		return { "kind": &"unit", "unit": unit }

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if typeof(data) != TYPE_DICTIONARY or GameState.phase != GameState.Phase.PLAN:
			return false
		if data["kind"] == &"unit":
			return true
		if data["kind"] == &"item" and unit != null:
			var preview: Dictionary = GameState.preview_equip(data["id"], unit)
			preview_changed.emit(_describe(preview, data["id"]))
			_report_forge(preview, data["id"], unit)
			return preview.get("allowed", false)
		forge_preview_cleared.emit()
		return false

	## The forged item's own inspector, while the cursor is over the pirate
	## holding the other half. The line says what it makes; this says what the
	## thing it makes does, which is the half the decision actually turns on.
	func _report_forge(preview: Dictionary, item_id: StringName, unit: RosterUnit) -> void:
		if preview.get("forges", &"") == &"":
			forge_preview_cleared.emit()
			return
		forge_previewed.emit(item_id, preview["with"], unit,
			global_position + Vector2(size.x * 0.5, 0.0), self)

	## Says what the drop would produce, before it happens.
	func _describe(preview: Dictionary, item_id: StringName) -> String:
		if not preview.get("allowed", false):
			return preview.get("reason", "")
		var forged: StringName = preview.get("forges", &"")
		if forged != &"":
			var def: ItemDef = GameState.content.item_def(forged)
			return "Forges %s %s" % [def.icon, def.display_name]
		var item: ItemDef = GameState.content.item_def(item_id)
		return "Equip %s" % item.display_name

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_clear_preview()
		if data["kind"] == &"unit":
			unit_dropped.emit(data["unit"])
		elif data["kind"] == &"item" and unit != null:
			item_dropped.emit(data["id"], unit)

	## A drag that ended anywhere — dropped here, dropped elsewhere, or
	## abandoned — leaves the line and the inspector describing a drop that is
	## not going to happen. Godot tells every control the drag is over, which is
	## the only notice a slot the cursor left long ago ever gets.
	##
	## Deliberately not on MOUSE_EXIT: the control being left is notified after
	## the one being entered has already been asked whether it can take the drop,
	## so clearing there wipes the preview the *next* slot has just set.
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END:
			_clear_preview()

	func _clear_preview() -> void:
		preview_changed.emit("")
		forge_preview_cleared.emit()


# =============================================================================

class SellZone extends PanelContainer:
	signal unit_sold(unit: RosterUnit)
	signal preview_changed(text: String)

	var _label: Label = null
	var _armed: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(52, 0) if Layout.compact() else Vector2(96, 64)
		# Water, not another panel: this is the far side of the rail. The rope
		# border is the gunwale you would be dropping someone over.
		add_theme_stylebox_override("panel",
			UITheme.panel_style(UITheme.OVERBOARD, UITheme.ROPE_DARK, 7))
		_label = UITheme.label(_idle_text(), UITheme.FONT_TINY, Color("a95a68"))
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if typeof(data) != TYPE_DICTIONARY or data.get("kind") != &"unit":
			return false
		# Naming the price on the zone means a sale is never a surprise.
		var unit: RosterUnit = data["unit"]
		_label.text = "SELL FOR\n%s %d" % [UITheme.COIN, unit.sell_value()]
		_label.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		_armed = true
		return true

	func _drop_data(_at: Vector2, data: Variant) -> void:
		_reset()
		unit_sold.emit(data["unit"])

	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAG_END and _armed:
			_reset()

	func _reset() -> void:
		_armed = false
		_label.text = _idle_text()
		_label.add_theme_color_override("font_color", Color("a95a68"))

	## The flavour is only affordable where the zone is 96 points wide. On a
	## phone it is 52, and the instruction is the half that has to survive.
	func _idle_text() -> String:
		return "DROP\nTO SELL" if Layout.compact() else "THE PLANK\nDROP TO SELL"



# =============================================================================

## The rope ring a pirate stands in, drawn under them in every bench slot.
##
## An empty slot is a dark hatch with a faint ring; a crewed one lights the rope
## and picks out the seizings. That is the whole "these nine are yours" signal —
## the slots themselves are identical, so without it the bench reads as storage
## rather than as a deck with people on it.
##
## `MOUSE_FILTER_IGNORE`, because it covers the whole slot and the slot is the
## thing a drag has to be able to start on.
class SlotRing extends Control:
	## Ring radius as a fraction of the slot's short side.
	const RADIUS := 0.46
	## Below this the seizings are one indistinct pixel each; only the ring is
	## drawn. Same trade `Pose.detail` makes on the board.
	const DETAIL_RADIUS := 11.0

	var _crewed: bool = false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_crewed(crewed: bool) -> void:
		if crewed == _crewed:
			return
		_crewed = crewed
		queue_redraw()

	func _draw() -> void:
		var radius := minf(size.x, size.y) * RADIUS
		if radius < 4.0:
			return
		var centre := size * 0.5
		var rope := UITheme.ROPE if _crewed else Color(UITheme.ROPE_DARK, 0.55)
		draw_arc(centre, radius, 0.0, TAU, 28, rope, 1.5, true)
		if radius < DETAIL_RADIUS:
			return
		# Four seizings across the ring, offset so none sits on an axis and
		# turns into a stray horizontal.
		for i in 4:
			var angle := TAU * (float(i) / 4.0) + PI * 0.25
			var out := Vector2(cos(angle), sin(angle))
			draw_line(centre + out * (radius - 2.0), centre + out * (radius + 2.0),
				rope, 1.0)
