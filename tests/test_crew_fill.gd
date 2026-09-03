extends TestCase

## Spare crew are seated when the fight starts.
##
## A pirate bought and left on the deck does not fight, and the game said so
## only through a crew count in the corner of the shop — so a round bought in
## the last seconds of planning was fought a body down for no decision anybody
## made. `GameState._field_spare_crew` sends the deck up at the bell.
##
## Three of these fail silently if the rule is broken, which is why they are
## assertions on the board rather than on the call. A fill that seats one pirate
## when two seats are open, one that seats a tenth pirate on a nine-seat board,
## or one that overwrites the formation the player spent the round building all
## leave a run that plays perfectly well and is quietly the wrong game.


func before_each() -> void:
	var game := state()
	game.instant = true
	game.start_game()


func after_each() -> void:
	# These end mid-fight, with a sim built and the phase on COMBAT. Everything
	# after them assumes an ordinary run planning its first round.
	var game := state()
	game.instant = false
	game.start_game()


# --- fixtures ----------------------------------------------------------------

## The first champion the content folder offers that fights at this range.
func _champion(melee: bool) -> ChampionDef:
	for champion in content().champions():
		if (champion.attack_range <= 1) == melee:
			return champion
	fail("no %s champion in data/champions" % ("melee" if melee else "ranged"))
	return null


## Puts `count` pirates on the bench, from slot 0 up, and returns them.
func _bench(count: int, melee: bool = true) -> Array[RosterUnit]:
	var game := state()
	var out: Array[RosterUnit] = []
	for i in count:
		var unit := RosterUnit.new(_champion(melee))
		game.bench[i] = unit
		out.append(unit)
	return out


## Puts the run on the weather round with `id`'s water at `cells`.
func _weather(id: StringName, cells: Array[Vector2i]) -> void:
	var game := state()
	game.stage = 2
	game.round_number = game.SEA_ROUND
	game.sea_id = id
	game.sea_cells = cells
	assert_true(game.sea_active(), "the fixture is not on the weather round")


## Every hex on the board, for the case where there is nowhere dry left.
func _whole_board() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in Hex.ROWS:
		for x in Hex.COLS:
			out.append(Vector2i(x, y))
	return out


# --- the fill ----------------------------------------------------------------

func test_a_spare_pirate_is_seated_when_the_fight_starts() -> void:
	var game := state()
	game.player.level = 1
	var spare := _bench(1)

	game.start_combat_now()
	game._process(1.0 / 60.0)

	assert_eq(game.phase, game.Phase.COMBAT, "the fight never started")
	assert_eq(game.board.size(), 1, "the empty seat was fought with nobody in it")
	assert_true(game.board.has(spare[0]), "somebody other than the deck's first was seated")
	assert_null(game.bench[0], "the pirate was seated and left on the bench as well")
	assert_true(Hex.is_player_half(spare[0].cell), "seated outside the player's half")


func test_it_fills_every_empty_seat_not_just_one() -> void:
	var game := state()
	game.player.level = 3
	var spare := _bench(3)

	game._field_spare_crew()

	assert_eq(game.board.size(), 3, "a crew of three went to sea with fewer")
	for i in 3:
		assert_true(game.board.has(spare[i]), "deck slot %d was left behind" % i)


func test_it_takes_the_deck_in_order() -> void:
	var game := state()
	game.player.level = 1
	var spare := _bench(3)

	game._field_spare_crew()

	assert_eq(game.board.size(), 1)
	assert_true(game.board.has(spare[0]), "the first off the bench was not the first seated")


func test_it_never_seats_more_than_the_crew_capacity() -> void:
	var game := state()
	game.player.level = 2
	var spare := _bench(5)

	game._field_spare_crew()

	assert_eq(game.board.size(), 2, "the fill sailed over capacity")
	assert_eq(game.bench[2], spare[2], "a pirate past capacity left the bench anyway")


func test_a_full_crew_is_left_alone() -> void:
	var game := state()
	game.player.level = 1
	var seated := RosterUnit.new(_champion(true))
	seated.cell = Vector2i(3, 5)
	game.board.append(seated)
	var spare := _bench(1)
	var notices := probe(Events.notice, 2)

	game._field_spare_crew()

	assert_eq(game.board.size(), 1, "a full board was filled past its capacity")
	assert_eq(game.bench[0], spare[0], "a pirate was seated with no seat to take")
	assert_eq(seated.cell, Vector2i(3, 5), "the seated pirate was moved")
	assert_eq(notices.size(), 0, "the player was told about a fill that did not happen")


