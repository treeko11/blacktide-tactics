class_name DpsPanel
extends VBoxContainer

## The DPS meter: who dealt the damage, who took it, and who healed it back.
##
## Three tabs over one list, because they are three readings of the same fight
## and three panels would be three places to keep in step. The tab picks which
## number sorts the rows and fills the bars; nothing else about the list changes.
##
## **It reads the fight back, it does not remember it.** The same rule the
## inspector learned: text built once when the panel opened is a photograph, and
## a meter photographed at the start of a fight is a meter reading zero for the
## whole fight. `refresh()` re-reads `GameState.battle_stats()` on a timer and
## writes into the rows it already has, rather than rebuilding them — a rebuild
## ten times a second is the allocation churn `FxLayer` exists to avoid, and it
## would also throw away the scroll position on every tick.
##
## Rows are keyed by uid and only rebuilt when the *set* of combatants changes,
## which in practice is once per fight. Ordering is a `move_child` per tick.
##
## The bars are scaled against the largest value across **both** fleets, so the
## two sides are read against each other rather than each against itself. A
## meter where the enemy's best and yours both draw a full bar answers nothing.

## Which number the tab shows. The keys are the ones `Sim.stats()` reports.
const TABS := [
	{ "key": &"dealt",  "label": "DAMAGE",  "color": Color("ff9d5c") },
	{ "key": &"taken",  "label": "TAKEN",   "color": Color("ff7d7d") },
	{ "key": &"healed", "label": "HEALING", "color": Color("7dffb0") },
]

## Ten times a second. Fast enough that a number never looks stuck, slow enough
## that it is not doing layout work every frame of a 4x fight.
const REFRESH_SECONDS := 0.1

## Which tab was last read, kept across openings. `Modals` frees its content when
## the dialog closes, so a plain field would drop the player back on DAMAGE every
## time — including when they close the meter to watch a moment of the fight and
## open it straight back up.
static var _last_tab: StringName = &"dealt"

var _tab: StringName = &"dealt"
var _tab_buttons: Array[Button] = []

var _summary: Label = null
var _mine: VBoxContainer = null
var _theirs: VBoxContainer = null
var _mine_head: Label = null
var _theirs_head: Label = null
var _empty: Label = null

## uid -> StatRow, so a refresh writes into the row that is already on screen.
var _rows: Dictionary = {}
var _since_refresh: float = 0.0


func _init() -> void:
	_tab = _last_tab
	add_theme_constant_override("separation", 6)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(tabs)

	for spec in TABS:
		var key: StringName = spec["key"]
		var button := UITheme.button(spec["label"], UITheme.FONT_SMALL)
		button.toggle_mode = true
		button.button_pressed = key == _tab
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): show_tab(key))
		tabs.add_child(button)
		_tab_buttons.append(button)

	_summary = UITheme.label("", UITheme.FONT_SMALL, UITheme.MUTED)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_summary)

	_mine_head = UITheme.label("YOUR FLEET", UITheme.FONT_TINY, UITheme.FOAM)
	add_child(_mine_head)
	_mine = VBoxContainer.new()
	_mine.add_theme_constant_override("separation", 2)
	add_child(_mine)

	_theirs_head = UITheme.label("THE ENEMY", UITheme.FONT_TINY, Color("ff9d9d"))
	add_child(_theirs_head)
	_theirs = VBoxContainer.new()
	_theirs.add_theme_constant_override("separation", 2)
	add_child(_theirs)

	# Shown instead of the two lists before the first fight of a run, when there
	# is genuinely nothing to report rather than nothing worth reporting.
	_empty = UITheme.label("No fight to report yet. The meter fills in from the "
		+ "first broadside.", UITheme.FONT_SMALL, UITheme.MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_empty)


func _ready() -> void:
	set_process(true)
	refresh()


func _process(delta: float) -> void:
	# A meter nobody is looking at costs nothing. The dialog hosting this is
	# hidden rather than freed, so without the check it would keep re-reading a
	# fight through every planning phase of the run.
	if not is_visible_in_tree():
		return
	_since_refresh += delta
	if _since_refresh < REFRESH_SECONDS:
		return
	_since_refresh = 0.0
	refresh()


