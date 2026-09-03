extends TestCase

## **DEV BUILD ONLY — delete this file with `scripts/dev/`.**
##
## The dev menu is a full-screen Control sitting on top of the entire game, which
## is the exact shape of the bug that has now cost this project two debugging
## sessions: a `Container` defaults to STOP where a `Label` defaults to IGNORE,
## so an overlay is only as transparent as its children, and one left hit-testable
## reads as the game ignoring the player rather than as a bug.
##
## A toast doing that was bad. The dev menu doing it would be worse — it covers
## the whole window, and it would look exactly like the game having frozen.


## Closed, the only thing in the overlay that may take a click is the DEV chip.
func test_the_closed_menu_only_hit_tests_its_own_chip() -> void:
	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	assert_eq(menu.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the overlay itself would swallow every click aimed at the game")

	var blockers := PackedStringArray()
	_collect_visible_blockers(menu, "DevMenu", blockers)
	assert_eq(blockers.size(), 1,
		"exactly the chip should be clickable while closed, got: %s"
		% ", ".join(blockers))

	menu.free()


## The chip has to stay on screen, and the screen is the *viewport*.
##
## This test used to measure against `Layout.css_size` — the same yardstick the
## menu positioned the chip with — so it passed while the chip was off screen on
## every desktop window that was not exactly 1600x900. `css_size` is the window
## in CSS pixels; the wide layout stretches a 1600x900 content scale to fill it,
## so a 2000x1004 window is a 1793x900 coordinate space and a chip at
## `css_size - 44` is 163 units past the right edge, invisible and unclickable.
##
## So `css_size` is set here to something the viewport deliberately is not, and
## the assertion is against the viewport.
func test_the_chip_sits_inside_the_screen() -> void:
	var was := Layout.css_size
	# A Variant off `get_main_loop()`, so the type is spelled out — the same trap
	# `content()` and `state()` carry.
	var screen: Vector2 = Engine.get_main_loop().root.get_visible_rect().size
	Layout.css_size = screen + Vector2(400, 104)

	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	var chip: Button = menu._chip
	var corner := chip.position + chip.get_combined_minimum_size()
	assert_gt(chip.position.x, 0.0, "the chip is off the left edge")
	assert_gt(chip.position.y, 0.0, "the chip is off the top edge")
	assert_true(corner.x <= screen.x and corner.y <= screen.y,
		"the chip corner %s is outside the %s viewport (it was placed from the %s css size)"
		% [corner, screen, Layout.css_size])

	menu.free()
	Layout.css_size = was


## Spawning must take the real cost out of the shared pool.
##
## A two-star is three copies and a three-star is nine, exactly as merging three
## bought copies would. Anything looser and a dev spawn silently drains a
## champion out of every captain's shop for the rest of the run — the same
## failure `test_economy` guards the real shop against, arriving through a door
## that test does not watch.
func test_spawning_pays_the_pool_the_same_as_buying_would() -> void:
	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	var game := state()
	var champion_id: StringName = game.content.shop_champions()[0].id
	var before: int = game.copies_left(champion_id)

	menu._spawn_star = 2
	menu._spawn(champion_id)

	assert_eq(game.copies_left(champion_id), before - 3,
		"a two-star spawn should cost the pool three copies")

	# And back again, at the same weight, so clearing the board is reversible.
	menu._clear_fleet()
	assert_eq(game.copies_left(champion_id), before,
		"clearing the fleet should return every copy it took")

	menu.free()


## Jumping forward has to land the run in a playable planning phase.
##
## It winds the round counter by hand rather than replaying rounds, which is the
## kind of shortcut that leaves the game between phases with no way forward — the
## armoury did exactly that once, and the run stopped dead there every time.
func test_jumping_to_a_stage_lands_in_planning() -> void:
	var game := state()
	game.start_game()

	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	var gold_before: int = game.player.gold
	menu._jump_to_stage(4)

	assert_eq(game.stage, 4, "it should have arrived at stage 4")
	assert_eq(game.round_number, 1, "a stage starts at its first round")
	assert_eq(game.phase, game.Phase.PLAN, "the run has to be playable afterwards")
	assert_gt(game.player.gold, gold_before,
		"the rounds it skipped should still have paid their income")

	menu.free()
	game.start_game()


## A jump draws the weather of the stage it arrives in.
##
## The stage draws its sea when the stage *opens*, and `_advance_round` was the
## only thing that crossed a stage line — so a jump carried the sea it left with
## and its lanes forward into a stage that never rolled. Jumping out of stage 1,
## which draws nothing at all, it carried nothing: the stage you landed on had no
## weather for the whole of it. Silent both ways, and this button exists to look
## at a late board, of which the weather is now a third of what there is to see.
func test_jumping_to_a_stage_draws_that_stage_weather() -> void:
	var game := state()
	game.start_game()
	assert_eq(game.sea_id, &"", "stage 1 should draw no weather to carry forward")

	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)
	menu._jump_to_stage(4)

	assert_ne(game.sea_id, &"", "stage 4 was jumped into with no weather at all")
	assert_not_null(content().sea(game.sea_id),
		"the jump left a sea id nothing defines: %s" % game.sea_id)

	# The forecast has to be live too. A sea id with no lanes behind it marks
	# nothing on the board, which is the half the player actually reads.
	#
	# Guarded rather than dereferenced. A GDScript error abandons the method and
	# returns to the runner as though it finished, so an unguarded `def.id` here
	# would skip the teardown below and hand the next test a dev menu still
	# parented to the root — which is exactly how this failed the first time it
	# was made to fail on purpose.
	game.round_number = game.SEA_ROUND
	var def: SeaDef = game.sea_def()
	if def != null:
		assert_true(game.sea_active(), "stage 4 does not report its own weather round")
		if def.marks_cells:
			assert_gt(float(game.sea_cells.size()), 0.0,
				"%s marks water and the jump drew none of it" % def.id)

	menu.free()
	game.start_game()


