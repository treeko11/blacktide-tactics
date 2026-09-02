class_name DevMenu
extends Control

## **DEV BUILD ONLY.** The cheat panel. See `dev.gd` for how to remove all this.
##
## It attaches itself to the scene tree *root*, as a sibling of `Main` rather
## than a child of it. Two things follow from that, both of them the point:
## `main.gd` needs no hook, so removing this folder cannot break a compile; and
## the HUD rebuild that a phone rotation triggers throws away all of `Main`'s
## children without touching this, so the menu survives a rotation for free.
##
## **This is the one place allowed to break the "Main is the only place that
## mutates GameState" rule.** A cheat panel is by definition a second path from a
## click to a change — that is what it is for — and routing it through `Main`
## would spread code that has to be deleted later across a file that stays. So it
## calls `GameState` directly, and it is all in this one file.
##
## The opener is a small chip in the bottom-right corner. That corner is the only
## one that is read-only in all three layouts: it is the log on a desktop and the
## shop's gold panel on a phone, where every other corner is either a shop card,
## a bench slot, a board hex or the speed buttons. It is draggable anyway, so
## when it does sit over something being tested it can be moved rather than
## worked around.

## How far the chip may move before a press counts as a drag rather than a tap.
const DRAG_SLOP := 6.0

const CHIP_SIZE := Vector2(38, 20)
const CHIP_MARGIN := Vector2(6, 6)

## Sim steps drained per frame while skipping a fight. Enough to finish most
## fights inside two frames without freezing on a long one.
const SKIP_STEPS := 600

var _chip: Button = null
var _scrim: ColorRect = null
var _panel: PanelContainer = null
var _content: VBoxContainer = null
var _scroll: ScrollContainer = null
var _status: Label = null

var _open := false
var _page: StringName = &"root"

## The star a champion picked from the roster page is spawned at.
var _spawn_star := 1

var _freeze_clock := false

## Set while a fight is being fast-forwarded, with the speed and instant flag it
## has to put back when the round lands.
var _skipping := false
var _saved_speed := 1
var _saved_instant := false

## The screen the chip and panel were last sized against. A phone rotation
## changes it, and everything here is positioned from it.
var _last_screen := Vector2.ZERO

var _dragging := false
var _drag_from := Vector2.ZERO
var _chip_from := Vector2.ZERO
var _drag_distance := 0.0

## Whether the chip is somewhere the player chose. Until it is, a re-fit returns
## it to its corner rather than clamping it — see `_fit_to_screen`.
var _chip_moved := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The overlay itself must never take a click: only the chip and, once it is
	# open, the panel. This is the rule a toast broke twice — a full-rect Control
	# left on STOP is an invisible blocker over the whole game.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.game_theme()

	_build_chip()
	_build_panel()
	set_process(true)


# =============================================================================
#  The opener
# =============================================================================

## The screen, in the coordinates the Controls in here are positioned in.
##
## **Not `Layout.css_size`**, which is the window in CSS pixels and only agrees
## with this on a phone. The wide layout keeps the 1600x900 content scale and
## stretches it with `expand`, so a 2000x1004 window is a *1793x900* coordinate
## space — and a chip placed at `css_size - 44` sat 163 units past its right edge
## and 78 below its bottom. The DEV chip was off screen on every desktop window
## except exactly 1600x900, which is the one size `screenshot.gd` renders at, so
## neither the tool nor `test_dev` — measuring against `css_size` as well — ever
## saw it. The rule the whole file now follows: `css_size` decides *which* layout
## is built, the viewport decides *where* a thing goes.
func _screen() -> Vector2:
	return get_viewport_rect().size


func _build_chip() -> void:
	_chip = UITheme.button("DEV", UITheme.FONT_TINY)
	_chip.custom_minimum_size = CHIP_SIZE
	_chip.modulate.a = 0.62
	_chip.tooltip_text = ""
	add_child(_chip)

	# From the size the button really takes, not `CHIP_SIZE`: the theme's font and
	# padding set a minimum the nominal size loses to, and positioning from the
	# nominal one put the chip flush against the bottom edge of a phone with no
	# margin at all.
	_chip.position = _screen() - _chip.get_combined_minimum_size() - CHIP_MARGIN
	_chip.gui_input.connect(_on_chip_input)


