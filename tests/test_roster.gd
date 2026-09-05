extends TestCase

## Buying, merging, positioning, and items — the things the player does with a
## mouse between fights.

func before_each() -> void:
	state().start_game()
	state().player.gold = 200


func _give(champion_id: StringName, star: int = 1) -> RosterUnit:
	var s := state()
	var unit := RosterUnit.new(content().champion(champion_id), star)
	var slot: int = s.first_free_bench_slot()
	s.bench[slot] = unit
	return unit


# --- merging -----------------------------------------------------------------

func test_three_copies_merge_into_a_two_star() -> void:
	var s := state()
	_give(&"barnaby")
	_give(&"barnaby")
	_give(&"barnaby")
	s._check_upgrades()

	var owned: Array = s.owned_units()
	assert_eq(owned.size(), 1, "three copies should have become one unit")
	assert_eq(owned[0].star, 2)


func test_nine_copies_merge_all_the_way_to_three_star() -> void:
	var s := state()
	for i in 9:
		_give(&"barnaby")
	s._check_upgrades()

	var owned: Array = s.owned_units()
	assert_eq(owned.size(), 1)
	assert_eq(owned[0].star, 3, "nine copies is a three-star")


## An upgrade must not silently bench a unit you had positioned. Losing your
## carry's seat on a star-up, mid-timer, is a lost round.
func test_merging_keeps_the_board_seat() -> void:
	var s := state()
	var fielded := _give(&"barnaby")
	s.move_to_board(fielded, Vector2i(3, 5))
	_give(&"barnaby")
	_give(&"barnaby")
	s._check_upgrades()

	assert_eq(s.board.size(), 1, "the upgrade should still be fielded")
	assert_eq(s.board[0].cell, Vector2i(3, 5), "and in the same seat")
	assert_eq(s.board[0].star, 2)


## One item per copy, and deliberately only one that could pair with anything:
## every component forges with every other, so two of them on the three copies
## would test the merge's forging rather than that it carries anything at all.
## That case is `test_capstones.gd`.
func test_merging_carries_items_across() -> void:
	var s := state()
	var a := _give(&"barnaby")
	a.items.append(&"blade")
	var b := _give(&"barnaby")
	b.items.append(&"bloodletter")
	_give(&"barnaby")
	s._check_upgrades()

	var upgraded: RosterUnit = s.owned_units()[0]
	assert_eq(upgraded.star, 2)
	assert_true(upgraded.items.has(&"blade"), "items should survive the merge")
	assert_true(upgraded.items.has(&"bloodletter"))


## Three items is the hard limit; a fourth has to go back to the hold rather
## than vanish.
##
## Four *finished* items that pair with nothing between them, because a merge
## forges now: any two components combine, so five of those come out the other
## side as three items and nothing overflows at all. The pairings are asserted
## rather than assumed, so adding a recipe between any two of these fails here
## saying so instead of failing the overflow count and looking like a merge bug.
func test_merge_overflow_items_return_to_the_hold() -> void:
	var s := state()
	s.player.items.clear()
	var loose: Array[StringName] = [&"bloodletter", &"hull_of_the_deep",
		&"coral_aegis", &"krakens_compass"]
	for i in loose.size():
		for j in range(i + 1, loose.size()):
			assert_eq(content().forge(loose[i], loose[j]), &"",
				"%s and %s now forge, so this fixture no longer overflows"
					% [loose[i], loose[j]])

	var a := _give(&"barnaby")
	a.items.assign(loose.slice(0, 3))
	var b := _give(&"barnaby")
	b.items.assign(loose.slice(3))
	_give(&"barnaby")
	s._check_upgrades()

	var upgraded: RosterUnit = s.owned_units()[0]
	assert_eq(upgraded.items.size(), RosterUnit.MAX_ITEMS)
	assert_eq(s.player.items.size(), 1, "the one that did not fit should be held")


# --- positioning -------------------------------------------------------------

func test_the_board_is_capped_by_level() -> void:
	var s := state()
	s.player.level = 1
	var first := _give(&"barnaby")
	var second := _give(&"pip")

	assert_true(s.move_to_board(first, Vector2i(3, 5)))
	var notices := probe(events().notice, 2)
	assert_false(s.move_to_board(second, Vector2i(2, 5)),
		"a level 1 captain fields one pirate")
	assert_eq(notices.size(), 1, "and should be told why")


