class_name Modals
extends Control

## The full-screen dialogs: the armoury, the forge chart, how to play, and the
## end of the run.

signal armoury_chosen(item_id: StringName)
signal restart_requested()

var _scrim: ColorRect = null
var _box: PanelContainer = null
var _content: VBoxContainer = null
var _dismissable: bool = true


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
	_box.custom_minimum_size = Vector2(520, 0)
	centre.add_child(_box)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_box.add_child(_content)


func is_open() -> bool:
	return visible


func close() -> void:
	visible = false
	_clear()


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()


func _open(title: String, subtitle: String, dismissable: bool = true) -> void:
	_clear()
	_dismissable = dismissable
	visible = true

	var heading := UITheme.label(title, 26, UITheme.GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(heading)

	if subtitle != "":
		var sub := UITheme.label(subtitle, UITheme.FONT_SMALL, UITheme.MUTED)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(sub)


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

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(row)

	for item_id in offers:
		var item: ItemDef = GameState.content.item_def(item_id)
		if item == null:
			continue
		var card := _item_card(item)
		card.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				close()
				armoury_chosen.emit(item_id))
		row.add_child(card)


func _item_card(item: ItemDef) -> PanelContainer:
	var card := PanelContainer.new()
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
	_content.add_child(close_button)


func _can_make(held: Dictionary, a: StringName, b: StringName) -> bool:
	if a == b:
		return int(held.get(a, 0)) >= 2
	return held.has(a) and held.has(b)


func _chart_header(component: ItemDef) -> Control:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(72, 40)
	cell.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("11283a"), Color("2f5a72"), 5))
	cell.tooltip_text = component.display_name

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
	cell.custom_minimum_size = Vector2(72, 40)
	var border := UITheme.GOOD if makeable else Color("1d3b4e")
	cell.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0d1c26") if not makeable else Color("0e2a1e"), border, 5))
	if result == null:
		return cell

	cell.tooltip_text = "%s — %s" % [result.display_name, result.description]

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	cell.add_child(column)

	var glyph := Label.new()
	glyph.add_theme_font_override("font", UITheme.emoji_font())
	glyph.add_theme_font_size_override("font_size", 17)
	glyph.text = result.icon
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(glyph)

	var name_label := UITheme.label(result.display_name, 8,
		UITheme.GOOD if makeable else UITheme.MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name_label)

	return cell


# =============================================================================
#  How to sail
# =============================================================================

func open_help() -> void:
	_open("How to Sail", "")

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(560, 380)
	body.add_theme_font_size_override("normal_font_size", UITheme.FONT_SMALL)
	body.text = _help_text()
	_content.add_child(body)

	var button := UITheme.button("WEIGH ANCHOR", UITheme.FONT_BODY)
	button.pressed.connect(close)
	_content.add_child(button)


func _help_text() -> String:
	return """[color=#7fe3ff][b]THE LOOP[/b][/color]
Buy pirates from the shop, drag them onto your half of the board, and your crew fights on its own. Lose and your [b]hull[/b] takes damage. Last captain afloat wins.

[color=#7fe3ff][b]UPGRADING[/b][/color]
Three copies of the same pirate merge into a ★★ version; three of those make ★★★. Copies on the bench count. The shop marks a card [color=#ffd98a]BUY THIS[/color] when it completes an upgrade.

[color=#7fe3ff][b]TRAITS[/b][/color]
Every pirate has an [b]Origin[/b] and a [b]Class[/b]. Fielding enough [i]different[/i] pirates sharing a trait activates a fleet-wide bonus — three copies of one pirate is a star-up, not a trait. Hover the manifest to read them.

[color=#7fe3ff][b]GOLD[/b][/color]
5 a round, plus 1 interest per 10 banked (max 5), plus a streak bonus for consecutive wins [i]or[/i] losses. Refreshing costs 2, XP costs 4.

[color=#7fe3ff][b]ITEMS[/b][/color]
Monster rounds drop components. Drag two onto the same pirate to [b]forge[/b] a full item — three per pirate. The [b]Forge chart[/b] button over the cargo hold shows every pairing. The armoury at the end of a stage offers a finished item.

[color=#7fe3ff][b]CONTROLS[/b][/color]
[b]Drag[/b] pirates between bench and board · [b]Right-click[/b] to sell · [b]D[/b] refresh · [b]F[/b] buy XP · [b]Space[/b] start the battle early · [b]1 / 2 / 4[/b] battle speed"""


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
	_content.add_child(button)
