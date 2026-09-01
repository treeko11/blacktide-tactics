extends TestCase

## The numbers behind the DPS meter.
##
## The meter itself is three tabs over one list and is checked by
## `screenshot.gd --modal=dps`. What is worth asserting here is that the counters
## are actually fed — a meter that renders beautifully and reports zero is the
## failure mode, and it is invisible in a screenshot of a fight nobody watched.

const STUN := 60.0


func _frozen_battle() -> Sim:
	var sim := battle(
		[entry(&"barnaby", Vector2i(3, 4))],
		[entry(&"rat", Vector2i(3, 4))])
	# Nobody acts, so only the thing under test moves the counters.
	for u in sim.units:
		u.stun_time = STUN
	return sim


func _player(sim: Sim) -> SimUnit:
	return sim.teams[Sim.Team.PLAYER][0]


func _foe(sim: Sim) -> SimUnit:
	return sim.teams[Sim.Team.ENEMY][0]


# --- the counters ------------------------------------------------------------

func test_damage_credits_both_sides_the_same_figure() -> void:
	var sim := _frozen_battle()
	var src := _player(sim)
	var target := _foe(sim)
	target.armor = 100.0

	var dealt := sim.damage(src, target, 200.0, &"physical")

	assert_almost_eq(src.damage_dealt, dealt, 0.01,
		"the dealer should be credited what actually landed")
	assert_almost_eq(target.damage_taken, dealt, 0.01,
		"one side's dealt and the other's taken must agree")


## Damage a shield soaks still happened, and both tabs have to say so — a tank
## whose shields ate a broadside did take it.
func test_damage_taken_counts_what_a_shield_absorbed() -> void:
	var sim := _frozen_battle()
	var src := _player(sim)
	var target := _foe(sim)
	target.armor = 0.0
	sim.add_shield(target, 500.0, 10.0)
	var full_health := target.hp

	sim.damage(src, target, 200.0, &"true")

	assert_almost_eq(target.hp, full_health, 0.01, "the shield should have held")
	assert_almost_eq(target.damage_taken, 200.0, 0.01,
		"absorbed damage is still damage taken")
	assert_almost_eq(src.damage_dealt, 200.0, 0.01)


func test_unmitigated_damage_accumulates_over_several_hits() -> void:
	var sim := _frozen_battle()
	var src := _player(sim)
	var target := _foe(sim)
	sim.damage(src, target, 50.0, &"true")
	sim.damage(src, target, 30.0, &"true")
	assert_almost_eq(src.damage_dealt, 80.0, 0.01, "hits should add up")
	assert_almost_eq(target.damage_taken, 80.0, 0.01)


## The devour finisher deletes a target without going through damage(). Left
## uncounted, the one ability that removes a full-health tank read as having done
## nothing at all.
func test_execute_is_credited_the_health_it_removed() -> void:
	var sim := _frozen_battle()
	var src := _player(sim)
	var target := _foe(sim)
	sim.add_shield(target, 200.0, 10.0)
	var effective := target.hp + target.shield

	sim.execute(src, target)

	assert_false(target.alive, "execute should have killed it")
	assert_almost_eq(src.damage_dealt, effective, 0.01,
		"the executioner should be credited health plus shield")
	assert_almost_eq(target.damage_taken, effective, 0.01)


func test_healing_credits_the_healer_only_what_landed() -> void:
	var sim := _frozen_battle()
	var healer := _player(sim)
	var target := _foe(sim)
	sim.damage(null, target, 100.0, &"true")

	var healed := sim.heal(healer, target, 400.0)

	assert_almost_eq(healed, 100.0, 0.01, "healing should stop at full health")
	assert_almost_eq(healer.healing_done, 100.0, 0.01,
		"overheal is not healing done")


## Regeneration heals nobody in the meter unless the unit is named as its own
## source. An item that quietly restores health is one of the things the healing
## tab exists to make visible.
func test_regeneration_credits_the_unit_healing_itself() -> void:
	var sim := _frozen_battle()
	var u := _player(sim)
	sim.damage(null, u, 200.0, &"true")
	u.item_regen = 0.05

	sim.step()

	assert_gt(u.healing_done, 0.0, "item regen should count as healing done")


# --- the readout -------------------------------------------------------------

func test_stats_reports_a_row_per_combatant_on_both_teams() -> void:
	var sim := battle(
		[entry(&"barnaby", Vector2i(3, 4)), entry(&"lyra", Vector2i(2, 5))],
		[entry(&"rat", Vector2i(3, 4))])

	var rows := sim.stats()

	assert_eq(rows.size(), 3, "every unit in the fight should get a row")
	var mine := 0
	var theirs := 0
	for row in rows:
		if int(row["team"]) == Sim.Team.PLAYER:
			mine += 1
		else:
			theirs += 1
	assert_eq(mine, 2, "both of the player's pirates should be listed")
	assert_eq(theirs, 1)


func test_stats_carries_the_numbers_the_tabs_show() -> void:
	var sim := _frozen_battle()
	var src := _player(sim)
	var target := _foe(sim)
	sim.damage(src, target, 100.0, &"true")
	sim.heal(src, target, 40.0)

	var rows := sim.stats()
	var dealer := _row_for(rows, src.uid)
	var victim := _row_for(rows, target.uid)

	assert_almost_eq(dealer["dealt"], 100.0, 0.01)
	assert_almost_eq(dealer["healed"], 40.0, 0.01)
	assert_almost_eq(victim["taken"], 100.0, 0.01)
	assert_eq(dealer["name"], src.display_name(), "a row should name its pirate")
	assert_true(victim["alive"], "a survivor should not be marked dead")


## The meter outlives the fight: the round advances, the sim is disposed, and the
## player is still looking at what just happened. A snapshot holding SimUnits
## would read back blanks the moment `dispose()` nulled their defs.
func test_stats_survive_the_disposal_of_the_fight() -> void:
	var sim := _frozen_battle()
	sim.damage(_player(sim), _foe(sim), 100.0, &"true")
	var rows := sim.stats()
	var before: String = rows[0]["name"]

	sim.dispose()

	assert_eq(rows[0]["name"], before, "a snapshot must not go blank on dispose")
	assert_ne(rows[0]["name"], "", "the name should still be readable")


func _row_for(rows: Array, uid: int) -> Dictionary:
	for row in rows:
		if int(row["uid"]) == uid:
			return row
	fail("no stats row for uid %d" % uid)
	return {}
