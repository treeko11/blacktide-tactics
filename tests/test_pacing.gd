extends TestCase

## Round pacing: the overtime ramp, and the star curve that decides whether a
## fight gets harder to finish as a run goes on.
##
## Both fail silently. A ramp that is applied cleanly and changes no number is
## indistinguishable from one that works — the same trap the DPS meter and the
## sea are held to — so every assertion here is on a number, and the two that
## matter most are on the shape of a whole fight rather than on one call.

const STUN := 120.0


func _frozen_battle() -> Sim:
	var sim := battle(
		[entry(&"barnaby", Vector2i(3, 4))],
		[entry(&"rat", Vector2i(3, 4))])
	for u in sim.units:
		u.stun_time = STUN
	return sim


func _foe(sim: Sim) -> SimUnit:
	return sim.teams[Sim.Team.ENEMY][0]


# --- the ramp itself ---------------------------------------------------------

func test_overtime_is_flat_until_it_starts() -> void:
	var sim := _frozen_battle()
	assert_eq(sim.overtime(), 0.0, "a fight opens outside overtime")
	run_for(sim, Sim.OVERTIME_START - 1.0)
	assert_eq(sim.overtime(), 0.0, "overtime should not begin early")


func test_overtime_ramps_to_full() -> void:
	var sim := _frozen_battle()
	run_for(sim, Sim.OVERTIME_START + 1.0)
	assert_gt(sim.overtime(), 0.0, "overtime should have begun")
	assert_lt(sim.overtime(), 1.0, "and should not arrive at full strength")

	run_for(sim, Sim.OVERTIME_FULL - Sim.OVERTIME_START)
	assert_almost_eq(sim.overtime(), 1.0, 0.001, "overtime should reach full ramp")


## The ramp is a multiplier on damage, and it has to be a real one.
func test_overtime_amplifies_damage() -> void:
	var early := _frozen_battle()
	var before := early.damage(null, _foe(early), 100.0, &"true")

	var late := _frozen_battle()
	run_for(late, Sim.OVERTIME_FULL + 1.0)
	var after := late.damage(null, _foe(late), 100.0, &"true")

	assert_almost_eq(after, before * (1.0 + Sim.OVERTIME_DAMAGE), 0.01,
		"a hit at full overtime should land for the full multiplier")
	assert_gt(after, before, "overtime should make a hit land harder")


## Healing is the half the stalemate actually rested on.
func test_overtime_cuts_healing() -> void:
	var early := _frozen_battle()
	var target := _foe(early)
	target.hp = 1.0
	var before := early.heal(null, target, 100.0)

	var late := _frozen_battle()
	var late_target := _foe(late)
	run_for(late, Sim.OVERTIME_FULL + 1.0)
	late_target.hp = 1.0
	var after := late.heal(null, late_target, 100.0)

	assert_almost_eq(after, before * (1.0 - Sim.OVERTIME_HEAL_CUT), 0.01,
		"a heal at full overtime should land for what is left of it")
	assert_lt(after, before, "overtime should make a heal land softer")


## Shielding is healing under another name as far as a stalemate goes, and it
## was applied by a different function, so it needs its own assertion.
func test_overtime_cuts_shielding() -> void:
	var early := _frozen_battle()
	early.add_shield(_foe(early), 100.0, 10.0)
	var before: float = _foe(early).shield

	var late := _frozen_battle()
	run_for(late, Sim.OVERTIME_FULL + 1.0)
	late.add_shield(_foe(late), 100.0, 10.0)
	var after: float = _foe(late).shield

	assert_almost_eq(after, before * (1.0 - Sim.OVERTIME_HEAL_CUT), 0.01,
		"a shield at full overtime should be worth what is left of it")