## Skipping a fight has to finish it and hand the speed controls back.
##
## It borrows `instant` and the speed multiplier to fast-forward, and a skip that
## returned without putting them back would leave every later fight resolving at
## 4x with no pauses — which reads as the game having broken, not as a leftover
## dev setting.
func test_skipping_a_fight_resolves_it_and_restores_the_speed() -> void:
	var game := state()
	game.start_game()
	game.speed = 2

	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	menu._skip_fight()
	assert_eq(game.phase, game.Phase.PLAN, "start_combat_now only sets the clock")

	var guard := 0
	while menu._skipping and guard < 2000:
		game._process(1.0 / 30.0)
		menu._drain_fight()
		guard += 1

	assert_false(menu._skipping, "the skip never finished")
	assert_eq(game.speed, 2, "the speed the player chose was not put back")
	assert_false(game.instant, "instant was left on")

	menu.free()
	game.start_game()


## A rotation must not strand the chip off the edge of the screen.
##
## `Main` survives a rotation by rebuilding; this menu survives it by not being
## one of Main's children. But everything here is positioned from the viewport,
## and a phone turned upright takes that from 844 wide to 390.
## A chip parked in the bottom-right corner of the landscape screen then sits at
## x=800, off the right-hand edge — the dev menu unreachable on the one device it
## exists for, and only after a rotation.
func test_the_chip_stays_reachable_after_a_rotation() -> void:
	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	# Parked in the bottom-right corner of a landscape phone, then turned
	# upright. The size is handed in rather than moved, because a test cannot
	# resize a headless window and the question has nothing to do with one.
	menu._chip.position = Vector2(800, 358)
	menu._fit_to_screen(Vector2(390, 844))

	var corner: Vector2 = menu._chip.position + menu._chip.get_combined_minimum_size()
	assert_true(corner.x <= 390.0 and corner.y <= 844.0,
		"the chip corner %s is off a 390x844 screen after rotating" % corner)
	assert_true(menu._panel.custom_minimum_size.x <= 390.0,
		"the panel is wider than the screen it rotated onto")

	menu.free()


## The log and the menu wait for the game to exist. They must not do it by
## counting.
##
## `Dev` used to record the root's child count during its own `_ready()` and wait
## for it to go up, on the reasoning that an autoload registered last sees only
## the autoloads. In a browser that is false — `Main` is already parented by
## then — so the count was captured one too high, nothing ever exceeded it, and
## `_boot()` never ran. The log, the DEV chip and the whole menu were absent from
## every web build, silently, on the only platform the playtesters use.
func test_the_game_is_found_by_asking_the_tree_not_by_counting_it() -> void:
	var root: Node = Engine.get_main_loop().root

	# The suite parents nothing of its own here, so what is under the root is the
	# autoloads — and the autoloads are not a game.
	assert_false(Dev._game_exists(),
		"an autoload reads as the game, so the log would boot before there is one")

	# The browser case. Nothing is going to *arrive*: it is already standing
	# there, and has to be recognised where it stands.
	var stand_in := Control.new()
	stand_in.name = "Main"
	root.add_child(stand_in)

	assert_true(Dev._game_exists(),
		"a game already under the root went unnoticed, which is the web bug")

	root.remove_child(stand_in)
	stand_in.free()


# =============================================================================
#  The web log
# =============================================================================
#
#  On the web the playtest log lives in the WASM heap, and the only two ways out
#  of it are Godot buttons. The export runs single-threaded, so a hang in the
#  game's main loop is a hang of the whole page: no button, no timer, no
#  JavaScript. A crash is worse — it takes the heap and the log together. Either
#  way the log was gone at exactly the moment it was worth reading, which is what
#  `DevStore` exists to fix.
#
#  None of that can be tested through a browser from here, so the storage is
#  injected and these drive the real class against a Dictionary. A store that
#  looks perfect and records nothing is the DPS-meter problem, so every
#  assertion below is on what came back out.


