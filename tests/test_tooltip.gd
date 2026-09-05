extends TestCase

## The inspector reads its subject back rather than remembering it.
##
## The text used to be built once, by the handler that opened the tooltip, which
## made every number in it a photograph. Mid-fight that was the worst of it: the
## board only reports a hover when the cursor *moves*, so a stat block held still
## to be read was frozen at whatever was true when the cursor arrived, and a
## pinned one on a phone never changed at all.
##
## These call `_reread()` directly instead of waiting for the tooltip's own
## timer, because a test method here cannot await frames.

func _tooltip() -> Tooltip:
	var tip := Tooltip.new()
	Engine.get_main_loop().root.add_child(tip)
	return tip


## The carrier tests below start a run and then seat a pirate, and the autoload
## they do it in is shared by every file after this one — `test_wiki` renders
## pages that read `GameState.board_traits()` and the player's items. Leaving a
## Kelpar on the board is a fixture leaking into somebody else's test.
func after_each() -> void:
	state().start_game()


## The one that matters: health falling during a fight has to reach the panel.
func test_a_live_stat_block_follows_the_pirate_it_describes() -> void:
	var sim := battle(
		[entry(&"ashmore", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	var tip := _tooltip()
	var refresh := func() -> String:
		if not unit.alive:
			return ""
		return Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	tip.show_text(refresh.call(), Vector2.ZERO, null, refresh)

	var before: String = tip._body.text
	assert_true(before.contains(str(roundi(unit.hp))), "the stat block did not show health")

	unit.hp -= 30.0
	tip._reread()
	assert_ne(tip._body.text, before, "the stat block did not change when health did")
	assert_true(tip._body.text.contains(str(roundi(unit.hp))),
		"the stat block did not show the new health")

	tip.hide_now()
	tip.queue_free()


## A pirate that died keeps its numbers, and says so.
##
## The reported bug was "tooltips stop working after victory/defeat": the board
## text builder treated a dead pirate and a finished fight as a subject that had
## gone, so the inspector emptied itself the moment the fight it was reading
## ended — with the survivors still standing on the board being looked at. The
## last numbers a pirate had are the ones somebody who just watched it die is
## reading the panel for. The marker is the other half: a frozen block with
## nothing to say why is indistinguishable from one that stopped updating.
func test_a_dead_pirate_keeps_its_last_numbers() -> void:
	var sim := battle(
		[entry(&"ashmore", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]
	unit.hp = 340.0

	var alive_text := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	assert_false(alive_text.contains("Fallen"), "a living pirate was marked as fallen")

	unit.alive = false
	var fallen := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	assert_true(fallen.contains("Fallen"), "a dead pirate's block did not say it had fallen")
	assert_true(fallen.contains("340"),
		"a dead pirate's block lost the health it had when it went down")
	assert_true(fallen.contains(unit.def.display_name),
		"a dead pirate's block lost the pirate's name")


## An empty refresh means the subject is gone, and closes the inspector.
##
## This is the only way a *pinned* one on a touchscreen ever finds out: nothing
## un-hovers a finger, so a pirate sold or merged between fights, or one from a
## fight the round has moved on from, would otherwise leave a panel describing
## something that is no longer on the board. A pirate that merely *died* is not
## that — it keeps its last numbers; see the test above — so the refresh here is
## the tooltip's contract being exercised rather than the board's rule.
func test_an_inspector_closes_when_its_subject_is_gone() -> void:
	var sim := battle(
		[entry(&"ashmore", Vector2i(3, 5))],
		[entry(&"brine", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	var tip := _tooltip()
	var refresh := func() -> String:
		if not unit.alive:
			return ""
		return Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	tip.pin(refresh.call(), Vector2.ZERO, null, refresh)
	assert_true(tip.pinned, "the inspector did not pin")

	unit.alive = false
	tip._reread()
	assert_false(tip.visible, "the inspector stayed open over a dead pirate")
	assert_false(tip.pinned, "the inspector stayed pinned over a dead pirate")

	tip.queue_free()


## A closed inspector must not keep a battle alive.
##
## A refresh for a fight is a lambda holding a SimUnit, and a SimUnit holds its
## target, its hooks and its captured casters — the reference cycles that
## `Sim.dispose()` exists to break. A tooltip that kept its last refresh would
## pin one whole fight in memory per hover.
func test_closing_an_inspector_drops_what_it_was_reading() -> void:
	var tip := _tooltip()
	tip.show_text("something", Vector2.ZERO, null, func() -> String: return "still here")
	assert_true(tip._refresh_source.is_valid(), "the refresh was not stored")

	tip.hide_now()
	assert_false(tip._refresh_source.is_valid(), "the refresh outlived the inspector")

	tip.queue_free()


## A champion gets its figure beside the text; nothing else does.
##
## The portrait is a node rather than anything in the body string, so every
## existing check here — which compares text — passes whether it appears or not.
## And the gap it reserves comes out of the body's width, so a portrait left
## showing for an item is also a stat block wrapped forty points narrower than it
## needed to be, on the panel that is already most of a phone screen.
func test_only_a_champion_gets_a_portrait() -> void:
	var tip := _tooltip()
	var champion: ChampionDef = content().champion(&"sirene")
	assert_not_null(champion, "no champion called sirene to inspect")

	var full: float = tip._body.custom_minimum_size.x
	tip.show_text(Tooltip.champion_text(champion, 1), Vector2.ZERO, null,
		Callable(), champion)
	assert_true(tip._portrait.visible, "a pirate's inspector drew no figure")
	assert_eq(tip._portrait.champion, champion, "the figure is of the wrong pirate")
	assert_lt(tip._body.custom_minimum_size.x, full,
		"the portrait took no width from the text, so it has nowhere to go")

	tip.show_text(Tooltip.item_text(&"blade"), Vector2.ZERO)
	assert_false(tip._portrait.visible, "an item's inspector drew a pirate")
	assert_eq(tip._body.custom_minimum_size.x, full,
		"the text never got its width back")

	tip.show_text(Tooltip.champion_text(champion, 1), Vector2.ZERO, null,
		Callable(), champion)
	tip.hide_now()
	assert_false(tip._portrait.visible,
		"a closed inspector still holds the last pirate it showed")

	tip.free()


## A trait's inspector names every pirate that carries it.
##
## The breakpoint list says a trait wants two more pirates and never says which,
## so the only place that answered was the almanac — a full-screen dialog over
## the shop, opened mid-decision with the planning clock running.
func test_a_trait_lists_every_pirate_that_carries_it() -> void:
	state().start_game()
	var text := Tooltip.trait_text(&"leviathan", 0, -1)

	var carriers := 0
	for champion in content().champions():
		if champion.cost <= 0 or not champion.has_trait(&"leviathan"):
			continue
		carriers += 1
		assert_true(text.contains(champion.display_name),
			"%s carries Leviathan and the inspector did not name it"
				% champion.display_name)
	assert_gt(carriers, 0, "no pirate carries Leviathan, so the test proves nothing")


## The marks are live: they say where the player's own copies are.
##
## The text is rebuilt ten times a second, so seating a pirate has to change what
## the badge's inspector says about it while that inspector is open. A bench copy
## is the interesting one — it is a breakpoint sitting in the hold.
func test_the_carrier_list_marks_what_the_player_owns() -> void:
	var s := state()
	s.start_game()

	var champion: ChampionDef = content().champion(&"kelpar")
	assert_not_null(champion, "no champion called kelpar to seat")
	assert_true(champion.has_trait(&"leviathan"), "kelpar stopped being a Leviathan")

	var unowned := Tooltip.trait_text(&"leviathan", 0, -1)

	var unit := RosterUnit.new(champion, 1)
	s.bench[s.first_free_bench_slot()] = unit
	var benched := Tooltip.trait_text(&"leviathan", 0, -1)
	assert_ne(benched, unowned, "a bench copy did not change how it is listed")

	s.move_to_board(unit, Vector2i(3, 5))
	var fielded := Tooltip.trait_text(&"leviathan", 1, -1)
	assert_ne(fielded, benched, "seating a pirate did not change how it is listed")
	assert_true(fielded.contains("✔ %s" % champion.display_name),
		"a pirate on the board is not marked as one of the ones being counted")


# --- ability scaling ---------------------------------------------------------
#
# The marks beside the ability numbers are the only thing in the HUD that says
# what a figure is driven by, and the way they break is silent: a tag that never
# renders leaves a bare number that looks finished, and throws nothing.
#
# The legend that used to spell the marks out underneath is gone - two lines of
# glossary on a panel that is most of the screen on a phone, above a stat block
# already naming both stats - so what is asserted here is the marks themselves.

## An ability power number is marked with the stat that drives it.
func test_an_ability_number_is_marked_with_the_stat_that_drives_it() -> void:
	var nautica: ChampionDef = content().champion(&"nautica")
	var text := Tooltip.champion_text(nautica, 1)

	# The whole mark, colour included — that is what actually reaches the label,
	# and the colour is the half a glance reads before the letters do.
	assert_true(text.contains(Content.scaling_tag(&"ap")),
		"the ability power mark is missing from the ability text")
	assert_false(text.contains(Content.scaling_tag(&"ad")),
		"an ability that reads nothing off attack damage was marked for it")


## A hybrid carries both marks, which is the whole reason they are on the numbers
## rather than on the ability. Finn deals a percentage of attack damage and a
## flat true-damage figure in the same sentence.
func test_a_hybrid_ability_marks_each_number_separately() -> void:
	var finn: ChampionDef = content().champion(&"finn")
	var text := Tooltip.champion_text(finn, 1)

	assert_true(text.contains(Content.scaling_tag(&"ad")),
		"the attack damage mark is missing")
	assert_true(text.contains(Content.scaling_tag(&"ap")),
		"the ability power mark is missing")


## An ability that scales off nothing carries no mark at all. Tuck hands out
## mana and haste, and both are the same figure however the pirate is built, so
## a mark on either would be a lie in the shape of a helpful annotation.
func test_an_unscaled_ability_gets_no_marks() -> void:
	var tuck: ChampionDef = content().champion(&"tuck")
	var text := Tooltip.champion_text(tuck, 1)
	assert_false(text.contains(Content.scaling_tag(&"ad")),
		"an ability that scales off nothing was marked for attack damage")
	assert_false(text.contains(Content.scaling_tag(&"ap")),
		"an ability that scales off nothing was marked for ability power")


## Ability power is in the stat block on every champion, at its baseline, so it
## is a stat a player can find before anything has granted them any.
func test_the_stat_block_always_carries_ability_power() -> void:
	var missing: Array[String] = []
	for champion in content().champions():
		if not Tooltip.champion_text(champion, 1).contains("Ability Power ["):
			missing.append(String(champion.id))
	assert_true(missing.is_empty(),
		"no ability power in the stat block for: %s" % ", ".join(missing))


## The live block reports the multiplier the fight is actually using, which is
## the number that matters — 100 is the baseline the printed figures are written
## at, so what a player wants is not "180" but "1.8 times the page".
func test_bonus_ability_power_shows_as_a_multiplier() -> void:
	var sim := battle(
		[entry(&"nautica", Vector2i(3, 5))],
		[entry(&"rat", Vector2i(3, 1))])
	var unit: SimUnit = sim.units[0]

	var base := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	assert_true(base.contains("×1.00"), "a pirate at base did not read as ×1.00")

	unit.ability_power += 80.0
	var boosted := Tooltip.champion_text(unit.def, unit.star, unit.items, unit)
	assert_true(boosted.contains("×1.80"),
		"+80 ability power did not read as ×1.80")
	assert_true(boosted.contains("180"), "the stat block lost the raw figure")


# =============================================================================
#  The forge preview
# =============================================================================
#
# What two components make, answered from the drag rather than after the drop.
# Equipping cannot be undone, so this is the one inspector in the game that has
# to be right *before* the player commits to anything.


## It is the forged item's own page, not a name.
##
## Naming the result was the old answer, and it is half of one: "Forges The
## Bloodletter" says nothing about what the Bloodletter does, which is the whole
## question. So the preview carries the same text the almanac and the forge
## chart give for that item.
func test_a_forge_preview_carries_the_forged_item_itself() -> void:
	var made: ItemDef = content().item_def(content().forge(&"blade", &"blade"))
	var text := Tooltip.forge_text(&"blade", &"blade")

	assert_true(text.contains(made.display_name),
		"the preview did not name what the pair forges into")
	assert_true(text.contains(made.description),
		"the preview named the item without saying what it does")
	assert_true(text.contains(content().item_def(&"blade").display_name),
		"the preview did not say which two components it was describing")


## Two components that do not pair produce nothing at all.
##
## "" is also the tooltip's own signal that its subject has gone, so a preview
## whose pairing stops being possible closes itself rather than sitting there
## promising an item nobody can forge.
func test_a_pair_that_does_not_forge_previews_nothing() -> void:
	var finished: StringName = content().forge(&"blade", &"blade")
	assert_eq(Tooltip.forge_text(&"blade", finished), "",
		"a component and a finished item were offered as a forge")
	assert_eq(Tooltip.forge_text(finished, finished), "",
		"two finished items were offered as a forge")


## Over a pirate it says whose slots it is about to fill; loose in the hold it
## says where the drop has to go, because the hold is not where forging happens.
func test_a_forge_preview_says_where_the_drop_goes() -> void:
	var champion: ChampionDef = content().champion(&"ashmore")
	var unit := RosterUnit.new(champion)
	var on_pirate := Tooltip.forge_text(&"blade", &"plate", unit)
	assert_true(on_pirate.contains(unit.champion.display_name),
		"a forge on a pirate did not name the pirate")

	var loose := Tooltip.forge_text(&"blade", &"plate")
	assert_false(loose.contains(unit.champion.display_name),
		"a forge with nobody involved named a pirate")
	assert_true(loose.contains("pirate"),
		"a forge previewed in the hold did not say a pirate is needed")
