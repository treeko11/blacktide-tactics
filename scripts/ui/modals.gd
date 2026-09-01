class_name Modals
extends Control

## The full-screen dialogs the *run* raises: the armoury, the forge chart, and
## the end of the run.
##
## The reference dialogs are not here. How to Sail used to be, and it moved into
## `Wiki` when the almanac absorbed it — a rules page that only ever opened once,
## at the start of a run, was a rules page nobody could get back to.
##
## The box sizes itself to the screen and scrolls when it runs out of room, which
## is what makes these usable on a phone: the forge chart is a six-by-six grid and
## does not shrink usefully.

signal armoury_chosen(item_id: StringName)
signal restart_requested()

## A cell of the forge chart is being looked at. Main turns it into the same
## inspector the cargo hold uses, so the chart answers "what does this make" and
## "what does the thing it makes actually do" in one place.
signal chart_item_hovered(item_id: StringName, at: Vector2, source: Control)
signal chart_item_unhovered()

var _scrim: ColorRect = null
var _box: PanelContainer = null
var _scroll: ScrollContainer = null
var _content: VBoxContainer = null
var _actions: VBoxContainer = null
var _dismissable: bool = true
var _max_height: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP

	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.72)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0e2534"), UITheme.LINE, 10))
	centre.add_child(_box)

	# A dialog wider than the screen is a dialog with its buttons off the edge.
	var room := Layout.css_size
	_box.custom_minimum_size = Vector2(minf(520.0, room.x - 24.0), 0)
	_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	_box.add_child(stack)

	_max_height = room.y * 0.82

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_scroll = scroll

	# Buttons live below the scroll, never inside it. A tall dialog on a phone
	# scrolled its own dismiss button off the bottom — a way out you have to go
	# looking for is a dialog that looks stuck.
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 6)
	stack.add_child(_actions)

	set_process(true)


func _process(_delta: float) -> void:
	if visible:
		_fit_height()


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	_clear()


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()
	for child in _actions.get_children():
		child.queue_free()


func _open(title: String, subtitle: String, dismissable: bool = true) -> void:
	_clear()
	_dismissable = dismissable
	visible = true

	# Opened at full height so the content lays out at its real width; _fit_height
	# shrinks it once the labels know how wide they are.
	_scroll.custom_minimum_size = Vector2(0, _max_height)

	var heading := UITheme.label(title, 26, UITheme.GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(heading)

	if subtitle != "":
		var sub := UITheme.label(subtitle, UITheme.FONT_SMALL, UITheme.MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(sub)


## Sized every frame the dialog is open rather than once when it opens.
##
## An autowrapping label asked for its minimum height before it has been given a
## width answers as though every word were on its own line — the three-item
## armoury measured 5895 points tall on the frame it was built. One layout pass
## later the same question gets the right answer, so the fit converges instead of
## trusting the first number it is told.
func _fit_height() -> void:
	if _scroll == null or not visible:
		return
	var wanted: float = minf(_content.get_combined_minimum_size().y, _max_height)
	if absf(wanted - _scroll.custom_minimum_size.y) > 0.5:
		_scroll.custom_minimum_size = Vector2(0, wanted)


## Adds a button under the scroll rather than inside it, where it cannot be
## scrolled out of reach.
func _add_action(button: Button) -> void:
	_actions.add_child(button)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _dismissable:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# =============================================================================
#  The armoury
# =============================================================================

## Three finished items, take one. Not dismissable — the round waits on it.
func open_armoury(offers: Array[StringName]) -> void:
	_open("The Armoury", "Salvage from the wreck — take one. (+2 gold)", false)

	# Three cards side by side is 200 points each, which no phone has. Stacked,
	# each card becomes a full-width row instead, as in the JS build.
	var row: BoxContainer
	if Layout.compact():
		row = VBoxContainer.new()
	else:
		row = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8 if Layout.compact() else 12)
	_content.add_child(row)

	for item_id in offers:
		var item: ItemDef = GameState.content.item_def(item_id)
		if item == null:
			continue
		var card := _item_card(item)
		# Taken on release, and only if the finger is still on the card — the same
		# rule a shop card follows, for the same reason. A press was enough before,
		# which meant the armoury could not be scrolled on a phone: the flick that
		# was meant to reach the third item took the first one instead. The choice
		# is final and ends the round, so it must be something the player let go of
		# on purpose.
		card.gui_input.connect(func(event: InputEvent):
			if not (event is InputEventMouseButton) or event.pressed:
				return
			if event.button_index != MOUSE_BUTTON_LEFT:
				return
			if not Rect2(Vector2.ZERO, card.size).has_point(event.position):
				return
			close()
			armoury_chosen.emit(item_id))
		row.add_child(card)


func _item_card(item: ItemDef) -> PanelContainer:
	var card := PanelContainer.new()
	if Layout.compact():
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		card.custom_minimum_size = Vector2(200, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("132a3a"), Color("24485c"), 8))
	card.mouse_entered.connect(func():
		card.add_theme_stylebox_override("panel",
			UITheme.panel_style(Color("1b3a4e"), UITheme.GOLD, 8)))
	card.mouse_exited.connect(func():
		card.add_theme_stylebox_override("panel",
			UITheme.panel_style(Color("132a3a"), Color("24485c"), 8)))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	card.add_child(column)

	var glyph := Label.new()
	glyph.add_theme_font_override("font", UITheme.emoji_font())
	glyph.add_theme_font_size_override("font_size", 34)
	glyph.text = item.icon
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(glyph)

	var name_label := UITheme.label(item.display_name, UITheme.FONT_BODY, UITheme.GOLD_BRIGHT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name_label)

	var body := UITheme.label(item.description, UITheme.FONT_TINY, Color("a9c4d4"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)

	return card


# =============================================================================
#  The forge chart
# =============================================================================

## Every component pairing and what it makes, in one grid.
##
## Item combinations were the least discoverable system in the game: five
## components make fifteen items and nothing anywhere said which. Pairings the
## player can make right now are marked, so the chart answers "what should I do
## with what I am holding" and not only "what exists".
func open_forge_chart() -> void:
	_open("The Forge", "Two components on one pirate combine. Green is what your hold can make now.")

	var content := GameState.content
	var components: Array = content.components()

	var held: Dictionary = {}
	for item_id in GameState.player.items:
		held[item_id] = int(held.get(item_id, 0)) + 1

	var grid := GridContainer.new()
	grid.columns = components.size() + 1
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)

	grid.add_child(Control.new())     # empty corner
	for component in components:
		grid.add_child(_chart_header(component))

	for row_component in components:
		grid.add_child(_chart_header(row_component))
		for column_component in components:
			var result_id: StringName = content.forge(row_component.id, column_component.id)
			var result: ItemDef = content.item_def(result_id)
			var makeable := _can_make(held, row_component.id, column_component.id)
			grid.add_child(_chart_cell(result, makeable))

	var close_button := UITheme.button("CLOSE", UITheme.FONT_BODY)
	close_button.pressed.connect(close)
	_add_action(close_button)