## Stands in for `localStorage`, with the same shape the browser backend has.
class FakeStorage:
	var data := {}

	func put(key: String, value: String) -> void:
		data[key] = value

	func take(key: String) -> Variant:
		return data.get(key, null)

	func drop(key: String) -> void:
		data.erase(key)


func _store(disk: FakeStorage) -> DevStore:
	return DevStore.new(disk.put, disk.take, disk.drop)


## The last line before the freeze is the whole point.
func test_the_store_holds_the_line_it_just_wrote() -> void:
	var disk := FakeStorage.new()

	var first := _store(disk)
	first.open()
	first.append("[00:00.0] RUN    started")
	first.append("[00:12.3] BUY    Old Anchor Ned")
	# No mark_clean: this is a session that stopped dead, which is the case
	# worth recovering.

	var next := _store(disk)
	next.open()
	var found := next.recover()

	assert_false(found.is_empty(), "nothing survived the session")
	assert_true(String(found.get("text", "")).ends_with("BUY    Old Anchor Ned"),
		"the last line written is missing, which is the only one that matters: %s"
		% found.get("text", ""))
	assert_eq(int(found.get("count", 0)), 2)
	assert_false(bool(found.get("clean", true)),
		"a session that never sealed must read as having stopped dead")


## A sealed session is one the player walked away from, not a freeze.
func test_a_sealed_session_reads_as_a_clean_exit() -> void:
	var disk := FakeStorage.new()

	var first := _store(disk)
	first.open()
	first.append("[00:00.0] RUN    started")
	# What the page's own `pagehide` does on a real exit.
	first.mark_clean()

	var next := _store(disk)
	next.open()

	assert_true(bool(next.recover().get("clean", false)),
		"a sealed session must not be reported as a crash")


## Past what a bank holds, the oldest go and the newest stay.
func test_a_long_session_keeps_its_tail() -> void:
	var disk := FakeStorage.new()
	var capacity := DevStore.CHUNKS * DevStore.CHUNK_LINES

	var first := _store(disk)
	first.open()
	for i in capacity + 100:
		first.append("line %04d" % i)

	var next := _store(disk)
	next.open()
	var found := next.recover()
	var text := String(found.get("text", ""))

	assert_true(bool(found.get("trimmed", false)),
		"a session past the ring must say that it was trimmed")
	assert_true(text.ends_with("line %04d" % (capacity + 99)),
		"the newest line was dropped instead of the oldest")
	assert_false(text.contains("line 0000"),
		"the ring kept the oldest line, so it is not bounded")
	assert_eq(text.split("\n").size(), capacity,
		"the ring holds a different number of lines than it claims")


## Two sessions are kept, not one. The banks alternate for this reason: a launch
## must not be able to destroy the log of the launch that went wrong, and the
## tester's next act after a freeze is to reload.
func test_a_new_run_cannot_destroy_the_session_before_it() -> void:
	var disk := FakeStorage.new()

	var first := _store(disk)
	first.open()
	first.append("the oldest session")

	var second := _store(disk)
	second.open()
	second.append("the session that froze")

	var third := _store(disk)
	third.open()
	var found := third.recover()

	assert_true(String(found.get("text", "")).contains("the session that froze"),
		"the run before this one was overwritten")
	assert_false(String(found.get("text", "")).contains("the oldest session"),
		"two runs back is still being reported as the previous one")


## And the thing that feeds it. `record()` writing to the heap and nowhere else
## is the bug this whole section exists to close, and it would look identical
## from every other angle.
func test_recording_a_line_puts_it_in_the_store() -> void:
	var disk := FakeStorage.new()
	var store := _store(disk)
	store.open()

	# Headless is not a playtest, so `Dev` is deliberately not recording. Both
	# are put back below.
	var was_recording: bool = Dev._recording
	var was_store: DevStore = Dev.store
	var was_lines: int = Dev.lines.size()
	Dev._recording = true
	Dev.store = store

	Dev.record(&"TEST", "a line that has to reach storage")

	Dev._recording = was_recording
	Dev.store = was_store
	Dev.lines.resize(was_lines)

	var next := _store(disk)
	next.open()
	assert_true(String(next.recover().get("text", "")).contains(
		"a line that has to reach storage"),
		"Dev.record kept the line in the heap and nowhere a crash cannot reach")