func test_a_unit_cannot_be_placed_on_the_enemy_half() -> void:
	var s := state()
	s.player.level = 5
	var unit := _give(&"barnaby")
	assert_false(s.move_to_board(unit, Vector2i(3, 2)), "row 2 is the enemy half")


func test_dropping_onto_an_occupied_cell_swaps() -> void:
	var s := state()
	s.player.level = 5
	var a := _give(&"barnaby")
	var b := _give(&"pip")
	s.move_to_board(a, Vector2i(3, 5))
	s.move_to_board(b, Vector2i(2, 5))

	s.move_to_board(a, Vector2i(2, 5))
	assert_eq(a.cell, Vector2i(2, 5))
	assert_eq(b.cell, Vector2i(3, 5), "the occupant should have taken the vacated seat")


func test_benching_a_fielded_unit_frees_its_cell() -> void:
	var s := state()
	s.player.level = 5
	var unit := _give(&"barnaby")
	s.move_to_board(unit, Vector2i(3, 5))
	assert_eq(s.board.size(), 1)

	s.move_to_bench(unit, 0)
	assert_eq(s.board.size(), 0)
	assert_null(s.unit_at(Vector2i(3, 5)))
	assert_false(unit.on_board())


# --- items -------------------------------------------------------------------

func test_two_components_forge_on_a_unit() -> void:
	var s := state()
	var unit := _give(&"barnaby")
	s.player.items.clear()
	s.player.items.append(&"blade")
	s.player.items.append(&"plate")

	s.equip_item(&"blade", unit)
	s.equip_item(&"plate", unit)

	assert_eq(unit.items.size(), 1, "the pair should have forged into one item")
	assert_eq(unit.items[0], &"ironclad", "blade + plate is the Ironclad Cutlass")
	assert_true(s.player.items.is_empty(), "both components should be spent")


## The forge preview is what the UI shows *before* the drop. Equipping cannot be
## undone, so guessing is expensive.
func test_the_forge_preview_names_the_result_before_the_drop() -> void:
	var s := state()
	var unit := _give(&"barnaby")
	unit.items.append(&"blade")
	s.player.items.append(&"plate")

	var preview: Dictionary = s.preview_equip(&"plate", unit)
	assert_true(preview["allowed"])
	assert_eq(preview["forges"], &"ironclad")


func test_a_unit_carrying_three_items_is_refused() -> void:
	var s := state()
	var unit := _give(&"barnaby")
	unit.items.assign([&"bloodletter", &"abyssal_prism", &"hull_of_the_deep"])
	s.player.items.clear()
	s.player.items.append(&"bloodletter")

	var preview: Dictionary = s.preview_equip(&"bloodletter", unit)
	assert_false(preview["allowed"], "a fourth item should be refused")
	assert_false(s.equip_item(&"bloodletter", unit))


func test_selling_a_unit_returns_its_items() -> void:
	var s := state()
	s.player.items.clear()
	var unit := _give(&"barnaby")
	unit.items.assign([&"blade", &"lens"])
	s.sell(unit)
	assert_eq(s.player.items.size(), 2, "items should come back to the hold")


func test_every_pair_of_components_forges_something() -> void:
	var components: Array = content().components()
	for a in components:
		for b in components:
			var forged: StringName = content().forge(a.id, b.id)
			assert_ne(forged, &"",
				"%s + %s forges nothing" % [a.id, b.id])


# --- the AI's items ----------------------------------------------------------

## The playtest note was "I don't think I saw the AI use items". They now draw
## the same loot the player does and equip it by the same rules.
func test_bots_equip_the_loot_they_are_given() -> void:
	var s := state()
	var bot: Bot = s.bots[0]
	bot.level = 5
	for i in 5:
		bot.units.append(RosterUnit.new(content().champion(&"barnaby"), 1))
	bot.items.assign([&"blade", &"plate"])

	bot.equip_items(s)

	var carried := 0
	for u in bot.units:
		carried += u.items.size()
	assert_gt(carried, 0.0, "a bot holding items should put them on its board")
	assert_true(bot.items.is_empty(), "and should not be hoarding them")


func test_bots_forge_components_rather_than_stacking_them() -> void:
	var s := state()
	var bot: Bot = s.bots[0]
	bot.level = 3
	bot.units.append(RosterUnit.new(content().champion(&"barnaby"), 1))
	bot.items.assign([&"blade", &"plate"])

	bot.equip_items(s)

	var unit: RosterUnit = bot.units[0]
	assert_eq(unit.items.size(), 1, "the two components should have combined")
	assert_false(content().is_component(unit.items[0]),
		"and the result should be a forged item")