## Tap opens, drag moves.
##
## A dev button in a fixed corner is a dev button that eventually sits on top of
## the exact thing being tested. Distinguishing the two by distance rather than
## by time keeps a tap instant.
func _on_chip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_distance = 0.0
			_drag_from = event.global_position
			_chip_from = _chip.position
		elif _dragging:
			_dragging = false
			if _drag_distance <= DRAG_SLOP:
				_toggle(not _open)
	elif event is InputEventMouseMotion and _dragging:
		var moved: Vector2 = (event as InputEventMouseMotion).global_position - _drag_from
		_drag_distance = maxf(_drag_distance, moved.length())
		if _drag_distance > DRAG_SLOP:
			var room := _screen() - _chip.get_combined_minimum_size()
			_chip.position = (_chip_from + moved).clamp(Vector2.ZERO, room)
			# From here on the chip is where it was *put*, and a re-fit may only
			# clamp it. Until then it is only where it landed, and a re-fit is
			# free to put it back in its corner.
			_chip_moved = true


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	# Backquote is the console key everywhere; F12 is the one a laptop without a
	# backquote still has. Neither is bound by the game.
	if event.keycode == KEY_QUOTELEFT or event.keycode == KEY_F12:
		_toggle(not _open)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _open:
		_toggle(false)
		get_viewport().set_input_as_handled()


func _toggle(open: bool) -> void:
	_open = open
	_scrim.visible = open
	_panel.visible = open
	_chip.visible = not open
	if open:
		_page = &"root"
		_rebuild()


# =============================================================================
#  The panel
# =============================================================================

func _build_panel() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Color(0, 0, 0, 0.66)
	_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_scrim.visible = false
	# A press outside the panel closes it — but **a wheel notch is a
	# `InputEventMouseButton` with `pressed` true**, and the menu is taller than
	# it fits, so scrolling to reach the bottom of it closed it instead. Every
	# section below the fold, the playtest log included, was unreachable with a
	# wheel. Only the buttons that are buttons dismiss it.
	const DISMISSES := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
	_scrim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and DISMISSES.has((event as InputEventMouseButton).button_index):
			_toggle(false))
	add_child(_scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.add_theme_stylebox_override("panel",
		UITheme.panel_style(Color("1a1206"), UITheme.GOLD, 10))
	# Same sizing rule the real dialogs use: never wider than the screen, never
	# taller than most of it. A phone is the narrow case and it is the one that
	# matters, because it is where the playtests are.
	_panel.custom_minimum_size = Vector2(minf(520.0, _screen().x - 20.0), 0)
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centre.add_child(_panel)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	_panel.add_child(stack)

	var header := HBoxContainer.new()
	stack.add_child(header)
	header.add_child(UITheme.label("DEV MENU", UITheme.FONT_TITLE, UITheme.GOLD_BRIGHT))
	header.add_child(UITheme.spacer())
	var close := UITheme.button("CLOSE", UITheme.FONT_SMALL)
	close.pressed.connect(func() -> void: _toggle(false))
	header.add_child(close)

	_status = UITheme.label("", UITheme.FONT_TINY, UITheme.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, minf(420.0, _screen().y * 0.62))
	stack.add_child(scroll)

	_scroll = scroll

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)

	_last_screen = _screen()


func _rebuild() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()

	match _page:
		&"champions":
			_build_champion_page()
		&"items":
			_build_item_page()
		_:
			_build_root_page()
	_refresh_status()


func _refresh_status() -> void:
	var where := ProjectSettings.globalize_path(Dev.log_path)
	if Dev.log_path == "":
		# It said "memory only" here, which stopped being true when the log
		# started going into browser storage a line at a time — and which was the
		# discouraging half of the message, since memory is precisely what a
		# freeze takes with it.
		where = "log kept in browser storage" if Dev.store != null \
			else "log in memory only (no browser storage)"
	_status.text = "%d-%d %s  ·  level %d  ·  %d gold  ·  %d hull\n%d log lines  ·  %s" % [
		GameState.stage, GameState.round_number, String(GameState.round_type()),
		GameState.player.level, GameState.player.gold, GameState.player.hp,
		Dev.lines.size(), where]


# --- the sections ------------------------------------------------------------

