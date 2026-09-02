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


## Every visible Control under `node` that would take a click.
func _collect_visible_blockers(node: Node, path: String, into: PackedStringArray) -> void:
	for child in node.get_children():
		if child is Control and not child.visible:
			continue
		var where := "%s/%s" % [path, child.get_class()]
		if child is Control and child.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			into.append(where)
		_collect_visible_blockers(child, where, into)