## Switches tab. Public so `screenshot.gd` can photograph all three and prove the
## two nobody looks at first are not broken.
func show_tab(key: StringName) -> void:
	_tab = key
	_last_tab = key
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = TABS[i]["key"] == key
	refresh()


# =============================================================================
#  Reading the fight back
# =============================================================================

func refresh() -> void:
	var stats: Array = GameState.battle_stats()
	var duration: float = GameState.battle_duration()

	var showing := not stats.is_empty()
	_empty.visible = not showing
	_mine_head.visible = showing
	_theirs_head.visible = showing
	if not showing:
		_summary.text = ""
		_clear_rows()
		return

	_sync_rows(stats)

	# One scale for both fleets: a bar has to mean the same thing on either side
	# of the line or the comparison the panel exists for cannot be made.
	var peak := 0.0
	var mine_total := 0.0
	var theirs_total := 0.0
	for row in stats:
		var value: float = row[_tab]
		peak = maxf(peak, value)
		if int(row["team"]) == Sim.Team.PLAYER:
			mine_total += value
		else:
			theirs_total += value

	var colour: Color = _tab_colour()
	for row in stats:
		var widget: StatRow = _rows[int(row["uid"])]
		widget.show_stat(row, row[_tab], peak, colour)

	_order(_mine, stats, Sim.Team.PLAYER)
	_order(_theirs, stats, Sim.Team.ENEMY)

	_theirs_head.text = GameState.opponent_name.to_upper()
	_summary.text = "%s  ·  you %s  ·  them %s  ·  %s" % [
		_elapsed(duration), _amount(mine_total), _amount(theirs_total),
		_rate(mine_total, duration),
	]


## Builds a row per combatant, but only when the cast list actually changed —
## once per fight, not ten times a second.
func _sync_rows(stats: Array) -> void:
	var wanted := {}
	for row in stats:
		wanted[int(row["uid"])] = row

	var same := wanted.size() == _rows.size()
	if same:
		for uid in wanted:
			if not _rows.has(uid):
				same = false
				break
	if same:
		return

	_clear_rows()
	for row in stats:
		var widget := StatRow.new()
		_rows[int(row["uid"])] = widget
		if int(row["team"]) == Sim.Team.PLAYER:
			_mine.add_child(widget)
		else:
			_theirs.add_child(widget)


## Detached before freeing, not just freed. `queue_free()` is deferred, so a row
## dropped that way is still a child — and still holding an index — for the rest
## of the frame. `_sync_rows` refills immediately after calling this, and the
## reordering that follows would count the corpses.
func _clear_rows() -> void:
	for box in [_mine, _theirs]:
		for child in box.get_children():
			box.remove_child(child)
			child.queue_free()
	_rows.clear()


## Sorts one fleet's rows by the active tab, biggest first.
func _order(box: VBoxContainer, stats: Array, team: int) -> void:
	var ours: Array = []
	for row in stats:
		if int(row["team"]) == team:
			ours.append(row)
	ours.sort_custom(func(a, b): return a[_tab] > b[_tab])
	for i in ours.size():
		var widget: StatRow = _rows[int(ours[i]["uid"])]
		if widget.get_parent() == box and widget.get_index() != i:
			box.move_child(widget, i)


## How many combatants the meter is showing.
##
## Public so `screenshot.gd` can check the panel actually built its rows without
## naming `DpsPanel`. A `--script` target that names this class pulls it into the
## tool's compile graph, where the `GameState` global does not resolve and the
## whole class fails to compile — see the headless gotchas in CLAUDE.md.
func row_count() -> int:
	return _rows.size()


## Whether the dialog hosting this got squeezed. `Modals` caps its box at 520
## points and takes the screen's width below that, so this is the same test.
static func _narrow() -> bool:
	return Layout.css_size.x < 544.0


func _tab_colour() -> Color:
	for spec in TABS:
		if spec["key"] == _tab:
			return spec["color"]
	return UITheme.INK


# --- formatting --------------------------------------------------------------

