extends TestCase

## The sea state: one weather round a stage, and what it does to the fight.
##
## Two halves that fail in completely different ways. The schedule is silent
## when it goes wrong — a stage that forecasts weather it never delivers, or a
## fog bank over a monster round, both look like an ordinary run. And the
## effects are the DPS meter problem: a sea that applies cleanly and changes
## nothing is indistinguishable from a sea that is working, so every one of them
## is asserted on the board or on the numbers rather than on having been called.

const STUN := 60.0


## Everyone frozen, so the only thing that moves anybody is the weather.
func _becalmed(sea: StringName, cells: Array[Vector2i],
		mine: Array[Vector2i], theirs: Array[Vector2i] = []) -> Sim:
	var board_a: Array = []
	for cell in mine:
		board_a.append(entry(&"barnaby", cell))
	var board_b: Array = []
	for cell in theirs:
		board_b.append(entry(&"rat", cell))
	if board_b.is_empty():
		board_b.append(entry(&"rat", Vector2i(0, 0)))

	var sim := battle(board_a, board_b, 12345, sea, cells)
	for u in sim.units:
		u.stun_time = STUN
	return sim


func _column(x: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Hex.ROWS:
		out.append(Vector2i(x, y))
	return out


# --- the definitions ---------------------------------------------------------

## Every sea says what it is, what it does, and has something to do it with.
##
## `Content._verify` already shouts about a missing script, but a def with an
## empty herald is worse and quieter: the round opens, the weather applies, and
## the only thing the player is told is a blank line in the log.
func test_every_sea_is_complete() -> void:
	var seas: Array = content().seas()
	assert_gt(seas.size(), 0, "no sea states loaded at all")
	for def in seas:
		assert_ne(def.id, &"", "a sea has no id")
		assert_ne(def.display_name, "", "%s has no name" % def.id)
		assert_ne(def.herald, "", "%s has no herald line to open the round with" % def.id)
		assert_ne(def.description, "", "%s never says what it does" % def.id)
		assert_ne(def.icon, "", "%s has no icon for the forecast chip" % def.id)
		assert_not_null(content().sea_effect(def.id),
			"%s has no effect script" % def.id)


## The numbers reach the description. A `{token}` left in the text is a sea that
## tells the player "{range} hexes".
func test_a_description_has_no_tokens_left_in_it() -> void:
	for def in content().seas():
		var text: String = def.text()
		assert_false(text.contains("{"),
			"%s still has a token in its description: %s" % [def.id, text])


# --- the schedule ------------------------------------------------------------

## Stage 1 never forecasts weather, because stage 1 never gets any.
##
## Its fourth round is the armoury, and the three before it are monsters — the
## floor a player with anything on the board is meant to clear. A countdown to a
## storm that never arrives is worse than no countdown.
func test_stage_one_is_never_given_weather() -> void:
	GameState.start_game()
	assert_eq(GameState.stage, 1, "a new run should open in stage 1")
	for n in range(1, GameState.rounds_this_stage() + 1):
		GameState.round_number = n
		assert_eq(GameState.rounds_until_sea(), -1,
			"stage 1 round %d claims weather is coming" % n)
		assert_false(GameState.sea_active(), "stage 1 round %d is in weather" % n)


## From stage 2 the forecast counts down and lands on the fixed round.
func test_the_forecast_counts_down_to_the_weather_round() -> void:
	GameState.start_game()
	GameState.stage = 2
	GameState._roll_sea()
	assert_ne(GameState.sea_id, &"", "stage 2 drew no sea at all")

	for n in range(1, 7):
		GameState.round_number = n
		var away := GameState.rounds_until_sea()
		if n < GameState.SEA_ROUND:
			assert_eq(away, GameState.SEA_ROUND - n,
				"round %d should be %d off" % [n, GameState.SEA_ROUND - n])
		elif n == GameState.SEA_ROUND:
			assert_eq(away, 0, "the weather round should report itself")
		else:
			assert_eq(away, -1, "round %d is past the weather" % n)


## A monster round is never fought in weather, wherever the sea round falls.
func test_a_monster_round_is_never_fought_in_weather() -> void:
	GameState.start_game()
	GameState.stage = 2
	GameState._roll_sea()
	for n in range(1, 7):
		GameState.round_number = n
		if GameState.round_type() != &"pvp":
			assert_false(GameState.sea_active(),
				"round 2-%d is a %s and has weather on it"
					% [n, GameState.round_type()])


## Every sea is dealt before any of them comes round again.
##
## Rolled independently each stage, a seven-stage run could be fog three times
## and never once a following sea — and a captain who has met one sea has not
## met the system, they have met that sea. The bag is what makes the order
## random without making the spread random too.
func test_every_sea_is_dealt_before_any_repeats() -> void:
	GameState.start_game()
	var seas: Array = content().seas()
	var seen: Array = []
	for stage in range(2, 2 + seas.size()):
		GameState.stage = stage
		GameState._roll_sea()
		assert_false(seen.has(GameState.sea_id),
			"%s came round again after only %d stages" % [GameState.sea_id, seen.size()])
		seen.append(GameState.sea_id)
	assert_eq(seen.size(), seas.size(), "the hand did not deal every sea")


## A fresh hand never opens on the sea the last one closed with.
##
## The seam is the one place a bag can still repeat, and it is the only place it
## would be noticed — two stages running of the same weather is exactly what the
## bag exists to stop.
func test_a_fresh_hand_never_repeats_the_last_sea() -> void:
	var seas: Array = content().seas()
	for s in 25:
		GameState.start_game()
		GameState.stage = 2
		GameState.rng.seed = s
		GameState._sea_bag.clear()
		for i in seas.size():
			GameState._roll_sea()
		var last: StringName = GameState.sea_id
		GameState._roll_sea()
		assert_ne(GameState.sea_id, last,
			"seed %d dealt %s twice across the seam" % [s, last])


## The same seed deals the same hand in the same order.
func test_the_same_seed_deals_the_same_order() -> void:
	var first: Array = _deal(7)
	var again: Array = _deal(7)
	assert_eq(first, again, "the same seed dealt two different orders")


func _deal(stages: int) -> Array:
	GameState.start_game()
	GameState.rng.seed = 4242
	GameState._sea_bag.clear()
	var out: Array = []
	for i in stages:
		GameState.stage = 2 + i
		GameState._roll_sea()
		out.append(GameState.sea_id)
	return out


## The same run draws the same weather in the same lanes.
##
## The seven fights of the weather round are seven separate sims handed one set
## of cells, and the board is marked from the same set before any of them exist.
## If the lanes were drawn per fight they would disagree, and the marks on the
## board would be a decoration rather than a warning.
func test_the_same_seed_draws_the_same_lanes() -> void:
	var effect: SeaEffect = content().sea_effect(&"rogue_waves")
	var def: SeaDef = content().sea(&"rogue_waves")
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 99
	b.seed = 99
	assert_eq(effect.cells(def, a), effect.cells(def, b),
		"the same seed drew two different sets of lanes")


## A wave has somewhere to push into, wherever its lane lands.
##
## Waves travel toward +x, so a lane on the right-hand edge would be marked
## hazard on the board and then do nothing at all to anybody standing in it.
func test_a_wave_lane_is_never_against_the_right_edge() -> void:
	var effect: SeaEffect = content().sea_effect(&"rogue_waves")
	var def: SeaDef = content().sea(&"rogue_waves")
	var rng := RandomNumberGenerator.new()
	for s in 40:
		rng.seed = s
		for cell in effect.cells(def, rng):
			assert_lt(float(cell.x), float(Hex.COLS - 1),
				"seed %d put a wave lane on the right edge" % s)


# --- what the weather does ---------------------------------------------------

## Fog caps a range that the champion, its items and its traits already set.
##
## Applied last for exactly this reason: a cap that ran before the trait pass
## would be a suggestion, and Lyra would still be shooting five hexes through a
## fog bank.
func test_fog_caps_a_range_after_everything_else_has_raised_it() -> void:
	var clear: Sim = battle([entry(&"lyra", Vector2i(3, 6))], [entry(&"rat", Vector2i(3, 1))])
	var open_range: int = clear.teams[Sim.Team.PLAYER][0].attack_range
	assert_gt(float(open_range), 2.0, "lyra should out-range a fog bank to begin with")

	var cap := int(content().sea(&"fog").value(&"range"))
	var sim := battle([entry(&"lyra", Vector2i(3, 6))], [entry(&"rat", Vector2i(3, 1))],
		12345, &"fog")
	assert_eq(sim.teams[Sim.Team.PLAYER][0].attack_range, cap,
		"fog did not close the range down")


## A wave shoves whoever is standing in its lane one hex sideways.
func test_a_rogue_wave_moves_a_unit_out_of_its_lane() -> void:
	var sim := _becalmed(&"rogue_waves", _column(2), [Vector2i(2, 5)])
	var pirate: SimUnit = sim.teams[Sim.Team.PLAYER][0]
	assert_eq(pirate.cell, Vector2i(2, 5), "the fight did not start where it was told")

	var first: float = content().sea(&"rogue_waves").value(&"first")
	run_for(sim, first + 0.5)
	assert_eq(pirate.cell, Vector2i(3, 5), "the wave left the pirate where it found them")
	assert_eq(sim.unit_at(Vector2i(3, 5)), pirate, "occupancy did not follow the push")
	assert_true(sim.cell_free(Vector2i(2, 5)), "the pirate left a corpse in the old cell")


## Two units in adjacent lanes are pushed from the front, not the back.
##
## Pushed the other way round the leading unit is still standing in the cell the
## one behind is trying to reach, so the whole lane declines to move and the sea
## does nothing while looking like it should have. Cost nothing here and would
## have been invisible in play.
func test_a_wave_pushes_the_leading_unit_first() -> void:
	var cells := _column(2)
	cells.append_array(_column(3))
	var sim := _becalmed(&"rogue_waves", cells, [Vector2i(2, 5), Vector2i(3, 5)])

	var first: float = content().sea(&"rogue_waves").value(&"first")
	run_for(sim, first + 0.5)
	var moved: Array[Vector2i] = []
	for u in sim.teams[Sim.Team.PLAYER]:
		moved.append(u.cell)
	moved.sort()
	assert_eq(moved, [Vector2i(3, 5), Vector2i(4, 5)] as Array[Vector2i],
		"the lane did not move as one")


## The red tide burns what is standing in it and nothing else.
func test_the_red_tide_burns_only_the_rim() -> void:
	var tide: SeaDef = content().sea(&"red_tide")
	var rim := Vector2i(0, 5)
	var inland := Vector2i(3, 5)
	var effect: SeaEffect = content().sea_effect(&"red_tide")
	var sim := _becalmed(&"red_tide", effect.cells(tide, RandomNumberGenerator.new()),
		[rim, inland])

	var burned: SimUnit = sim.unit_at(rim)
	var safe: SimUnit = sim.unit_at(inland)
	assert_not_null(burned, "nobody was seated on the rim")
	assert_not_null(safe, "nobody was seated inland")

	run_for(sim, 3.5)
	assert_lt(burned.hp, burned.max_hp, "the tide did not burn the pirate standing in it")
	assert_eq(safe.hp, safe.max_hp, "the tide reached a pirate three hexes inland")


## A following sea speeds up whoever is in the lane, and never stacks.
##
## `add_buff` does not clamp and it multiplies, so two swells overlapping would
## come off as a permanent compounding buff — the unit would leave the fight
## faster than it entered. The gift has to expire before the next one arrives.
func test_a_following_sea_does_not_stack_its_gift() -> void:
	var def: SeaDef = content().sea(&"following_sea")
	var sim := _becalmed(&"following_sea", _column(2), [Vector2i(2, 5)])
	var pirate: SimUnit = sim.teams[Sim.Team.PLAYER][0]
	var base := pirate.attack_speed

	var first: float = def.value(&"first")
	run_for(sim, first + 0.2)
	var lifted := pirate.attack_speed
	assert_gt(lifted, base, "the current did not speed anybody up")

	# Three more swells. One multiplier at a time, however many have run.
	var interval: float = def.value(&"interval")
	run_for(sim, interval * 3.0)
	assert_lt(pirate.attack_speed, lifted * 1.05,
		"the current stacked: %.3f after four swells against %.3f after one"
			% [pirate.attack_speed, lifted])


## A pirate out of the lane gets nothing, which is what makes the lane a choice.
func test_a_following_sea_only_pays_the_lane() -> void:
	var sim := _becalmed(&"following_sea", _column(2), [Vector2i(2, 5), Vector2i(5, 5)])
	var inside: SimUnit = sim.unit_at(Vector2i(2, 5))
	var outside: SimUnit = sim.unit_at(Vector2i(5, 5))
	var base := outside.attack_speed

	var first: float = content().sea(&"following_sea").value(&"first")
	run_for(sim, first + 0.2)
	assert_gt(inside.attack_speed, base, "the pirate in the lane got nothing")
	assert_eq(outside.attack_speed, base, "the current reached three hexes out of its lane")
