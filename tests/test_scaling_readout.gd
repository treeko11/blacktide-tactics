extends TestCase

## The two halves of "what will this actually do", both of which fail silently.
##
## An ability description used to print the number authored in the .tres and
## stop there, so a pirate with items on read exactly the same as one straight
## out of the shop — the mark said "AP" and nothing said what the AP came to.
## And six items grow permanently over a fight while their description only ever
## promised that they would; the total went into the Attack figure at the top of
## the panel, where it is mixed in with the star curve, the traits and every
## other item and cannot be got back out. Neither looks like a bug from the
## outside. A frozen figure is still a figure, and a snowball that reports
## nothing looks like one that has not procced yet — which is why every
## assertion here is on a number.


func after_each() -> void:
	state().start_game()


# =============================================================================
#  Resolving an ability's numbers against the caster
# =============================================================================

## Corvane is one of the four hybrids: one figure off attack damage and one off
## ability power, in the same sentence. If either resolved against the wrong
## stat the sentence would still read perfectly.
func test_a_hybrid_resolves_each_number_against_its_own_stat() -> void:
	var sim := battle(
		[entry(&"corvane", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]
	unit.ad = 100.0
	unit.ability_power = 200.0

	var ability: Ability = content().ability(&"corvane")
	var text: String = content().format_description(
		unit.def.ability_desc, unit.def.ability_values, 1, ability.scaling(), unit)

	# 120% of 100 attack is 120; 80 at double power is 160.
	assert_true(text.contains("(120)"), "the AD figure did not resolve: %s" % text)
	assert_true(text.contains("(160)"), "the AP figure did not resolve: %s" % text)


## The figures follow the caster, which is the whole complaint — a stat block
## that updates over a fight above a description frozen at what the shop said.
func test_a_resolved_figure_moves_when_the_stat_does() -> void:
	var sim := battle(
		[entry(&"squall", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]
	var ability: Ability = content().ability(&"squall")

	unit.ability_power = SimUnit.BASE_AP
	var before: String = content().format_description(
		unit.def.ability_desc, unit.def.ability_values, 1, ability.scaling(), unit)
	unit.ability_power = SimUnit.BASE_AP * 2.0
	var after: String = content().format_description(
		unit.def.ability_desc, unit.def.ability_values, 1, ability.scaling(), unit)

	assert_ne(after, before, "doubling ability power changed nothing in the text")
	var base: float = unit.def.ability_values[&"dmg"][0]
	assert_true(after.contains("(%d)" % roundi(base * 2.0)),
		"the resolved figure did not double: %s" % after)


## The authored number survives beside the resolved one. Losing it would leave
## the player nothing to compare against, which is the only on-screen sign that
## their ability power is doing anything at all.
func test_the_authored_number_is_still_shown() -> void:
	var sim := battle(
		[entry(&"squall", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]
	unit.ability_power = SimUnit.BASE_AP * 3.0
	var ability: Ability = content().ability(&"squall")
	var text: String = content().format_description(
		unit.def.ability_desc, unit.def.ability_values, 1, ability.scaling(), unit)

	var base: float = unit.def.ability_values[&"dmg"][0]
	assert_true(text.contains("[b]%d[/b]" % roundi(base)),
		"the authored figure was replaced rather than annotated: %s" % text)


## No caster, no brackets. A shop card and an almanac page come through the same
## function and have no unit to resolve against — and a trait or an item has no
## caster at all, which is why `scaling` was a parameter in the first place.
func test_nothing_resolves_without_a_caster() -> void:
	var def: ChampionDef = content().champion(&"squall")
	var ability: Ability = content().ability(&"squall")
	var text: String = content().format_description(
		def.ability_desc, def.ability_values, 1, ability.scaling())
	assert_false(text.contains("("), "a bracket appeared with no caster: %s" % text)

	var every_star: String = content().format_description(
		def.ability_desc, def.ability_values, 0, ability.scaling())
	assert_true(every_star.contains("/"), "the all-stars form stopped listing stars")


## A number that scales off nothing is left alone. A stun duration and a shred
## percentage are the same figure at any stat line, so a bracket after one would
## be a lie in the shape of a helpful annotation.
func test_an_unscaled_number_gets_no_bracket() -> void:
	var sim := battle(
		[entry(&"dredge", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]
	var ability: Ability = content().ability(&"dredge")
	assert_false(ability.scaling().has(&"stun"),
		"this test needs an ability whose stun is unscaled")

	var text: String = content().format_description(
		unit.def.ability_desc, unit.def.ability_values, 1, ability.scaling(), unit)
	# One bracket per scaled key and no more, so the unscaled stun cannot have
	# been given one.
	assert_eq(text.count("("), ability.scaling().size(),
		"an unscaled figure was given a resolved bracket: %s" % text)


## The resolver agrees with the arithmetic the abilities themselves do. It is a
## second copy of that arithmetic — the deliberate cost of keeping a cast from
## reading its own damage out of the function the tooltip prints — so the thing
## that keeps the copy honest has to be a test.
func test_the_resolver_matches_what_a_cast_would_compute() -> void:
	var sim := battle(
		[entry(&"corvane", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]
	unit.ad = 137.0
	unit.ability_power = 250.0
	var ability: Ability = content().ability(&"corvane")

	assert_almost_eq(Ability.resolve(&"ap", 80.0, unit), ability.scaled(unit, &"bonus"),
		0.001, "the AP resolver disagrees with scaled()")
	assert_almost_eq(Ability.resolve(&"ad", 120.0, unit), unit.ad * 1.20,
		0.001, "the AD resolver is not a percentage of attack")


# =============================================================================
#  What a growing item has gathered
# =============================================================================

## The Bloodletter is the plain case: kills, and nothing else, make it grow.
func test_the_bloodletter_reports_what_it_has_gathered() -> void:
	var sim := battle(
		[entry(&"corvane", Vector2i(3, 5), 1, [&"bloodletter"])],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	assert_true(ItemEffect.gathered(unit, &"bloodletter").is_empty(),
		"an item reported growth before it had grown")

	var before := unit.ad
	for hook in unit.hooks_on_kill:
		hook.call(unit, sim.units[1])

	assert_almost_eq(unit.ad, before + 10.0, 0.001, "the kill granted no attack")
	assert_almost_eq(ItemEffect.gathered(unit, &"bloodletter").get(&"ad", 0.0),
		10.0, 0.001, "the kill was not recorded")

	var text := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	assert_true(text.contains("GATHERED"), "the inspector did not report the growth")
	assert_true(text.contains("+10 Attack"),
		"the inspector did not say how much: %s" % text)


## Siren's Locket grows on a cast rather than on a kill, and grows the stat the
## abilities scale off — so one fight moves both the gathered line and every
## bracketed figure above it.
func test_the_locket_reports_what_it_has_gathered() -> void:
	var sim := battle(
		[entry(&"squall", Vector2i(3, 5), 1, [&"sirens_locket"])],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	for i in 3:
		for hook in unit.hooks_on_cast:
			hook.call(unit)

	assert_almost_eq(ItemEffect.gathered(unit, &"sirens_locket").get(&"ap", 0.0),
		30.0, 0.001, "three casts did not record 30 ability power")

	var text := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	assert_true(text.contains("+30 Ability Power"),
		"the inspector did not report the locket's growth: %s" % text)


## Attack speed is granted as a multiplier, so it is reported as one. Two 1.07s
## are 1.145 and not "14%", and a sum here would quietly overstate the item.
func test_gathered_attack_speed_compounds() -> void:
	var sim := battle(
		[entry(&"corvane", Vector2i(3, 5), 1, [&"red_tally"])],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	for hook in unit.hooks_on_attack:
		hook.call(unit, sim.units[1])
		hook.call(unit, sim.units[1])

	assert_almost_eq(ItemEffect.gathered(unit, &"red_tally").get(&"as", 0.0),
		1.07 * 1.07, 0.001, "gathered attack speed was summed rather than compounded")


## Two snowballs on one pirate keep separate books, because the record is keyed
## by item — pooled, both totals would match neither description.
func test_two_snowballs_keep_separate_books() -> void:
	var sim := battle(
		[entry(&"corvane", Vector2i(3, 5), 1, [&"bloodletter", &"butchers_bill"])],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	for hook in unit.hooks_on_kill:
		hook.call(unit, sim.units[1])

	assert_almost_eq(ItemEffect.gathered(unit, &"bloodletter").get(&"ad", 0.0),
		10.0, 0.001, "the Bloodletter's total picked up its neighbour's grant")
	assert_almost_eq(ItemEffect.gathered(unit, &"butchers_bill").get(&"ad", 0.0),
		15.0, 0.001, "the Butcher's Bill's total picked up its neighbour's grant")


## A bounded item's stack counter and its gathered record are different keys.
## Boarding Hooks and the Ribcage were the only two items already spending their
## own id slot in `unit.scratch`, which is why the record does not live there.
func test_a_bounded_item_still_counts_its_stacks() -> void:
	var sim := battle(
		[entry(&"corvane", Vector2i(3, 5), 1, [&"boarding_hooks"])],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	for hook in unit.hooks_on_attack:
		hook.call(unit, sim.units[1])

	assert_eq(unit.scratch.get(&"boarding_hooks", 0), 1, "the stack count was lost")
	assert_almost_eq(ItemEffect.gathered(unit, &"boarding_hooks").get(&"armor", 0.0),
		3.0, 0.001, "the gathered armour was not recorded")


## An item that does not grow says nothing, rather than a row of zeroes on every
## item in the game.
func test_a_static_item_reports_nothing() -> void:
	var sim := battle(
		[entry(&"corvane", Vector2i(3, 5), 1, [&"blade"])],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]
	var text := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	assert_false(text.contains("GATHERED"),
		"a static item claimed to have gathered something: %s" % text)


## Nothing is reported outside a fight. The growth is fight-scoped — items are
## re-applied in `Sim._init` every round — so a total shown on a benched pirate
## would be last round's, which is worse than none at all.
func test_nothing_is_gathered_outside_a_fight() -> void:
	var def: ChampionDef = content().champion(&"corvane")
	var text := Tooltip.champion_text(def, 1, [&"bloodletter"])
	assert_false(text.contains("GATHERED"),
		"a bench inspector reported growth: %s" % text)
	assert_true(text.contains("The Bloodletter"),
		"the item vanished from the bench inspector: %s" % text)