func _build_root_page() -> void:
	var economy := _section("ECONOMY")
	_row(economy, [
		["+10 GOLD", func() -> void: _gold(10)],
		["+50 GOLD", func() -> void: _gold(50)],
		["GOLD 0", func() -> void: _gold(-GameState.player.gold)],
		["FREE ROLL", _free_roll],
	])
	_row(economy, [
		["+4 XP", func() -> void: _xp(GameState.XP_PER_PURCHASE)],
		["LEVEL UP", _level_up],
		["MAX LEVEL", _max_level],
	])
	_row(economy, [
		["FULL HULL", func() -> void: _hull(100 - GameState.player.hp)],
		["-10 HULL", func() -> void: _hull(-10)],
	])
	economy.add_child(UITheme.label("SET LEVEL", UITheme.FONT_TINY, UITheme.MUTED))
	var levels: Array = []
	for n in range(1, Captain.MAX_LEVEL + 1):
		levels.append([str(n), func() -> void: _set_level(n)])
	_row(economy, levels)

	var fleet := _section("FLEET AND CARGO")
	_row(fleet, [
		["SPAWN PIRATE »", func() -> void: _go(&"champions")],
		["GRANT ITEM »", func() -> void: _go(&"items")],
	])
	_row(fleet, [
		["CLEAR FLEET", _clear_fleet],
		["EMPTY HOLD", _clear_hold],
	])

	var round_box := _section("ROUND")
	_row(round_box, [
		["UNFREEZE CLOCK" if _freeze_clock else "FREEZE CLOCK", _toggle_freeze],
		["+30s", func() -> void: _add_time(30.0)],
	])
	_row(round_box, [
		["END PLANNING", _end_planning],
		["SKIP FIGHT", _skip_fight],
	])
	_note_line(round_box, "JUMP TO STAGE pays the income and gives the bots the "
		+ "turns for every round skipped, but nobody fights. For looking at a "
		+ "late board, not for judging a matchup.")
	var stages: Array = []
	for n in range(2, 9):
		stages.append([str(n), func() -> void: _jump_to_stage(n)])
	_row(round_box, stages)

	var log_box := _section("PLAYTEST LOG")
	_row(log_box, [
		["COPY LOG", _copy_log],
		["DOWNLOAD LOG", _download_log],
		["MARK", _mark],
	])
	_note_line(log_box, "MARK drops a divider in the log, for pointing at the "
		+ "moment something went wrong.")

	# Only when there is something to recover, which on the desktop is never:
	# there the log is a file that outlived whatever happened to the game.
	if not Dev.recovered.is_empty():
		var ended: String = "ended cleanly" if bool(Dev.recovered.get("clean", false)) \
			else "STOPPED DEAD"
		_row(log_box, [["RECOVER LAST (%d)" % int(Dev.recovered.get("count", 0)),
			_recover_log]])
		_note_line(log_box, "The previous session %s. Its log survived in browser "
			% ended + "storage, which is the only copy a freeze or a crash leaves "
			+ "behind — the buttons above can only reach this run's.")


func _build_champion_page() -> void:
	_back_row("SPAWN A PIRATE")

	var stars := HBoxContainer.new()
	stars.add_theme_constant_override("separation", 4)
	stars.add_child(UITheme.label("AT", UITheme.FONT_TINY, UITheme.MUTED))
	for star in [1, 2, 3]:
		var button := UITheme.button("%d%s" % [star, UITheme.STAR], UITheme.FONT_SMALL)
		if star == _spawn_star:
			button.add_theme_color_override("font_color", UITheme.GOLD_BRIGHT)
		button.pressed.connect(func() -> void:
			_spawn_star = star
			_rebuild())
		stars.add_child(button)
	# Taking the real cost out of the shared pool is what keeps a dev spawn from
	# quietly draining a champion out of everyone's shop for the rest of the run.
	_content.add_child(stars)
	_note_line(_content, "Costs the pool %d %s, exactly as merging that many "
		% [_copies_for(_spawn_star), "copy" if _spawn_star == 1 else "copies"]
		+ "bought copies would. Greyed out means the pool is short.")

	var grid := GridContainer.new()
	grid.columns = 2 if Layout.compact() else 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)

	var champions: Array = GameState.content.shop_champions().duplicate()
	champions.sort_custom(func(a: ChampionDef, b: ChampionDef) -> bool:
		if a.cost != b.cost:
			return a.cost < b.cost
		return a.display_name < b.display_name)

	for def: ChampionDef in champions:
		var left := GameState.copies_left(def.id)
		var button := UITheme.button("%s %s  %d%s" % [def.icon, def.display_name,
			def.cost, UITheme.COIN], UITheme.FONT_TINY)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = left < _copies_for(_spawn_star)
		button.add_theme_color_override("font_color",
			UITheme.cost_color(def.cost))
		button.pressed.connect(func() -> void: _spawn(def.id))
		grid.add_child(button)