## The formation is the whole game. A fill that moves somebody the player placed
## is worse than the empty seat it was fixing.
func test_it_never_moves_a_pirate_the_player_placed() -> void:
	var game := state()
	game.player.level = 3
	var seated := RosterUnit.new(_champion(true))
	seated.cell = Vector2i(3, 4)
	game.board.append(seated)
	_bench(2)

	game._field_spare_crew()

	assert_eq(game.board.size(), 3)
	assert_eq(seated.cell, Vector2i(3, 4), "the player's own placement was overwritten")
	var cells := {}
	for u in game.board:
		assert_false(cells.has(u.cell), "two pirates were seated in one hex")
		cells[u.cell] = true


func test_melee_are_seated_in_front_of_ranged() -> void:
	var game := state()
	game.player.level = 2
	var brawler := RosterUnit.new(_champion(true))
	var shooter := RosterUnit.new(_champion(false))
	game.bench[0] = brawler
	game.bench[1] = shooter

	game._field_spare_crew()

	assert_lt(float(brawler.cell.y), float(shooter.cell.y),
		"the bombardier was seated in front of the brawler")


## A board that rearranges itself with nothing on screen to say why is
## indistinguishable from a bug.
func test_the_fill_is_announced() -> void:
	var game := state()
	game.player.level = 1
	_bench(1)
	var notices := probe(Events.notice, 2)
	var lines := probe(Events.logged, 2)

	game._field_spare_crew()

	assert_eq(notices.size(), 1, "nothing was said about the pirate that was seated")
	assert_eq(lines.size(), 1, "the fill left no line in the log")


func test_an_empty_deck_changes_nothing() -> void:
	var game := state()
	game.player.level = 5
	var notices := probe(Events.notice, 2)

	game._field_spare_crew()

	assert_eq(game.board.size(), 0, "somebody was seated out of an empty deck")
	assert_eq(notices.size(), 0, "the player was told about a fill with nobody in it")


# --- the fill and the weather ------------------------------------------------

## A pirate sent up at the bell is not stood in the hazard.
##
## The sea's whole premise is that the player has the planning phase to answer
## it. A pirate the bosun seats has had no planning phase, so the game was
## making that call on the player's behalf and then announcing it as help.
## Witchfire was the sharpest version — its hexes are the middle three columns
## of row 4, which is exactly the first three seats the fill takes.
func test_the_bosun_seats_a_spare_pirate_out_of_the_marked_water() -> void:
	var game := state()
	game.player.level = 1
	# The three seats a melee pirate is offered first, all under water.
	_weather(&"red_tide", [Vector2i(3, 4), Vector2i(2, 4), Vector2i(4, 4)] as Array[Vector2i])
	var spare := _bench(1, true)

	game._field_spare_crew()

	assert_eq(game.board.size(), 1, "the spare pirate was not fielded at all")
	assert_true(Hex.is_player_half(spare[0].cell), "seated outside the player's half")
	assert_false(game.sea_cells.has(spare[0].cell),
		"the bosun stood the pirate in the red tide, at %s" % spare[0].cell)


## Dry water is a preference, never a reason to sail a body down.
##
## Sailing a seat short is the failure this whole function exists to prevent, so
## a board with nothing but marked hexes left still fields the pirate. Written
## because the obvious implementation — filter the seats, take the first — turns
## a hazard round into the bug the fill was added to fix.
func test_a_board_of_nothing_but_hazard_still_fields_the_pirate() -> void:
	var game := state()
	game.player.level = 1
	_weather(&"red_tide", _whole_board())
	var spare := _bench(1, true)

	game._field_spare_crew()

	assert_eq(game.board.size(), 1,
		"every hex was hazard, so the pirate was left on the deck instead")
	assert_true(game.board.has(spare[0]), "somebody other than the deck's first was seated")


## A fair wind is not chased.
##
## Which pirate is worth standing in one is a positioning decision, and taking
## it here would mean overriding the melee-forward, ranged-back order — which is
## already the better answer for a crew nobody placed. So a boon round seats
## exactly where calm water would have.
func test_the_bosun_does_not_chase_a_fair_wind() -> void:
	var game := state()
	game.player.level = 1
	var spare := _bench(1, true)
	game._field_spare_crew()
	var calm: Vector2i = spare[0].cell
	assert_true(Hex.on_board(calm), "the calm-water fixture seated nobody")

	game.start_game()
	game.player.level = 1
	# A fair wind in the back rank. Chased, it would drag a melee pirate behind
	# the ranged line; left alone, the seat is the one calm water gave.
	_weather(&"following_sea", [Vector2i(0, 7)] as Array[Vector2i])
	var again := _bench(1, true)
	game._field_spare_crew()

	assert_eq(again[0].cell, calm,
		"the bosun went looking for the fair wind instead of taking its seat")
