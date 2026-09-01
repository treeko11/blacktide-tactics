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


# --- what a shop card says about your own fleet -------------------------------

## The playtest note was misread the first time round: the ask is not "two of
## these are in the shop", it is "you already have one of these". A card the
## player owns a copy of has to say so, at any star, whether or not a purchase
## would merge.
func test_a_card_reports_a_copy_already_in_the_fleet() -> void:
	var s := state()
	_clear_shop()
	s.shop[0] = &"barnaby"
	s.board.append(RosterUnit.new(content().champion(&"barnaby"), 1))

	var info: Dictionary = s.shop_slot_info(0)
	assert_eq(info["owned"], 1)
	assert_eq(info["fleet_count"], 1)
	assert_false(info["completes_upgrade"], "one copy is not a star-up yet")


## A two-star copy will not merge with a fresh purchase, so `owned` is zero — but
## the pirate is still one of the player's, and the card has to say so.
func test_a_starred_up_copy_still_counts_as_in_the_fleet() -> void:
	var s := state()
	_clear_shop()
	s.shop[0] = &"barnaby"
	s.board.append(RosterUnit.new(content().champion(&"barnaby"), 2))

	var info: Dictionary = s.shop_slot_info(0)
	assert_eq(info["owned"], 0, "a two-star has nothing to merge with")
	assert_eq(info["fleet_count"], 1)
	assert_eq(info["fleet_star"], 2)


func test_a_benched_copy_counts_the_same_as_a_fielded_one() -> void:
	var s := state()
	_clear_shop()
	s.shop[0] = &"barnaby"
	s.bench[0] = RosterUnit.new(content().champion(&"barnaby"), 1)

	assert_eq(s.shop_slot_info(0)["fleet_count"], 1)


## One in the fleet and two on the counter is the same star-up as two in the
## fleet, it just costs twice.
func test_one_owned_plus_a_pair_in_the_shop_is_flagged_as_a_star_up() -> void:
	var s := state()
	_clear_shop()
	s.shop[0] = &"barnaby"
	s.shop[1] = &"barnaby"
	s.board.append(RosterUnit.new(content().champion(&"barnaby"), 1))

	var info: Dictionary = s.shop_slot_info(0)
	assert_eq(info["copies_in_shop"], 2)
	assert_true(info["pair_completes_upgrade"])
	assert_false(info["completes_upgrade"])


func test_a_pair_in_the_shop_alone_is_not_ownership() -> void:
	var s := state()
	_clear_shop()
	s.shop[0] = &"barnaby"
	s.shop[1] = &"barnaby"

	var info: Dictionary = s.shop_slot_info(0)
	assert_true(info["duplicate_in_shop"])
	assert_eq(info["fleet_count"], 0, "nothing is owned yet")
	assert_false(info["pair_completes_upgrade"])


# --- the armoury --------------------------------------------------------------

## The armoury modal cannot be dismissed, so an empty offer stops the run dead —
## which is what happened: _open_armoury announced the phase before it filled
## armoury_offer, handing Main the array the previous stage's pickup had cleared.
func test_the_armoury_offer_is_ready_before_the_phase_is_announced() -> void:
	var s := state()
	s.instant = true
	s.speed = 64

	# A Dictionary, not a local: a lambda captures by value, so assigning to a
	# captured int from inside the handler would silently do nothing.
	var seen := { "opened": 0, "empty": 0 }
	var watch := func(next_phase: int) -> void:
		if next_phase == s.Phase.ARMOURY:
			seen["opened"] += 1
			if s.armoury_offer.is_empty():
				seen["empty"] += 1
	Events.phase_changed.connect(watch)

	for i in 3000:
		if seen["opened"] >= 2:
			break
		if s.phase == s.Phase.PLAN:
			s.start_combat_now()
		elif s.phase == s.Phase.ARMOURY:
			s.take_armoury_item(s.armoury_offer[0])
		elif s.phase == s.Phase.OVER:
			break
		s._process(0.5)

	Events.phase_changed.disconnect(watch)

	assert_gt(float(seen["opened"]), 1.0, "the run should have reached two armouries")
	assert_eq(seen["empty"], 0, "an armoury opened with nothing to take")


## The shop is rolled at random, so a test naming a champion has to start from an
## empty counter or a stray roll of the same pirate skews the count.
func _clear_shop() -> void:
	var s := state()
	for i in s.shop.size():
		s.shop[i] = &""


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