func _build_item_page() -> void:
	_back_row("GRANT AN ITEM")

	for group in [["COMPONENTS", GameState.content.components()],
			["FORGED", GameState.content.forged_items()]]:
		_content.add_child(UITheme.label(group[0], UITheme.FONT_TINY, UITheme.MUTED))
		var grid := GridContainer.new()
		grid.columns = 2 if Layout.compact() else 3
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		_content.add_child(grid)
		for def: ItemDef in group[1]:
			var button := UITheme.button("%s %s" % [def.icon, def.display_name],
				UITheme.FONT_TINY)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.pressed.connect(func() -> void: _grant(def.id))
			grid.add_child(button)


# --- small builders ----------------------------------------------------------

## A wrapping line of explanation.
##
## Wrapping is not decoration here. A `Label` reports its whole unwrapped line as
## its minimum width, and the panel is sized from its contents, so one unwrapped
## sentence dragged the menu out to 772 points on a 390-point phone — off both
## edges of the screen it is meant to be used on.
func _note_line(into: VBoxContainer, text_: String) -> void:
	var label := UITheme.label(text_, UITheme.FONT_TINY, UITheme.MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(0, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	into.add_child(label)


func _section(title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UITheme.label(title, UITheme.FONT_SMALL, UITheme.GOLD))
	_content.add_child(box)
	return box


## One wrapping row of buttons, each `[label, Callable]`.
func _row(into: VBoxContainer, entries: Array) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	into.add_child(row)
	for entry in entries:
		var button := UITheme.button(entry[0], UITheme.FONT_SMALL)
		var action: Callable = entry[1]
		button.pressed.connect(func() -> void:
			action.call()
			# Every action changes something the header reports, and several
			# change what the page should offer next.
			if _open:
				_rebuild())
		row.add_child(button)


func _back_row(title: String) -> void:
	var row := HBoxContainer.new()
	var back := UITheme.button("« BACK", UITheme.FONT_SMALL)
	back.pressed.connect(func() -> void: _go(&"root"))
	row.add_child(back)
	row.add_child(UITheme.label(title, UITheme.FONT_SMALL, UITheme.GOLD))
	_content.add_child(row)


func _go(page: StringName) -> void:
	_page = page
	_rebuild()


# =============================================================================
#  Per-frame work
# =============================================================================

func _process(_delta: float) -> void:
	var screen := _screen()
	if _last_screen != screen:
		_last_screen = screen
		_fit_to_screen(screen)

	# Pinning the clock rather than pausing it: `GameState` owns the countdown
	# and there is no way to stop it from outside without editing game code, but
	# putting it back every frame is indistinguishable from the outside.
	if _freeze_clock and GameState.phase == GameState.Phase.PLAN:
		GameState.plan_timer = GameState.PLAN_SECONDS

	if _skipping:
		_drain_fight()


## Re-fits everything to the screen after a rotation.
##
## `Main` handles a rotation by throwing its whole HUD away and building the
## other one. This menu is not one of its children, which is what lets it survive
## a rotation — but surviving is not the same as still fitting. Every size here
## comes from `_screen()`, and on a phone turned sideways that goes from 390 wide
## to 844 and back. Left alone, a chip parked in the bottom-right corner of a
## landscape screen sits at x=800, which is off the right-hand edge of the
## portrait one: the dev menu would become unreachable on exactly the device it
## exists for, and only after a rotation, which is the hardest way to find it.
##
## A chip the player dragged somewhere is clamped, so it stays as close to where
## they put it as the new screen allows. **A chip they have not touched is put
## back in its corner instead**, and the difference is not cosmetic: a clamp only
## ever moves a chip when the screen *shrinks*, so a chip placed against a screen
## that was too small stays exactly where it was when the screen grows.
##
## That is not hypothetical. A browser reports its window as 64x64 for the first
## frames, before the canvas is sized — so the menu is built against a 64-point
## screen, parks the chip at (34, 45), and the real size arriving a frame later
## leaves it there: sitting on top of the HUD in the top-left corner, for the
## whole session, in every web build. Nothing was wrong with the corner it chose,
## only with the screen it measured, and re-measuring is what a re-fit is for.
##
## The size is a parameter so a test can hand it one, rather than having to move
## a real window to ask the question.
func _fit_to_screen(screen: Vector2 = _screen()) -> void:
	var room := screen - _chip.get_combined_minimum_size()
	_chip.position = _chip.position.clamp(Vector2.ZERO, room) if _chip_moved \
		else (room - CHIP_MARGIN).max(Vector2.ZERO)
	_panel.custom_minimum_size = Vector2(minf(520.0, screen.x - 20.0), 0)
	_scroll.custom_minimum_size = Vector2(0, minf(420.0, screen.y * 0.62))
	# The grids are one width on a phone and another on a desktop, and a rotation
	# crosses that breakpoint.
	if _open:
		_rebuild()


func _drain_fight() -> void:
	if GameState.phase == GameState.Phase.COMBAT:
		var sim: Sim = GameState.sim
		if sim != null and not sim.done:
			var steps := 0
			while not sim.done and steps < SKIP_STEPS:
				sim.step()
				steps += 1
		return

	# The fight has landed and been resolved. `instant` took the result and
	# post-combat pauses to zero, so this is the next planning phase already.
	if GameState.phase != GameState.Phase.RESULT:
		_skipping = false
		GameState.speed = _saved_speed
		GameState.instant = _saved_instant
		Dev.record(&"DEV", "skip finished")


# =============================================================================
#  The actions
# =============================================================================

func _note(what: String) -> void:
	Dev.record(&"DEV", what)


func _gold(amount: int) -> void:
	if amount >= 0:
		GameState.gain_gold(amount)
	else:
		GameState.spend_gold(-amount)
	_note("gold %+d" % amount)


func _xp(amount: int) -> void:
	GameState.player.add_xp(amount)
	Events.level_changed.emit(GameState.player.level, GameState.player.xp,
		GameState.player.xp_needed())
	_note("xp %+d" % amount)


func _level_up() -> void:
	if GameState.player.is_max_level():
		return
	_xp(GameState.player.xp_needed() - GameState.player.xp)


func _max_level() -> void:
	while not GameState.player.is_max_level():
		_level_up()


func _set_level(level: int) -> void:
	# Downwards as well as up, which no amount of XP can do — a dev menu that can
	# only go one way cannot get back to the level a bug was reported at.
	GameState.player.level = clampi(level, 1, Captain.MAX_LEVEL)
	GameState.player.xp = 0
	Events.level_changed.emit(GameState.player.level, 0,
		GameState.player.xp_needed())
	Events.board_changed.emit()
	_note("level set to %d" % GameState.player.level)


func _hull(delta: int) -> void:
	GameState.player.hp = clampi(GameState.player.hp + delta, 1, 100)
	Events.health_changed.emit(GameState.player.hp, delta)
	_note("hull %+d" % delta)


func _free_roll() -> void:
	GameState.refresh_shop(true)
	_note("free shop roll")


func _copies_for(star: int) -> int:
	return int(pow(3, star - 1))


## Spawns onto the bench, taking the real number of copies out of the shared
## pool: three for a two-star, nine for a three-star, exactly as merging would.
##
## Doing it any other way is how a dev menu silently drains a champion out of
## every captain's shop for the rest of the run, which `test_economy` exists to
## catch and which would then be blamed on the shop.
func _spawn(champion_id: StringName) -> void:
	var needed := _copies_for(_spawn_star)
	if GameState.copies_left(champion_id) < needed:
		GameState.notify("Pool has only %d left" % GameState.copies_left(champion_id))
		return
	var slot := GameState.first_free_bench_slot()
	if slot < 0:
		GameState.notify("The bench is full")
		return

	for i in needed:
		GameState.take_from_pool(champion_id)

	var def: ChampionDef = GameState.content.champion(champion_id)
	var unit := RosterUnit.new(def, _spawn_star)
	GameState.bench[slot] = unit
	_note("spawned %s at %d-star" % [def.display_name, _spawn_star])

	# A third one-star still merges, the same as buying it would.
	GameState._check_upgrades()
	Events.board_changed.emit()


func _grant(item_id: StringName) -> void:
	GameState.give_item(item_id, &"salvage")
	var def: ItemDef = GameState.content.item_def(item_id)
	_note("granted %s" % def.display_name)


func _clear_fleet() -> void:
	var count := 0
	for unit in GameState.owned_units():
		# Back to the pool at the right weight, or clearing the board would eat
		# the copies instead of returning them.
		GameState.return_to_pool(unit.id(), unit.star)
		count += 1
	GameState.board.clear()
	for i in GameState.bench.size():
		GameState.bench[i] = null
	Events.board_changed.emit()
	_note("cleared the fleet (%d pirates returned to the pool)" % count)


func _clear_hold() -> void:
	var count := GameState.player.items.size()
	GameState.player.items.clear()
	Events.board_changed.emit()
	_note("emptied the hold (%d items)" % count)


func _toggle_freeze() -> void:
	_freeze_clock = not _freeze_clock
	_note("clock %s" % ("frozen" if _freeze_clock else "running"))


func _add_time(seconds: float) -> void:
	GameState.plan_timer += seconds
	_note("clock +%ds" % int(seconds))


func _end_planning() -> void:
	GameState.start_combat_now()
	_note("planning ended early")


## Ends planning if it is still running, then fast-forwards the fight itself.
##
## `instant` is the flag the balance tools already use to take the post-combat
## and result pauses to zero; the sim is drained a few hundred steps a frame in
## `_drain_fight`. Both are put back when the next planning phase arrives.
func _skip_fight() -> void:
	if _skipping:
		return
	if GameState.phase == GameState.Phase.PLAN:
		GameState.start_combat_now()
	elif GameState.phase != GameState.Phase.COMBAT:
		GameState.notify("Nothing to skip")
		return
	_skipping = true
	_saved_speed = GameState.speed
	_saved_instant = GameState.instant
	GameState.instant = true
	GameState.speed = 4
	_toggle(false)
	_note("skipping the fight")


## Winds the run forward to the first round of `target`.
##
## This is a scenario jump, not a simulation: it pays the income and gives the
## bots the shopping turns for every round it passes, so the opponents are not
## still fielding a stage-1 board, but nobody fights. Good for looking at a late
## board and its economy, no use at all for judging a matchup.
func _jump_to_stage(target: int) -> void:
	if GameState.phase != GameState.Phase.PLAN:
		GameState.notify("Only between fights")
		return
	if target <= GameState.stage:
		GameState.notify("Already at stage %d" % GameState.stage)
		return

	var skipped := 0
	while GameState.stage < target and skipped < 100:
		var finished: StringName = GameState.round_type()
		skipped += 1

		GameState.round_number += 1
		if GameState.round_number > GameState.rounds_this_stage():
			GameState.round_number = 1
			GameState.stage += 1

		GameState.gain_gold(GameState.player.round_income(
			GameState.stage, GameState.round_number))
		GameState.player.add_xp(GameState.XP_PER_ROUND)

		for bot in GameState.bots:
			if not bot.alive:
				continue
			bot.grant_loot(finished, GameState, GameState.rng)
			bot.take_turn(GameState, finished)

	Events.level_changed.emit(GameState.player.level, GameState.player.xp,
		GameState.player.xp_needed())
	_note("jumped to stage %d (%d rounds skipped)" % [GameState.stage, skipped])

	# Announced through the normal door, so the HUD hears the new round the same
	# way it would have heard a real one.
	GameState._begin_planning()
	GameState.refresh_shop(true)


func _copy_log() -> void:
	Dev.copy_to_clipboard()
	GameState.notify("%d log lines copied" % Dev.lines.size(), &"good")


func _download_log() -> void:
	if not OS.has_feature("web"):
		GameState.notify("Already on disk: %s"
			% ProjectSettings.globalize_path(Dev.log_path), &"good")
		return
	Dev.download()


func _recover_log() -> void:
	if OS.has_feature("web"):
		Dev.download_recovered()
		return
	# Nowhere but the web ever fills this, but the clipboard is the honest
	# fallback if that changes: a download on the desktop is a file the player
	# has to be told the location of anyway.
	DisplayServer.clipboard_set(Dev.recovered_text())
	GameState.notify("Previous session copied", &"good")


func _mark() -> void:
	Dev.record(&"MARK", "---- marked by the player ----")
	GameState.notify("Marked the log", &"good")
