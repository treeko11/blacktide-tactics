extends TestCase

## Economy, the shop, and the shared champion pool.

func before_each() -> void:
	state().start_game()


# --- income ------------------------------------------------------------------

func test_base_income_is_five() -> void:
	var captain := Captain.new("Test", "x")
	captain.gold = 0
	assert_eq(captain.round_income(), 5)


func test_interest_pays_one_per_ten_banked() -> void:
	var captain := Captain.new("Test", "x")
	captain.gold = 30
	assert_eq(captain.round_income(), 8, "5 base + 3 interest")


func test_interest_is_capped_at_five() -> void:
	var captain := Captain.new("Test", "x")
	captain.gold = 200
	assert_eq(captain.round_income(), 10, "5 base + 5 interest, no more")


## Losing pays the same streak bonus as winning: a captain being beaten every
## round has to be able to fund the rebuild that gets them back in.
func test_a_losing_streak_pays_the_same_as_a_winning_one() -> void:
	var winner := Captain.new("W", "x")
	var loser := Captain.new("L", "x")
	for i in 5:
		winner.record_result(true)
		loser.record_result(false)
	assert_eq(winner.streak, 5)
	assert_eq(loser.streak, -5)
	assert_eq(winner.round_income(), loser.round_income())


func test_a_loss_breaks_a_winning_streak_immediately() -> void:
	var captain := Captain.new("Test", "x")
	for i in 4:
		captain.record_result(true)
	assert_eq(captain.streak, 4)
	captain.record_result(false)
	assert_eq(captain.streak, -1, "a loss should reset to -1, not to 3")


# --- levelling ---------------------------------------------------------------

func test_xp_carries_over_between_levels() -> void:
	var captain := Captain.new("Test", "x")
	captain.add_xp(4)   # level 1 needs 2, level 2 needs 2
	assert_eq(captain.level, 3, "4 xp should cross two levels")
	assert_eq(captain.xp, 0)


func test_levelling_stops_at_the_cap() -> void:
	var captain := Captain.new("Test", "x")
	captain.add_xp(10000)
	assert_eq(captain.level, Captain.MAX_LEVEL)
	assert_true(captain.is_max_level())


func test_board_capacity_follows_level() -> void:
	var captain := Captain.new("Test", "x")
	assert_eq(captain.board_capacity(), 1)
	captain.add_xp(4)
	assert_eq(captain.board_capacity(), 3)


# --- the shop ----------------------------------------------------------------

func test_a_fresh_shop_offers_five_cards() -> void:
	assert_eq(state().shop.size(), GameState.SHOP_SIZE)


func test_a_level_one_shop_only_offers_one_costs() -> void:
	var s := state()
	s.player.level = 1
	for roll in 20:
		s.return_to_pool_many(s.shop)
		s.shop = s.roll_shop(1)
		for champion_id in s.shop:
			var champion: ChampionDef = content().champion(champion_id)
			assert_eq(champion.cost, 1,
				"level 1 rolled a %d-cost" % champion.cost)


func test_rerolling_costs_two_gold() -> void:
	var s := state()
	s.player.gold = 10
	s.reroll()
	assert_eq(s.player.gold, 8)


func test_rerolling_without_the_gold_is_refused_and_says_so() -> void:
	var s := state()
	s.player.gold = 1
	var notices := probe(events().notice, 2)
	assert_false(s.reroll(), "the reroll should be refused")
	assert_eq(s.player.gold, 1, "and should not have charged")
	assert_eq(notices.size(), 1, "and should have told the player why")


func test_buying_xp_costs_four_and_grants_four() -> void:
	var s := state()
	s.player.gold = 10
	var before: int = s.player.level
	s.buy_xp()
	assert_eq(s.player.gold, 6)
	assert_gt(s.player.level, before)


# --- the shared pool ---------------------------------------------------------

## Every copy of every champion must be somewhere: in the pool, in the shop, or
## on somebody's roster. A card that is rolled and then neither bought nor
## returned silently drains the pool, and the shop slowly stops offering that
## champion to anyone — the kind of bug nobody notices for twenty rounds.
func test_no_champion_copies_are_lost_over_a_long_run() -> void:
	var s := state()
	var expected := _total_copies_at_start()

	for i in 40:
		s.refresh_shop(true)
		for b in s.bots:
			b.take_turn(s)

	assert_eq(_copies_everywhere(), expected,
		"copies leaked or were duplicated after 40 rounds of shopping")


func test_selling_returns_copies_to_the_pool() -> void:
	var s := state()
	s.player.gold = 100
	var champion_id: StringName = s.shop[0]
	assert_true(s.buy(0), "should be able to afford the first card")

	var unit: RosterUnit = null
	for u in s.owned_units():
		if u.id() == champion_id:
			unit = u
			break
	assert_not_null(unit, "the bought pirate should be on the bench")

	var held: int = s.copies_left(champion_id)
	s.sell(unit)
	assert_eq(s.copies_left(champion_id), held + 1, "the copy should go back")


func test_a_two_star_returns_three_copies() -> void:
	var s := state()
	var champion: ChampionDef = content().champion(&"barnaby")
	var before: int = s.copies_left(&"barnaby")
	var unit := RosterUnit.new(champion, 2)
	s.return_to_pool(unit.id(), unit.star)
	assert_eq(s.copies_left(&"barnaby"), before + 3)


func _total_copies_at_start() -> int:
	var total := 0
	for champion in content().shop_champions():
		total += content().pool_size(champion.cost)
	return total


func _copies_everywhere() -> int:
	var s := state()
	var total := 0
	for champion_id in s.pool:
		total += s.pool[champion_id]
	for champion_id in s.shop:
		if champion_id != &"":
			total += 1
	for u in s.owned_units():
		total += int(pow(3, u.star - 1))
	for b in s.bots:
		for u in b.units:
			total += int(pow(3, u.star - 1))
	return total