## Thousands as "12.4k". A five-figure damage total is unreadable in full and the
## bar beside it already carries the comparison.
static func _amount(value: float) -> String:
	if value >= 10000.0:
		return "%.1fk" % (value / 1000.0)
	return str(roundi(value))


static func _elapsed(seconds: float) -> String:
	return "%.1fs" % seconds


static func _rate(total: float, seconds: float) -> String:
	if seconds <= 0.1:
		return "–/s"
	return "%s/s" % _amount(total / seconds)


# =============================================================================
#  One combatant's line
# =============================================================================

class StatRow extends PanelContainer:
	var _icon: Label = null
	var _name: Label = null
	var _star: Label = null
	var _bar: ProgressBar = null
	var _value: Label = null
	var _fill := StyleBoxFlat.new()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel",
			UITheme.panel_style(Color("0a1c27"), UITheme.LINE, 4))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)

		_icon = Label.new()
		_icon.add_theme_font_override("font", UITheme.emoji_font())
		_icon.add_theme_font_size_override("font_size", 12)
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_icon)

		_name = UITheme.label("", UITheme.FONT_SMALL, UITheme.INK)
		_name.clip_text = true
		# A fixed share of the row rather than the name's own width, so the bars
		# all start at the same x and can be read as a column.
		#
		# Chosen by the width of the screen and **not** by `Layout.compact()`, for
		# the reason the almanac learned: compact says the HUD reflowed, it does
		# not say the screen is narrow. A phone held sideways is 844 points wide
		# and hosts this dialog at its full 520 — giving it the phone's 78-point
		# column there clipped "Old Anchor Ned" with 200 points to spare.
		_name.custom_minimum_size = Vector2(78 if DpsPanel._narrow() else 132, 0)
		row.add_child(_name)

		# The star rating gets its own column rather than being appended to the
		# name. Inside the clipped name it was the half that got cut — "Barnaby
		# Kegg 2*" came out as "Barnaby Kegg .", which reads as a typo rather than
		# as a name that ran out of room. A 1-star pirate leaves it blank, and the
		# column still holds the bars in line.
		_star = UITheme.label("", UITheme.FONT_TINY, UITheme.GOLD)
		_star.custom_minimum_size = Vector2(20, 0)
		row.add_child(_star)

		# The bar takes the slack. It is a ProgressBar rather than a drawn rect
		# because it already knows how to fill a container it does not own.
		_bar = ProgressBar.new()
		_bar.show_percentage = false
		_bar.max_value = 1.0
		_bar.custom_minimum_size = Vector2(0, 10)
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.add_theme_stylebox_override("background",
			UITheme.panel_style(Color("07131b"), UITheme.LINE, 3))
		_fill.corner_radius_top_left = 3
		_fill.corner_radius_top_right = 3
		_fill.corner_radius_bottom_left = 3
		_fill.corner_radius_bottom_right = 3
		_bar.add_theme_stylebox_override("fill", _fill)
		row.add_child(_bar)

		_value = UITheme.label("0", UITheme.FONT_SMALL, UITheme.INK)
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_value.custom_minimum_size = Vector2(46, 0)
		row.add_child(_value)

	## `peak` is the biggest value on either fleet, so every bar shares a scale.
	func show_stat(row: Dictionary, value: float, peak: float, colour: Color) -> void:
		_icon.text = row["icon"]
		var name_text: String = row["name"]
		# Assigned only when it differs: writing a Label's text re-shapes the line
		# and re-runs layout, and this is called ten times a second.
		if _name.text != name_text:
			_name.text = name_text

		var star: int = int(row["star"])
		var star_text := "" if star <= 1 else "%d%s" % [star, UITheme.STAR]
		if _star.text != star_text:
			_star.text = star_text

		var alive: bool = row["alive"]
		modulate.a = 1.0 if alive else 0.45

		_fill.bg_color = colour
		_bar.value = 0.0 if peak <= 0.0 else clampf(value / peak, 0.0, 1.0)

		var shown := DpsPanel._amount(value)
		if _value.text != shown:
			_value.text = shown
		_value.add_theme_color_override("font_color",
			colour if value > 0.0 else UITheme.MUTED)
