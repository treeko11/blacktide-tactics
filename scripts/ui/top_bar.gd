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

	_hp = _add_stat_chip(row, "❤", "100", Color("ff7d8a"))
	_gold = _add_stat_chip(row, UITheme.COIN, "0", UITheme.GOLD_BRIGHT)
	# The streak is the one stat a phone can do without: it is a nicety rather
	# than a number the player steers by, and the bar is already tight.
	_streak = _add_stat_chip(row, "⚔", "–", UITheme.FOAM, not compact)

	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 2)
	for value in SPEEDS:
		var button := UITheme.button("%d×" % value, UITheme.FONT_TINY)
		button.toggle_mode = true
		# Read from the run, not hard-coded to 1×. The HUD is rebuilt whenever the
		# window crosses a breakpoint, and the speed the player chose lives in
		# GameState and survives that — so a bar built fresh at 1× is a bar
		# claiming a speed the game is not running at.
		button.button_pressed = value == GameState.speed
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


## Adds a little icon-and-number chip to `row` and hands back the label to keep
## updating.
##
## It adds the chip itself rather than returning it, because the caller needs two
## different nodes out of one call — the chip to seat and the label to write to —
## and the alternative that avoided a two-element Array was assigning the field by
## name (`set("_%s" % ...)`), where a typo is silent.
func _add_stat_chip(row: HBoxContainer, icon: String, value: String, color: Color,
		shown: bool = true) -> Label:
	var chip := PanelContainer.new()
	chip.visible = shown
	row.add_child(chip)
	chip.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0a1c27"), UITheme.LINE, 4))
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 5)
	chip.add_child(inner)

	var glyph := Label.new()
	glyph.add_theme_font_override("font", UITheme.emoji_font())
	glyph.add_theme_font_size_override("font_size", 10 if Layout.compact() else 12)
	glyph.text = icon
	glyph.add_theme_color_override("font_color", color)
	inner.add_child(glyph)

	var label := UITheme.label(value,
		UITheme.FONT_SMALL if Layout.compact() else UITheme.FONT_TITLE, color)
	inner.add_child(label)
	return label


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
