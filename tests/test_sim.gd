extends TestCase

## The battle sim's own rules: mitigation, shields, buff bookkeeping, and the
## determinism the headless bot fights depend on.

const STUN := 60.0


func _frozen_battle() -> Sim:
	var sim := battle(
		[entry(&"barnaby", Vector2i(3, 4))],
		[entry(&"rat", Vector2i(3, 4))])
	# Nobody acts, so only the thing under test moves.
	for u in sim.units:
		u.stun_time = STUN
	return sim


func _player(sim: Sim) -> SimUnit:
	return sim.teams[Sim.Team.PLAYER][0]


func _foe(sim: Sim) -> SimUnit:
	return sim.teams[Sim.Team.ENEMY][0]


# --- mitigation --------------------------------------------------------------

## Damage is divided by (100 + resistance) / 100 — 100 armour halves it.
func test_armour_halves_damage_at_one_hundred() -> void:
	var sim := _frozen_battle()
	var target := _foe(sim)
	target.armor = 100.0
	var dealt := sim.damage(null, target, 200.0, &"physical")
	assert_almost_eq(dealt, 100.0, 0.01, "100 armour should halve 200 damage")


func test_true_damage_ignores_resistances() -> void:
	var sim := _frozen_battle()
	var target := _foe(sim)
	target.armor = 500.0
	target.magic_resist = 500.0
	var dealt := sim.damage(null, target, 200.0, &"true")
	assert_almost_eq(dealt, 200.0, 0.01, "true damage should not be mitigated")


func test_armour_shred_increases_damage_taken() -> void:
	var sim := _frozen_battle()
	var target := _foe(sim)
	target.armor = 100.0
	sim.apply_shred(target, 0.5, 5.0)
	var dealt := sim.damage(null, target, 200.0, &"physical")
	# 50% shred leaves 50 armour, so 200 * 100/150.
	assert_almost_eq(dealt, 133.333, 0.01, "shred should reduce effective armour")


# --- shields -----------------------------------------------------------------

func test_shields_absorb_before_health() -> void:
	var sim := _frozen_battle()
	var target := _foe(sim)
	target.armor = 0.0
	var full_health := target.hp
	sim.add_shield(target, 100.0, 10.0)

	sim.damage(null, target, 60.0, &"true")
	assert_almost_eq(target.hp, full_health, 0.01, "shield should have taken it all")
	assert_almost_eq(target.shield, 40.0, 0.01)

	sim.damage(null, target, 60.0, &"true")
	assert_almost_eq(target.shield, 0.0, 0.01, "shield should be spent")
	assert_almost_eq(target.hp, full_health - 20.0, 0.01, "overflow should hit health")


func test_expired_shields_stop_absorbing() -> void:
	var sim := _frozen_battle()
	var target := _foe(sim)
	sim.add_shield(target, 500.0, 1.0)
	assert_almost_eq(target.shield, 500.0, 0.01)
	run_for(sim, 1.5)
	assert_almost_eq(target.shield, 0.0, 0.01, "the shield should have timed out")


# --- buffs -------------------------------------------------------------------

## The invariant the sim's add_buff docstring promises: a multiplier that expires
## restores the original value *exactly*. Clamping on the way in would lose the
## difference and leave the unit permanently slower than it started.
func test_expiring_buff_restores_the_original_value_exactly() -> void:
	var sim := _frozen_battle()
	var u := _player(sim)
	var before := u.attack_speed

	sim.add_buff(u, &"attack_speed", 1.4, 1.0)
	assert_almost_eq(u.attack_speed, before * 1.4, 0.0001, "buff should apply")

	run_for(sim, 1.5)
	assert_almost_eq(u.attack_speed, before, 0.0001, "buff should come back off cleanly")


func test_expiring_flat_bonus_restores_the_original_value() -> void:
	var sim := _frozen_battle()
	var u := _player(sim)
	var before := u.armor

	sim.add_flat(u, &"armor", 40.0, 1.0)
	assert_almost_eq(u.armor, before + 40.0, 0.0001)

	run_for(sim, 1.5)
	assert_almost_eq(u.armor, before, 0.0001)


