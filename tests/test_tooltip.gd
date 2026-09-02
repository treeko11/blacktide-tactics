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


## An empty refresh means the subject is gone, and closes the inspector.
##
## This is the only way a *pinned* one on a touchscreen ever finds out: nothing
## un-hovers a finger, so a pirate that dies mid-fight, or is sold or merged
## between fights, would otherwise leave a panel describing something that is no
## longer on the board.
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