## It applies to both teams off the same clock, so it removes the stalemate
## without picking the winner.
func test_overtime_is_symmetric() -> void:
	var sim := _frozen_battle()
	run_for(sim, Sim.OVERTIME_FULL + 1.0)
	var mine := sim.damage(null, sim.teams[Sim.Team.PLAYER][0], 100.0, &"true")
	var theirs := sim.damage(null, sim.teams[Sim.Team.ENEMY][0], 100.0, &"true")
	assert_almost_eq(mine, theirs, 0.01, "overtime should favour neither team")


# --- what it is for ----------------------------------------------------------

## The whole point: a fight nobody can close now closes anyway.
##
## Two boards of healers, which is the shape that ran to the wall and was handed
## to whoever happened to have more health left.
func test_a_sustain_fight_ends_before_the_time_limit() -> void:
	var sim := battle(
		[entry(&"selka", Vector2i(2, 5)), entry(&"kelpar", Vector2i(3, 5)),
			entry(&"hookjaw", Vector2i(4, 5))],
		[entry(&"selka", Vector2i(2, 5)), entry(&"kelpar", Vector2i(3, 5)),
			entry(&"hookjaw", Vector2i(4, 5))])
	sim.run_to_end()
	assert_lt(sim.time, Sim.TIME_LIMIT,
		"a fight between two sustain boards should resolve on its own")


# --- the star curve ----------------------------------------------------------

## Resistances scale with the star, at the same rate attack damage does.
##
## They used to be flat, so every star-up handed a board more health and more
## damage and left mitigation where it was — offence and defence pulling apart
## a little further every time anybody upgraded anything.
func test_resistances_scale_with_star() -> void:
	var def: ChampionDef = content().champion(&"barnaby")
	var one := def.stats_at(1)
	var three := def.stats_at(3)

	assert_gt(three["armor"], one["armor"], "a three-star should be harder to cut")
	assert_almost_eq(three["armor"] / one["armor"],
		pow(ChampionDef.RES_PER_STAR, 2), 0.02,
		"armour should follow the resistance curve")
	assert_almost_eq(three["magic_resist"] / one["magic_resist"],
		pow(ChampionDef.RES_PER_STAR, 2), 0.02,
		"magic resist should follow the same curve")


## The rate is the attack-damage rate deliberately, so a board of three-stars
## fights another board of three-stars at the pace one-stars fight at.
func test_resistances_keep_pace_with_attack_damage() -> void:
	assert_almost_eq(ChampionDef.RES_PER_STAR, ChampionDef.AD_PER_STAR, 0.001,
		"resistances are meant to track the damage they mitigate")


## Tidecaller pours regeneration a unit has no room for into a shield, and the
## overflow is the part health could not take — not the part the heal failed to
## land. Measured off the landed amount, overtime's healing cut gets converted
## into shield instead of being lost, and the one trait built to heal through a
## stalemate comes out of the ramp exactly as strong as it went in.
##
## Asserted on the total the regen delivered — health restored plus shield
## banked — because that is the quantity the cut is supposed to reduce, and it
## is the one the bug leaves untouched.
func _tide_yield(seconds: float, warmup: float) -> float:
	var sim := _frozen_battle()
	var u := _foe(sim)
	if warmup > 0.0:
		run_for(sim, warmup)
	# Room to heal into, so the heal actually lands and can differ from what the
	# regen offered. At full health every formula agrees and nothing is tested.
	u.hp = u.max_hp * 0.9
	u.shields.clear()
	u.recalc_shield()

	var before: float = u.hp
	u.regen = { "pct": 2.0, "cap": 1.0 }
	run_for(sim, seconds)
	return (u.hp - before) + u.shield


func test_overtime_cuts_what_the_tide_regen_delivers() -> void:
	var early := _tide_yield(0.5, 0.0)
	var late := _tide_yield(0.5, Sim.OVERTIME_FULL + 1.0)

	assert_gt(early, 0.0, "the tide regen should deliver something at all")
	assert_lt(late, early * 0.5,
		"overtime should cut the regen's total yield, not move it into the shield")
