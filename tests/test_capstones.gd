extends TestCase

## Greater items — the third rung, and the slot rule that pays for it.
##
## Two things here fail silently and neither shows up in a played round. The
## **tier graph** is derived from the recipes rather than declared, so a capstone
## whose recipe named a component would load happily, sort itself into tier 2 and
## become a sixteenth forged item: the almanac would list it in the wrong group
## and the forge chart would look for it in a grid it is not in, with nothing
## thrown anywhere. And the **slot rule** is the whole cost of a greater item, so
## a path that quietly lets a pirate hold two of them and a third item besides
## does not look like a bug — it looks like a strong board.
##
## Every assertion is therefore on a loadout or on a tier, never on whether a
## call returned without complaining.

func before_each() -> void:
	state().start_game()
	state().player.gold = 200
	state().player.items.clear()


func _give(champion_id: StringName, star: int = 1) -> RosterUnit:
	var s := state()
	var unit := RosterUnit.new(content().champion(champion_id), star)
	var slot: int = s.first_free_bench_slot()
	s.bench[slot] = unit
	return unit


## A capstone id, and the two finished items it is forged from.
func _any_capstone() -> ItemDef:
	var all: Array = content().capstones()
	assert_gt(all.size(), 0, "there should be capstones to test")
	return all[0]


# --- the tier graph ----------------------------------------------------------

func test_the_three_rungs_are_derived_from_the_recipes() -> void:
	for item in content().components():
		assert_eq(content().item_tier(item.id), 1,
			"%s is a component and should be tier 1" % item.id)
	for item in content().forged_items():
		assert_eq(content().item_tier(item.id), 2,
			"%s is forged from components and should be tier 2" % item.id)
	for item in content().capstones():
		assert_eq(content().item_tier(item.id), 3,
			"%s is forged from finished items and should be tier 3" % item.id)


## The check the tier graph exists to make possible. A capstone naming a
## component would be a tier-2 item wearing a capstone's name, and every list in
## the game would put it in the wrong place without throwing.
func test_every_capstone_is_forged_from_two_finished_items() -> void:
	for item in content().capstones():
		assert_eq(item.recipe.size(), 2,
			"%s should be forged from exactly two items" % item.id)
		for part in item.recipe:
			assert_eq(content().item_tier(part), 2,
				"%s is forged from %s, which is not a finished item" % [item.id, part])


## The rule one rung up from "a component is never a dead end". A finished item
## with no capstone above it is a build that stops, and the player has no way to
## tell which ones those are short of reading the chart.
func test_every_finished_item_leads_to_a_capstone() -> void:
	for item in content().forged_items():
		var pairings: Array = content().forges_using(item.id)
		assert_gt(pairings.size(), 0,
			"%s is a finished item that forges into nothing" % item.id)


func test_a_capstone_forges_into_nothing() -> void:
	for item in content().capstones():
		assert_eq(content().forges_using(item.id).size(), 0,
			"%s is the top of the tree and should pair with nothing" % item.id)


func test_no_two_recipes_make_the_same_pair() -> void:
	var seen: Dictionary = {}
	for item in content().forged_items() + content().capstones():
		var key: StringName = item.key()
		assert_false(seen.has(key),
			"%s and %s are forged from the same pair" % [item.id, seen.get(key, &"")])
		seen[key] = item.id


# --- forging one -------------------------------------------------------------

func test_two_finished_items_on_one_pirate_forge_a_capstone() -> void:
	var s := state()
	var capstone := _any_capstone()
	var unit := _give(&"barnaby")
	unit.items.append(capstone.recipe[0])
	s.player.items.append(capstone.recipe[1])

	assert_true(s.equip_item(capstone.recipe[1], unit), "the drop should land")
	assert_eq(unit.items.size(), 1, "the pair should have become one item")
	assert_eq(unit.items[0], capstone.id)
	assert_true(s.player.items.is_empty(), "and the hold should be spent")


## The preview is what the drag promises. It and the drop are the same call now,
## so this is really asking that they cannot come apart.
func test_the_preview_names_the_capstone_before_the_drop() -> void:
	var s := state()
	var capstone := _any_capstone()
	var unit := _give(&"barnaby")
	unit.items.append(capstone.recipe[0])
	s.player.items.append(capstone.recipe[1])

	var preview: Dictionary = s.preview_equip(capstone.recipe[1], unit)
	assert_true(preview["allowed"])
	assert_eq(preview["forges"], capstone.id)

	s.equip_item(capstone.recipe[1], unit)
	assert_eq(unit.items[0], preview["forges"],
		"the drop should make what the preview promised")


