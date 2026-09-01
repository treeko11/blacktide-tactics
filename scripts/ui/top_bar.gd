class_name TopBar
extends PanelContainer

## Stage, phase, hull, streak, and the battle speed control.
##
## Gold lives here *and* in the shop row. That is deliberate duplication: this
## copy is for reading the run at a glance, the shop's copy is for spending, and
## during the planning phase the player never looks up here.
##
## On a phone the bar sheds everything that is not a number the player steers by:
## the wordmark, the phase name and the streak all go, and a FLEET button
## arrives, because the fleet panel has become a sheet that needs opening.

signal speed_changed(speed: int)
signal help_pressed()
signal fleet_pressed()

const SPEEDS := [1, 2, 4]

var _stage: Label = null
var _phase: Label = null
var _hp: Label = null
var _gold: Label = null
var _streak: Label = null
var _speed_buttons: Array[Button] = []


func _ready() -> void:
	var compact := Layout.compact()
	add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0d2130"), UITheme.LINE, 0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5 if compact else 12)
	add_child(row)

	if not compact:
		row.add_child(UITheme.label("BLACKTIDE", UITheme.FONT_TITLE, UITheme.GOLD))

	_stage = UITheme.label("1-1",
		UITheme.FONT_BODY if compact else UITheme.FONT_TITLE, UITheme.GOLD_BRIGHT)
	row.add_child(_stage)

	# Kept built either way so refresh() has something to write to; a phone just
	# never sees it. Branching on the label's existence instead means every
	# reader needs a null check for a saving of one Label.
	_phase = UITheme.label("PLANNING", UITheme.FONT_TINY, UITheme.FOAM)
	_phase.visible = not compact
	row.add_child(_phase)

	row.add_child(UITheme.spacer())

	for spec in [
		["❤", "100", Color("ff7d8a"), "hp"],
		[UITheme.COIN, "0", UITheme.GOLD_BRIGHT, "gold"],
		["⚔", "–", UITheme.FOAM, "streak"],
	]:
		var chip := _stat_chip(spec[0], spec[1], spec[2])
		chip[0].visible = not (compact and spec[3] == "streak")
		row.add_child(chip[0])
		set("_%s" % spec[3], chip[1])

	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 2)
	for value in SPEEDS:
		var button := UITheme.button("%d×" % value, UITheme.FONT_TINY)
		button.toggle_mode = true
		button.button_pressed = value == 1
		button.pressed.connect(func(): _select_speed(value))
		speeds.add_child(button)
		_speed_buttons.append(button)
	row.add_child(speeds)

	if compact:
		# The fleet and the log live in a sheet on a phone, and a sheet with no
		# handle is a panel that does not exist.
		var sheet := UITheme.button("FLEET", UITheme.FONT_TINY)
		sheet.pressed.connect(func(): fleet_pressed.emit())
		row.add_child(sheet)

	var help := UITheme.button("?", UITheme.FONT_BODY if not compact else UITheme.FONT_SMALL)
	help.pressed.connect(func(): help_pressed.emit())
	row.add_child(help)

	Events.gold_changed.connect(func(amount, _d): _gold.text = str(amount))
	Events.health_changed.connect(func(amount, _d): _hp.text = str(amount))
	Events.phase_changed.connect(_on_phase_changed)
	Events.round_began.connect(func(stage, number): _stage.text = "%d-%d" % [stage, number])
	Events.round_resolved.connect(func(_w, _d, _o): refresh())
	refresh()


## A little icon-and-number chip, returned as [chip, value label].
##
## Both are needed by the caller: the chip to add to the bar, the label to keep
## updating. Returning only the label and walking back up to `get_parent()` finds
## the inner row rather than the chip, which silently adds the wrong node.
func _stat_chip(icon: String, value: String, color: Color) -> Array:
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0a1c27"), UITheme.LINE, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	chip.add_child(row)

	var glyph := Label.new()
	glyph.add_theme_font_override("font", UITheme.emoji_font())
	glyph.add_theme_font_size_override("font_size", 10 if Layout.compact() else 12)
	glyph.text = icon
	glyph.add_theme_color_override("font_color", color)
	row.add_child(glyph)

	var label := UITheme.label(value,
		UITheme.FONT_SMALL if Layout.compact() else UITheme.FONT_TITLE, color)
	row.add_child(label)
	return [chip, label]


func _select_speed(value: int) -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].button_pressed = SPEEDS[i] == value
	speed_changed.emit(value)


func refresh() -> void:
	_hp.text = str(maxi(0, GameState.player.hp))
	_gold.text = str(GameState.player.gold)
	_streak.text = GameState.player.streak_label()
	_streak.add_theme_color_override("font_color",
		Color("ffb15c") if absi(GameState.player.streak) >= 3 else UITheme.FOAM)
	_stage.text = "%d-%d" % [GameState.stage, GameState.round_number]


func _on_phase_changed(phase: int) -> void:
	var names := {
		GameState.Phase.PLAN: "PLANNING",
		GameState.Phase.COMBAT: "BATTLE",
		GameState.Phase.RESULT: "AFTERMATH",
		GameState.Phase.ARMOURY: "ARMOURY",
		GameState.Phase.OVER: "FINISHED",
	}
	_phase.text = names.get(phase, "")
	_phase.add_theme_color_override("font_color",
		Color("ff9d9d") if phase == GameState.Phase.COMBAT else UITheme.FOAM)
	refresh()
