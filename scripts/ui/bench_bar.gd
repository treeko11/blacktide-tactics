class_name BenchBar
extends PanelContainer

## The deck: nine bench slots and the sell zone.
##
## Dragging uses Godot's own drag-and-drop rather than a hand-rolled one, so a
## drop target only has to answer "can I take this?" and "here it is". The
## payload is a dictionary: `{ "kind": "unit"|"item", ... }`.
##
## Every drop target also reports what a drop *would* do before it happens —
## which unit would be sold and for how much, which item two components would
## forge into. Both are irreversible, and both used to be guesses.

signal preview_changed(text: String)
signal unit_dropped(unit: RosterUnit, slot: int)
signal item_dropped(item_id: StringName, unit: RosterUnit)
signal unit_sold(unit: RosterUnit)
signal unit_hovered(unit: RosterUnit, at: Vector2)
signal unit_unhovered()

var _slots: Array[BenchSlot] = []
var _sell_zone: SellZone = null


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.PANEL, UITheme.LINE, 8))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	add_child(row)

	row.add_child(UITheme.heading("Deck"))

	for i in GameState.BENCH_SIZE:
		var slot := BenchSlot.new()
		slot.index = i
		slot.preview_changed.connect(func(text): preview_changed.emit(text))
		slot.unit_dropped.connect(func(unit): unit_dropped.emit(unit, slot.index))
		slot.item_dropped.connect(func(item_id, unit): item_dropped.emit(item_id, unit))
		slot.unit_hovered.connect(func(unit, at): unit_hovered.emit(unit, at))
		slot.unit_unhovered.connect(func(): unit_unhovered.emit())
		row.add_child(slot)
		_slots.append(slot)

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
	signal unit_dropped(unit: RosterUnit)
	signal item_dropped(item_id: StringName, unit: RosterUnit)
	signal unit_hovered(unit: RosterUnit, at: Vector2)
	signal unit_unhovered()

	const SLOT_SIZE := Vector2(64, 64)

	var index: int = 0
	var unit: RosterUnit = null

	var _view: UnitView = null

	func _init() -> void:
		custom_minimum_size = SLOT_SIZE
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_theme_stylebox_override("panel",
			UITheme.panel_style(Color("0a1a24"), Color("17323f"), 7))

		_view = UnitView.new()
		_view.scale = Vector2(0.72, 0.72)
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
		holder.custom_minimum_size = SLOT_SIZE
		holder.add_child(preview)
		preview.position = SLOT_SIZE * 0.5
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
			return preview.get("allowed", false)
		return false

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
		preview_changed.emit("")
		if data["kind"] == &"unit":
			unit_dropped.emit(data["unit"])
		elif data["kind"] == &"item" and unit != null:
			item_dropped.emit(data["id"], unit)


# =============================================================================

class SellZone extends PanelContainer:
	signal unit_sold(unit: RosterUnit)
	signal preview_changed(text: String)

	var _label: Label = null
	var _armed: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(96, 64)
		add_theme_stylebox_override("panel",
			UITheme.panel_style(Color("1a0a0e"), Color("5e2a34"), 7))
		_label = UITheme.label("DROP\nTO SELL", UITheme.FONT_TINY, Color("a95a68"))
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(_label)

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		if typeof(data) != TYPE_DICTIONARY or data.get("kind") != &"unit":
			return false
		# Naming the price on the zone means a sale is never a surprise.
		var unit: RosterUnit = data["unit"]
		_label.text = "SELL FOR\n● %d" % unit.sell_value()
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
		_label.text = "DROP\nTO SELL"
		_label.add_theme_color_override("font_color", Color("a95a68"))
