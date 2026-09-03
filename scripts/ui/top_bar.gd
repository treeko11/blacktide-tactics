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
signal dps_pressed()
signal sound_toggled()

const SPEEDS := [1, 2, 4]

var _stage: Label = null
var _phase: Label = null
var _hp: Label = null
var _gold: Label = null
var _streak: Label = null
var _sea_chip: PanelContainer = null
var _sea_glyph: Label = null
var _sea_label: Label = null
var _sea_mark: String = ""
var _overtime_mark: String = ""
var _overtime: bool = false
var _speed_buttons: Array[Button] = []
var _sound_button: Button = null


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

	# Beside the round number, because that is what it is: a fact about which
	# round this is. Hidden until there is weather to name.
	_build_sea_chip(row)

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

	# The one control here that is not about the run. It is an icon at every
	# width because it is the one button whose meaning a symbol carries better
	# than a word, and it reads `Audio.muted` rather than starting at "on": mute
	# is remembered between sessions, and a rotation rebuilds this bar.
	_sound_button = UITheme.button("", UITheme.FONT_SMALL)
	_sound_button.add_theme_font_override("font", UITheme.emoji_font())
	_sound_button.pressed.connect(func(): sound_toggled.emit())
	row.add_child(_sound_button)
	show_muted(Audio.muted)

	# Kept to three letters at every width. The dialog behind it is themed —
	# "The Butcher's Bill" — but the handle is not the place to be clever: a
	# player looking for a damage meter is looking for these three letters.
	var meter := UITheme.button("DPS", UITheme.FONT_TINY if compact else UITheme.FONT_SMALL)
	meter.pressed.connect(func(): dps_pressed.emit())
	row.add_child(meter)

	# Labelled where there is room for a label. The almanac holds every pirate,
	# trait, item and wave in the game as well as the rules, and a lone "?" says
	# none of that — but a phone's top bar has no width to spend saying it.
	var help := UITheme.button("?" if compact else "ALMANAC",
		UITheme.FONT_SMALL if compact else UITheme.FONT_BODY)
	help.pressed.connect(func(): help_pressed.emit())
	row.add_child(help)

	Events.sound_muted_changed.connect(show_muted)
	Events.speed_changed.connect(show_speed)
	Events.gold_changed.connect(func(amount, _d): _gold.text = str(amount))
	Events.health_changed.connect(func(amount, _d): _hp.text = str(amount))
	Events.phase_changed.connect(_on_phase_changed)
	Events.round_began.connect(func(_s, _n): _write_stage())
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


## The weather chip. Built like a stat chip but written by `show_sea`, which
## changes its colour as well as its text — a following sea and a red tide are
## not the same news and must not be the same green.
func _build_sea_chip(row: HBoxContainer) -> void:
	_sea_chip = PanelContainer.new()
	_sea_chip.visible = false
	_sea_chip.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("0a1c27"), UITheme.LINE, 4))
	row.add_child(_sea_chip)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	_sea_chip.add_child(inner)

	_sea_glyph = Label.new()
	_sea_glyph.add_theme_font_override("font", UITheme.emoji_font())
	_sea_glyph.add_theme_font_size_override("font_size",
		10 if Layout.compact() else 12)
	inner.add_child(_sea_glyph)

	_sea_label = UITheme.label("", UITheme.FONT_TINY, UITheme.FOAM)
	inner.add_child(_sea_label)


## This stage's weather, and how far off it is.
##
## `rounds_away` is 0 on the round being fought in it and -1 when there is none.
## A phone never gets the chip at all — see `_write_stage` — so the name only
## appears where there is width for it; on a phone it is in the toast, the log
## and the almanac instead.
func show_sea(def: SeaDef, rounds_away: int) -> void:
	if def == null or rounds_away < 0:
		_sea_chip.visible = false
		_sea_mark = ""
		_write_stage()
		return

	if Layout.compact():
		_sea_chip.visible = false
		_sea_mark = " %s" % def.icon if rounds_away == 0 else " %s%d" % [def.icon, rounds_away]
		_write_stage()
		return

	_sea_mark = ""
	_write_stage()
	_sea_chip.visible = true
	_sea_glyph.text = def.icon
	_sea_glyph.add_theme_color_override("font_color", def.mark_color)
	_sea_label.add_theme_color_override("font_color", def.mark_color)
	_sea_label.text = def.display_name.to_upper() if rounds_away == 0 		else "IN %d" % rounds_away


