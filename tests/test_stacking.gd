extends TestCase

## The four things that hand out a stat every time somebody casts, and the two
## mechanisms that give them a ceiling.
##
## Every failure here is silent. A grant that compounds applies exactly as
## cleanly as one that does not — the board simply wins, and nothing on screen
## says the ability was worth four times at second forty what it was worth at
## second ten. That was true of all four of these for the whole life of the
## project: Empress Nautica with two mana items banked +2,835 armour on every
## ally over one fight, and the only symptom was that two such boards could not
## kill each other before the time limit.
##
## So the assertions here are on the numbers, never on whether a call returned.
## `tools/stacking_balance.gd` is the other half — it measures whether the
## ceilings are in the right *place*, which no assertion can.

const AP := &"ability_power"


func _caster(items: Array = []) -> Sim:
	# Two casters against one body, so the fight lasts long enough to expire a
	# stack and nobody is under any pressure to stop casting.
	return battle(
		[entry(&"barnaby", Vector2i(3, 5), 2, items),
			entry(&"lyra", Vector2i(2, 6), 2)],
		[entry(&"grimscale", Vector2i(3, 5), 2)])


# --- the mechanism -----------------------------------------------------------

## An expiring grant has to actually come back off. Left on, the whole change is
## cosmetic and every measurement above is wrong.
func test_a_temporary_grant_expires() -> void:
	var sim := _caster()
	var u: SimUnit = sim.teams[0][0]
	var before: float = u.ability_power

	sim.add_flat(u, AP, 100.0, 2.0)
	assert_almost_eq(u.ability_power, before + 100.0, 0.01,
		"the grant should land immediately")

	run_for(sim, 1.0)
	assert_almost_eq(u.ability_power, before + 100.0, 0.01,
		"and should still be there inside its duration")

	run_for(sim, 1.5)
	assert_almost_eq(u.ability_power, before, 0.01,
		"and should be gone once it has run out")


## The inspector reads the growth book, so a book that only ever adds reports a
## number the unit does not have. It has to come back down with the stat.
func test_an_expiring_grant_leaves_the_growth_book_honest() -> void:
	var sim := _caster()
	var u: SimUnit = sim.teams[0][0]
	var book: Dictionary = {}

	sim.add_flat(u, AP, 60.0, 2.0, book, &"ap")
	assert_almost_eq(float(book.get(&"ap", 0.0)), 60.0, 0.01,
		"the book should record the grant")

	run_for(sim, 2.5)
	assert_almost_eq(float(book.get(&"ap", 0.0)), 0.0, 0.01,
		"and should give it back when the grant expires")


## The difference between an accumulator and a state. A duration alone caps a
## grant at `amount x casts inside the duration`, and the cast rate is exactly
## what the mana items raise — so a fleet-wide grant refreshes instead.
func test_a_refreshed_grant_does_not_stack_with_itself() -> void:
	var sim := _caster()
	var u: SimUnit = sim.teams[0][0]
	var before: float = u.ability_power

	sim.refresh_flat(u, AP, 50.0, 4.0, &"hymn")
	sim.refresh_flat(u, AP, 50.0, 4.0, &"hymn")
	sim.refresh_flat(u, AP, 50.0, 4.0, &"hymn")
	assert_almost_eq(u.ability_power, before + 50.0, 0.01,
		"three casts of one fleet-wide buff should be worth one, not three")


## Two different sources are two different buffs, though. Keyed wrongly, Nautica
## would overwrite Meredine and a fleet would quietly lose one of them.
func test_two_sources_refresh_independently() -> void:
	var sim := _caster()
	var u: SimUnit = sim.teams[0][0]
	var before: float = u.ability_power

	sim.refresh_flat(u, AP, 40.0, 4.0, &"meredine")
	sim.refresh_flat(u, AP, 55.0, 4.0, &"nautica")
	assert_almost_eq(u.ability_power, before + 95.0, 0.01,
		"two different abilities should both be on the unit")

	sim.refresh_flat(u, AP, 40.0, 4.0, &"meredine")
	assert_almost_eq(u.ability_power, before + 95.0, 0.01,
		"and re-casting one should not disturb the other")


## A refresh puts the clock back as well as the amount, or a fleet-wide buff
## expires on the schedule of the first cast rather than the last.
func test_a_refresh_restarts_the_clock() -> void:
	var sim := _caster()
	var u: SimUnit = sim.teams[0][0]
	var before: float = u.ability_power

	sim.refresh_flat(u, AP, 50.0, 3.0, &"hymn")
	run_for(sim, 2.0)
	sim.refresh_flat(u, AP, 50.0, 3.0, &"hymn")
	run_for(sim, 2.0)
	assert_almost_eq(u.ability_power, before + 50.0, 0.01,
		"four seconds after the first cast, but two after the second")


# --- the four sources --------------------------------------------------------

## Both growing items have to still grow, or the ceiling was applied by removing
## the effect. `test_abilities` covers the two abilities the same way.
func test_the_growing_items_still_grow() -> void:
	for item_id in [&"sirens_locket", &"drowned_choir"]:
		var sim := _caster([item_id])
		var u: SimUnit = sim.teams[0][0]
		var opening: float = u.ability_power
		run_for(sim, 12.0)
		var book := ItemEffect.gathered(u, item_id)
		assert_gt(float(book.get(&"ap", 0.0)), 0.0,
			"%s should have gathered ability power by now" % item_id)
		assert_gt(u.ability_power, opening,
			"%s's growth should be on the unit, not only in the book" % item_id)


## The ceiling itself, on the item that had the worst of it. A long fight and a
## short one should bank about the same; unbounded, the long one banks several
## times more. Asserted as a ratio rather than a figure, so retuning `STACK_AP`
## does not fail the test that guards its shape.
func test_item_growth_plateaus_rather_than_climbing() -> void:
	var early := _gathered_after(&"drowned_choir", 8.0)
	var late := _gathered_after(&"drowned_choir", 30.0)
	assert_gt(early, 0.0, "it should have gathered something in eight seconds")
	assert_lt(late, early * 2.0,
		"the growth should plateau: %.0f at 8s and %.0f at 30s is still climbing"
			% [early, late])


func _gathered_after(item_id: StringName, seconds: float) -> float:
	var sim := _caster([item_id])
	var u: SimUnit = sim.teams[0][0]
	run_for(sim, seconds)
	var book := ItemEffect.gathered(u, item_id)
	return float(book.get(&"ap", 0.0))


## The fleet-wide half, on the ability that most needed it. Nautica grants three
## stats to every ally; refreshed, an ally holds one cast's worth however long
## the fight runs and however often she casts.
func test_nautica_grants_the_fleet_one_cast_worth_however_often_she_casts() -> void:
	var sim := battle(
		[entry(&"nautica", Vector2i(3, 5), 2, [&"drowned_choir", &"krakens_compass"]),
			entry(&"lyra", Vector2i(2, 6), 2)],
		[entry(&"grimscale", Vector2i(3, 5), 3)])
	var ally: SimUnit = sim.teams[0][1]
	var base: float = ally.armor
	var per_cast: float = content().champion(&"nautica").ability_values[&"res"][1]

	run_for(sim, 25.0)
	var gained: float = ally.armor - base
	assert_gt(gained, 0.0, "she should have cast and buffed the fleet by now")
	assert_lt(gained, per_cast * 1.5,
		"the fleet should hold one cast's worth (%.0f), not %.0f stacked up"
			% [per_cast, gained])