## A capstone dropped on a pirate is only ever an item taking a slot: nothing
## pairs with it, so it must not silently consume whatever it landed on.
func test_a_capstone_dropped_on_a_pirate_only_takes_a_slot() -> void:
	var s := state()
	var capstone := _any_capstone()
	var unit := _give(&"barnaby")
	unit.items.append(&"blade")
	s.player.items.append(capstone.id)

	assert_true(s.equip_item(capstone.id, unit))
	assert_eq(unit.items.size(), 2, "it should sit beside the component, not eat it")
	assert_true(unit.items.has(&"blade"), "the component should still be there")


# --- the slot rule -----------------------------------------------------------

func test_two_capstones_leave_a_pirate_with_no_third_slot() -> void:
	var s := state()
	var all: Array = content().capstones()
	var unit := _give(&"barnaby")
	unit.items.assign([all[0].id, all[1].id])
	s.player.items.append(&"blade")

	var preview: Dictionary = s.preview_equip(&"blade", unit)
	assert_false(preview["allowed"],
		"two greater items should spend the third slot")
	assert_false(s.equip_item(&"blade", unit))
	assert_eq(unit.items.size(), 2, "and nothing should have been taken")
	assert_eq(s.player.items.size(), 1, "the item should still be in the hold")


func test_one_capstone_still_leaves_two_ordinary_slots() -> void:
	var s := state()
	var unit := _give(&"barnaby")
	unit.items.assign([_any_capstone().id])
	s.player.items.assign([&"bloodletter", &"hull_of_the_deep"])

	assert_true(s.equip_item(&"bloodletter", unit), "a second item should fit")
	assert_true(s.equip_item(&"hull_of_the_deep", unit), "and so should a third")
	assert_eq(unit.items.size(), 3,
		"one greater item costs nothing; only the second one does")


## The case the plain count misses. The pirate is not gaining an item — the forge
## turns two into one — so a size check alone waves it through, and the pirate
## ends up carrying two greater items *and* a third item beside them.
func test_a_second_capstone_is_refused_when_a_third_item_would_be_stranded() -> void:
	var s := state()
	var capstone := _any_capstone()
	var other: ItemDef = content().capstones()[1]
	var unit := _give(&"barnaby")
	# One greater item already, plus one half of a second, plus a spare.
	unit.items.assign([capstone.id, other.recipe[0], &"hull_of_the_deep"])
	s.player.items.append(other.recipe[1])

	var preview: Dictionary = s.preview_equip(other.recipe[1], unit)
	assert_false(preview["allowed"],
		"forging a second greater item here would leave three items on the pirate")
	assert_false(s.equip_item(other.recipe[1], unit))
	assert_eq(unit.items.size(), 3, "the loadout should be untouched")
	assert_true(unit.items.has(other.recipe[0]),
		"and the half that would have been spent should still be there")


func test_a_second_capstone_is_allowed_when_it_takes_the_last_slot() -> void:
	var s := state()
	var capstone := _any_capstone()
	var other: ItemDef = content().capstones()[1]
	var unit := _give(&"barnaby")
	unit.items.assign([capstone.id, other.recipe[0]])
	s.player.items.append(other.recipe[1])

	assert_true(s.equip_item(other.recipe[1], unit), "this one has room")
	assert_eq(unit.items.size(), 2)
	assert_eq(content().capstone_count(unit.items), 2)


func test_capacity_drops_to_two_only_at_the_second_capstone() -> void:
	var none: Array[StringName] = []
	var one: Array[StringName] = [_any_capstone().id]
	var two: Array[StringName] = [content().capstones()[0].id, content().capstones()[1].id]
	assert_eq(content().capacity(none), 3)
	assert_eq(content().capacity(one), 3)
	assert_eq(content().capacity(two), 2)


# --- the doors that do not go through equip_item ------------------------------

## A star-up carries the items of all three copies, and used to keep whichever
## three came first. With greater items in the mix that could hand the upgrade a
## loadout the drop rules forbid — arriving by merge, where nothing was looking.
func test_a_star_up_never_builds_a_loadout_the_rules_forbid() -> void:
	var s := state()
	var all: Array = content().capstones()
	var a := _give(&"barnaby")
	var b := _give(&"barnaby")
	var c := _give(&"barnaby")
	a.items.assign([all[0].id, &"bloodletter"])
	b.items.assign([all[1].id])
	c.items.assign([&"hull_of_the_deep"])

	s._check_upgrades()

	var owned: Array = s.owned_units()
	assert_eq(owned.size(), 1, "the three copies should have merged")
	var upgraded: RosterUnit = owned[0]
	var room: int = content().capacity(upgraded.items)
	assert_true(upgraded.items.size() <= room,
		"the upgrade is carrying more than its capstones leave room for")
	assert_true(content().capstone_count(upgraded.items) <= RosterUnit.MAX_CAPSTONES,
		"the upgrade is carrying too many greater items")
	assert_eq(content().capstone_count(upgraded.items), 2,
		"and the greater items are what it should have kept")