## The round, and on a phone the weather with it.
##
## A phone's bar has no slack at all — before this it ended with the almanac
## button hard against the right edge — so a chip that fits on a desktop pushes
## that button off the screen entirely, on the weather round, which is the round
## a player is most likely to want to look something up. The mark goes in the
## round label instead, where it costs one glyph and is arguably where it
## belonged anyway: it is a fact about which round this is.
func _write_stage() -> void:
	_stage.text = "%d-%d%s%s" % [GameState.stage, GameState.round_number,
		_sea_mark, _overtime_mark]


## Whether this fight has entered overtime.
##
## The phase label already says BATTLE and has the width to say something
## longer, so overtime replaces it rather than arriving as another chip — the
## bar has no slack for one, which is the whole reason the weather mark lives in
## the round label. A phone hides the phase label outright, so there it takes
## the same route the weather does and becomes a glyph on the round.
func show_overtime(active: bool) -> void:
	_overtime = active
	_overtime_mark = " 🔥" if active and Layout.compact() else ""
	_write_stage()
	_write_phase()


## Whether the weather chip is up. Read by `screenshot.gd --sea=`, which is the
## only thing that can see this bar at all.
func sea_shown() -> bool:
	return _sea_mark != "" or (_sea_chip != null and _sea_chip.visible)


## Whether the bar is reporting overtime. Read by `screenshot.gd --overtime`,
## which is the only thing that can see this bar at all — the phase label is
## hidden on a phone, so the two layouts are asserted through one accessor
## rather than by the tool knowing which of them it is looking at.
func overtime_shown() -> bool:
	if _overtime_mark != "":
		return true
	return _phase != null and _phase.visible and _phase.text == "OVERTIME"


## The bell, crossed out or not. Two emoji rather than a word, so the button
## stays the same width in both states and at every layout — and a bell rather
## than a speaker because the speaker emoji is drawn black, which on this bar is
## a dark grey smudge. The bell is yellow, and the game already rings one to
## start a fight.
func show_muted(is_muted: bool) -> void:
	_sound_button.text = "🔕" if is_muted else "🔔"


## Marks the speed the fight is actually running at.
##
## Driven off the bus rather than only by the buttons' own handler, because the
## speed can be changed without touching them — the 1/2/4 keys and the dev menu
## both do — and a toggle showing a speed the run is not at is worse than no
## toggle at all.
func show_speed(value: int) -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].button_pressed = SPEEDS[i] == value


func _select_speed(value: int) -> void:
	show_speed(value)
	speed_changed.emit(value)


func refresh() -> void:
	_hp.text = str(maxi(0, GameState.player.hp))
	_gold.text = str(GameState.player.gold)
	_streak.text = GameState.player.streak_label()
	_streak.add_theme_color_override("font_color",
		Color("ffb15c") if absi(GameState.player.streak) >= 3 else UITheme.FOAM)
	_write_stage()


const PHASE_NAMES := {
	GameState.Phase.PLAN: "PLANNING",
	GameState.Phase.COMBAT: "BATTLE",
	GameState.Phase.RESULT: "AFTERMATH",
	GameState.Phase.ARMOURY: "ARMOURY",
	GameState.Phase.OVER: "FINISHED",
}


func _on_phase_changed(phase: int) -> void:
	# Leaving combat drops the mark with it, so the next round does not open
	# still claiming to be in overtime.
	if phase != GameState.Phase.COMBAT:
		_overtime = false
		_overtime_mark = ""
	_write_phase(phase)
	refresh()


func _write_phase(phase: int = -1) -> void:
	var at: int = GameState.phase if phase < 0 else phase
	if _overtime and at == GameState.Phase.COMBAT:
		_phase.text = "OVERTIME"
		_phase.add_theme_color_override("font_color", Color("ff9d5c"))
		return
	_phase.text = PHASE_NAMES.get(at, "")
	_phase.add_theme_color_override("font_color",
		Color("ff9d9d") if at == GameState.Phase.COMBAT else UITheme.FOAM)