## A chip nobody moved belongs in its corner, however the screen got bigger.
##
## `_fit_to_screen` clamped, which only ever moves a chip when the screen
## *shrinks*. A browser reports its window as 64x64 for the first frames, so the
## menu was built against a 64-point screen, parked the chip at (34, 45), and the
## real size arriving a frame later left it exactly there — on top of the HUD in
## the top-left corner, all session, in every web build.
func test_a_chip_nobody_moved_is_put_back_in_its_corner() -> void:
	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	# The opening frames of a browser, in order.
	menu._fit_to_screen(Vector2(64, 64))
	menu._fit_to_screen(Vector2(1600, 900))

	var size: Vector2 = menu._chip.get_combined_minimum_size()
	var want := Vector2(1600, 900) - size - DevMenu.CHIP_MARGIN
	assert_almost_eq(menu._chip.position.x, want.x, 0.5,
		"the chip stayed where a 64-point screen put it")
	assert_almost_eq(menu._chip.position.y, want.y, 0.5,
		"the chip stayed where a 64-point screen put it")

	menu.free()


## But a chip the player dragged somewhere stays there, which is the rule the
## clamp was written for: it is clamped onto the new screen, never re-cornered.
func test_a_chip_the_player_moved_is_only_ever_clamped() -> void:
	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)

	menu._chip_moved = true
	menu._chip.position = Vector2(300, 200)
	menu._fit_to_screen(Vector2(1600, 900))
	assert_eq(menu._chip.position, Vector2(300, 200),
		"a chip put somewhere deliberately was moved back to the corner")

	# And a rotation onto a screen it no longer fits still brings it back on.
	menu._fit_to_screen(Vector2(390, 844))
	var corner: Vector2 = menu._chip.position + menu._chip.get_combined_minimum_size()
	assert_true(corner.x <= 390.0, "the chip is off the right edge at %s" % corner)

	menu.free()


## The scrim closes the menu on a press outside it. A wheel notch is not one.
##
## `InputEventMouseButton` covers the wheel, `pressed` is true for it, and the
## menu is taller than it fits — so scrolling down to reach the bottom of it
## closed it instead, and every section below the fold, the playtest log
## included, could not be reached with a wheel at all.
func test_scrolling_over_the_menu_does_not_dismiss_it() -> void:
	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)
	menu._toggle(true)

	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	menu._scrim.gui_input.emit(wheel)
	assert_true(menu._open, "a wheel notch closed the menu")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	menu._scrim.gui_input.emit(click)
	assert_false(menu._open, "a press outside the panel no longer closes it")

	menu.free()


## A recovered log nobody can reach is the same as no recovered log.
##
## The button only exists when there is something to recover, which on the
## desktop is never — the file there outlived whatever happened to the game — so
## this is the only place it is ever built outside a browser.
func test_the_menu_offers_a_recovered_session() -> void:
	var was: Dictionary = Dev.recovered
	Dev.recovered = {
		"text": "[00:00.0] RUN    started",
		"count": 41,
		"started": "2026-09-02 10:00:00",
		"clean": false,
		"trimmed": false,
	}

	var menu := DevMenu.new()
	Engine.get_main_loop().root.add_child(menu)
	# The pages are built when the menu opens, not when it is constructed.
	menu._toggle(true)
	var labels := PackedStringArray()
	_collect_button_labels(menu, labels)

	Dev.recovered = was

	var found := false
	for label in labels:
		if label.begins_with("RECOVER LAST"):
			found = true
	assert_true(found, "no way to reach the previous session's log, got: %s"
		% ", ".join(labels))

	menu.free()


## And that it hands over the log rather than a summary of it. The header is
## worth its lines: a log arriving with no end marker cannot be told from one
## whose owner simply closed the tab, which is the question being asked.
func test_the_recovered_log_says_how_the_session_ended() -> void:
	var was: Dictionary = Dev.recovered
	Dev.recovered = {
		"text": "[00:00.0] RUN    started\n[01:02.3] BUY    Old Anchor Ned",
		"count": 2,
		"started": "2026-09-02 10:00:00",
		"clean": false,
		"trimmed": true,
	}
	var text: String = Dev.recovered_text()
	Dev.recovered = was

	assert_true(text.contains("abruptly"),
		"a session that stopped dead is not reported as one: %s" % text)
	assert_true(text.contains("Old Anchor Ned"),
		"the header replaced the log instead of introducing it")
	assert_true(text.contains("oldest were dropped"),
		"a trimmed log does not say that it is one")


func _collect_button_labels(node: Node, into: PackedStringArray) -> void:
	for child in node.get_children():
		if child is Button:
			into.append((child as Button).text)
		_collect_button_labels(child, into)


## Every visible Control under `node` that would take a click.
func _collect_visible_blockers(node: Node, path: String, into: PackedStringArray) -> void:
	for child in node.get_children():
		if child is Control and not child.visible:
			continue
		var where := "%s/%s" % [path, child.get_class()]
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			into.append(where)
		_collect_visible_blockers(child, where, into)