## Bots equip through the same plan the player's drops go through, so the rule
## cannot hold on one side of the board and not the other.
func test_a_bot_never_builds_a_loadout_the_rules_forbid() -> void:
	var s := state()
	var bot: Bot = s.bots[0]
	bot.level = 2
	bot.units.append(RosterUnit.new(content().champion(&"barnaby"), 1))
	var loot: Array[StringName] = []
	for item in content().capstones():
		loot.append(item.id)
	loot.append(&"bloodletter")
	bot.items.assign(loot)

	bot.equip_items(s)

	for u in bot.units:
		var room: int = content().capacity(u.items)
		assert_true(u.items.size() <= room,
			"a bot unit is carrying more than its capstones leave room for")
		assert_true(content().capstone_count(u.items) <= RosterUnit.MAX_CAPSTONES,
			"a bot unit is carrying too many greater items")


## Bots draw finished items from the armoury and components from monster rounds.
## Handing them a capstone whole would undercut the forge for the half of the
## board the player is fighting.
func test_the_armoury_never_hands_out_a_capstone() -> void:
	for item in content().forged_items():
		assert_true(content().item_tier(item.id) < 3,
			"%s is offered by the armoury but is a greater item" % item.id)


# --- the effects actually do something ----------------------------------------

## The DPS-meter problem: an item that applies cleanly and changes no number is
## indistinguishable from one that works. Every capstone is cast onto a unit and
## has to move something.
func test_every_capstone_changes_the_unit_it_is_put_on() -> void:
	for item in content().capstones():
		var plain := battle([entry(&"barnaby", Vector2i(0, 5))],
			[entry(&"barnaby", Vector2i(0, 1))])
		var kitted := battle([entry(&"barnaby", Vector2i(0, 5), 1, [item.id])],
			[entry(&"barnaby", Vector2i(0, 1))])
		var before: SimUnit = plain.teams[0][0]
		var after: SimUnit = kitted.teams[0][0]
		var moved := (
			after.ad != before.ad
			or after.ability_power != before.ability_power
			or after.max_hp != before.max_hp
			or after.attack_speed != before.attack_speed
			or after.armor != before.armor
			or after.magic_resist != before.magic_resist
			or after.shield != before.shield
			or after.mana != before.mana
			or after.item_regen != before.item_regen
			or after.omnivamp != before.omnivamp
		)
		assert_true(moved, "%s changes nothing about the unit carrying it" % item.id)


## A greater item is meant to be worth about two finished ones. It is not worth
## pinning every number, but a capstone weaker than a parent it is made of is a
## trap the player pays a slot for, and that is worth failing over.
func test_a_capstone_is_never_weaker_than_the_items_it_is_made_of() -> void:
	for item in content().capstones():
		var mine := _stat_total(item.id)
		for part in item.recipe:
			assert_true(mine >= _stat_total(part),
				"%s is weaker than %s, which is half of it" % [item.id, part])


## A rough weight for an item's opening stat line, in arbitrary units. Only ever
## compared against another item's, never read as a balance figure.
func _stat_total(item_id: StringName) -> float:
	var plain := battle([entry(&"barnaby", Vector2i(0, 5))],
		[entry(&"barnaby", Vector2i(0, 1))])
	var kitted := battle([entry(&"barnaby", Vector2i(0, 5), 1, [item_id])],
		[entry(&"barnaby", Vector2i(0, 1))])
	var a: SimUnit = plain.teams[0][0]
	var b: SimUnit = kitted.teams[0][0]
	return (
		(b.ad - a.ad) * 2.0
		+ (b.ability_power - a.ability_power) * 1.0
		+ (b.max_hp - a.max_hp) * 0.1
		+ (b.attack_speed - a.attack_speed) * 100.0
		+ (b.armor - a.armor) * 1.5
		+ (b.magic_resist - a.magic_resist) * 1.5
		+ (b.shield - a.shield) * 0.1
		+ (b.omnivamp - a.omnivamp) * 100.0
		+ (b.item_regen - a.item_regen) * 1000.0
	)