## Makes a chart cell report what it is, so the real inspector can open on it.
##
## It used to carry Godot's own `tooltip_text`, which is a hover feature: a phone
## never saw it, and even on a desktop it gave one line where the item's own
## panel gives the full effect and what it is forged from.
func _inspectable(cell: Control, item_id: StringName) -> void:
	cell.mouse_filter = Control.MOUSE_FILTER_STOP
	cell.mouse_entered.connect(func():
		chart_item_hovered.emit(item_id,
			cell.global_position + Vector2(cell.size.x * 0.5, cell.size.y), cell))
	cell.mouse_exited.connect(func(): chart_item_unhovered.emit())


func _can_make(held: Dictionary, a: StringName, b: StringName) -> bool:
	if a == b:
		return int(held.get(a, 0)) >= 2
	return held.has(a) and held.has(b)


## Chart cells. Six columns of 72 is 432 points wide, so a phone gets 48.
func _chart_size() -> Vector2:
	return Vector2(48, 34) if Layout.compact() else Vector2(72, 40)


func _chart_header(component: ItemDef) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = _chart_size()
	cell.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("11283a"), Color("2f5a72"), 5))
	_inspectable(cell, component.id)

	var glyph := Label.new()
	glyph.add_theme_font_override("font", UITheme.emoji_font())
	glyph.add_theme_font_size_override("font_size", 20)
	glyph.text = component.icon
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cell.add_child(glyph)
	return cell


func _chart_cell(result: ItemDef, makeable: bool) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = _chart_size()
	var border := UITheme.GOOD if makeable else Color("1d3b4e")
	cell.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0d1c26") if not makeable else Color("0e2a1e"), border, 5))
	if result == null:
		return cell

	_inspectable(cell, result.id)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	cell.add_child(column)

	var glyph := Label.new()
	glyph.add_theme_font_override("font", UITheme.emoji_font())
	glyph.add_theme_font_size_override("font_size", 17)
	glyph.text = result.icon
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(glyph)

	# The name does not fit a 48-point cell. The icon and the tooltip carry it.
	if not Layout.compact():
		var name_label := UITheme.label(result.display_name, 8,
			UITheme.GOOD if makeable else UITheme.MUTED)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(name_label)

	return cell


# =============================================================================
#  End of the run
# =============================================================================

func open_game_over(place: int) -> void:
	var won := place == 1
	_open("The Sea Is Yours" if won else "Davy Jones Calls", "", false)

	var result := UITheme.label("%s place" % GameState.ordinal(place), UITheme.FONT_TITLE,
		UITheme.GOLD if won else UITheme.INK)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(result)

	var blurb := UITheme.label(
		"Every rival fleet lies on the seabed. The horizon belongs to you." if won
		else "Your hull gave out at stage %d. The crew salutes you as you sink."
			% GameState.stage,
		UITheme.FONT_SMALL, UITheme.MUTED)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(blurb)

	var button := UITheme.button("SAIL AGAIN", UITheme.FONT_BODY)
	button.pressed.connect(func():
		close()
		restart_requested.emit())
	_add_action(button)