# --- lifecycle ---------------------------------------------------------------

func test_killing_the_last_enemy_ends_the_fight_as_a_win() -> void:
	var sim := battle(
		[entry(&"barnaby", Vector2i(3, 4))],
		[entry(&"rat", Vector2i(3, 4))])
	sim.run_to_end()
	assert_true(sim.done)
	assert_eq(sim.winner, Sim.Result.PLAYER_WIN,
		"a champion should beat a single deck rat")


func test_a_fight_always_terminates() -> void:
	# Two immovable walls that cannot kill each other still have to stop.
	var sim := battle(
		[entry(&"ned", Vector2i(3, 4), 3)],
		[entry(&"golem", Vector2i(3, 4))])
	sim.run_to_end()
	assert_true(sim.done, "run_to_end must always terminate")
	assert_lt(sim.time, Sim.TIME_LIMIT + 1.0, "and within the time limit")


func test_an_empty_board_loses() -> void:
	var sim := battle([], [entry(&"rat", Vector2i(3, 4))])
	sim.run_to_end()
	assert_eq(sim.winner, Sim.Result.ENEMY_WIN, "fielding nothing should lose")


# --- determinism -------------------------------------------------------------

## The six bot-vs-bot fights every round are resolved headless and never seen. If
## the same seed did not produce the same fight, a reported result could not be
## reproduced to debug it.
func test_the_same_seed_produces_the_same_fight() -> void:
	var board_a: Array = [
		entry(&"isla", Vector2i(3, 4), 2), entry(&"saltyjo", Vector2i(2, 6)),
		entry(&"nerida", Vector2i(4, 6)),
	]
	var board_b: Array = [
		entry(&"hookjaw", Vector2i(3, 4), 2), entry(&"doss", Vector2i(2, 6)),
		entry(&"coral", Vector2i(4, 6)),
	]

	var first := battle(board_a, board_b, 9871)
	first.run_to_end()
	var second := battle(board_a, board_b, 9871)
	second.run_to_end()

	assert_eq(second.winner, first.winner, "same seed, same winner")
	assert_almost_eq(second.time, first.time, 0.0001, "same seed, same duration")
	assert_almost_eq(second.team_score(0), first.team_score(0), 0.0001,
		"same seed, same survivors")


# --- movement ----------------------------------------------------------------

func test_a_melee_unit_walks_into_range() -> void:
	var sim := battle(
		[entry(&"barnaby", Vector2i(3, 7))],
		[entry(&"rat", Vector2i(3, 7))])
	var u := _player(sim)
	var start := u.cell
	run_for(sim, 5.0)
	assert_ne(u.cell, start, "a melee unit should close the gap")


func test_a_ranged_unit_does_not_need_to_close() -> void:
	var sim := battle(
		[entry(&"lyra", Vector2i(3, 4))],
		[entry(&"rat", Vector2i(3, 4))])
	var u := _player(sim)
	var start := u.cell
	run_for(sim, 1.0)
	assert_eq(u.cell, start, "range 5 already covers an adjacent rank")


func test_two_units_never_share_a_cell() -> void:
	var board_a: Array = []
	for i in 5:
		board_a.append(entry(&"pip", Vector2i(i + 1, 6)))
	var board_b: Array = []
	for i in 5:
		board_b.append(entry(&"rat", Vector2i(i + 1, 4)))

	var sim := battle(board_a, board_b)
	for i in 200:
		sim.step()
		var seen: Dictionary = {}
		for u in sim.units:
			if not u.alive:
				continue
			var key := Hex.key(u.cell)
			if seen.has(key):
				fail("two units occupied %s on tick %d" % [u.cell, i])
				return
			seen[key] = true
	assert_true(true, "occupancy stayed exclusive for 200 ticks")
