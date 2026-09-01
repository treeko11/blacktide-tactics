extends "res://tools/tool_script.gd"

## Loads the game, lets it settle, and writes a PNG.
##
##   godot --path . --script res://tools/screenshot.gd -- --out=shot.png
##
## Must run *without* `--headless`: there is nothing to capture if nothing was
## rendered.
##
## Arguments after `--`:
##   --out=<path>     where to write (default user://shot.png)
##   --phase=combat   skip the planning phase and photograph a fight instead
##   --frames=<n>     how many frames to let pass first
##   --gold=<n>       start the player with this much gold
##   --units=<ids>    comma-separated champion ids to field, e.g. lyra,kraken
##   --bench=<ids>    comma-separated champion ids to sit on the bench
##   --stars=<n>      what star the fielded crew is (default 2)
##   --size=<WxH>     resize the window first, e.g. --size=390x844 for a phone
##   --hold=<what>    press and hold a "card", a "bench" slot or a forge "chart"
##                    square, then photograph the inspector it opens
##   --rotate=<WxH>   resize again once the HUD is up, to prove it rebuilds
##   --measure        print how tall each block of the HUD ended up
##   --sequence=forge replay the reported lock-up: read the forge chart, close
##                    it, then try to buy from the shop
##   --live           hover a pirate mid-fight and prove the inspector keeps up
##                    with it without the cursor moving again
##   --shop=<ids>     comma-separated champion ids to seat in the shop

var _out := "user://shot.png"
var _scene: Node = null


func setup() -> void:
	_out = arg("out", _out)
	startup_frames = int(arg("frames", "40"))

	# Before the scene exists, so the HUD is built in the layout it will be shot
	# in rather than built wide and then rebuilt.
	var wanted := arg("size")
	if wanted != "":
		var parts := wanted.split("x")
		if parts.size() == 2:
			root.size = Vector2i(int(parts[0]), int(parts[1]))

	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func run() -> void:
	var game := state()
	if game == null:
		fail("no GameState")
		return

	manual_quit = true
	_close_modals()

	if arg("speed") != "":
		game.speed = int(arg("speed"))
	if arg("gold") != "":
		game.player.gold = int(arg("gold"))

	var units := arg("units")
	if units != "":
		_field(game, units.split(","))

	var benched := arg("bench")
	if benched != "":
		_bench(game, benched.split(","))

	var counter := arg("shop")
	if counter != "":
		_stock_shop(game, counter.split(","))

	if arg("modal") != "":
		await _open_modal(arg("modal"), game)
		await _frames(3)
		_capture()
		finish()
		return

	if arg("sequence") != "":
		await _sequence(game, arg("sequence"))
		_capture()
		finish()
		return

	if has_flag("measure"):
		await _frames(6)
		_measure()
		_capture()
		finish()
		return

	if arg("rotate") != "":
		await _rotate(arg("rotate"))
		_capture()
		finish()
		return

	if arg("hold") != "":
		await _press_and_hold(game, arg("hold"))
		_capture()
		finish()
		return

	if has_flag("live"):
		await _watch_a_fight(game)
		finish()
		return

	if arg("phase") == "combat":
		await _run_a_fight(game)
	else:
		await _frames(3)      # let the board rebuild after fielding a crew
		_capture()
	finish()


## Fields a named crew, so a screenshot can show a real board rather than an
## empty one.
func _field(game: Node, ids: PackedStringArray) -> void:
	game.player.level = maxi(game.player.level, ids.size())
	var seats := [
		Vector2i(3, 5), Vector2i(2, 5), Vector2i(4, 5), Vector2i(1, 5),
		Vector2i(5, 5), Vector2i(3, 7), Vector2i(2, 7), Vector2i(4, 7),
	]
	var star := int(arg("stars", "2"))
	for i in mini(ids.size(), seats.size()):
		var champion = content().champion(StringName(ids[i].strip_edges()))
		if champion == null:
			continue
		var unit := RosterUnit.new(champion, star)
		unit.cell = seats[i]
		game.board.append(unit)
	events().board_changed.emit()


## Puts named champions on the bench, for shots and touch tests that need one.
func _bench(game: Node, ids: PackedStringArray) -> void:
	for i in mini(ids.size(), game.bench.size()):
		var champion = content().champion(StringName(ids[i].strip_edges()))
		if champion != null:
			game.bench[i] = RosterUnit.new(champion, int(arg("stars", "2")))
	events().board_changed.emit()


## Seats named champions in the shop, so a shot can show a card against a known
## fleet rather than whatever the roll happened to offer.
func _stock_shop(game: Node, ids: PackedStringArray) -> void:
	for i in game.shop.size():
		game.shop[i] = &"" if i >= ids.size() else StringName(ids[i].strip_edges())
	events().shop_rolled.emit(game.shop.duplicate())


# --- scripted touch ----------------------------------------------------------

## One finger down at a point, held for `seconds`, then lifted.
func _touch(at: Vector2, seconds: float = 0.05) -> void:
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = at
	Input.parse_input_event(down)
	await _frames(maxi(2, roundi(seconds * 60.0)))

	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = at
	Input.parse_input_event(up)
	await _frames(4)


func _centre_of(control: Control) -> Vector2:
	return control.global_position + control.size * 0.5


## Replays the sequence that left the shop unresponsive on a phone.
##
## The report was "I could not interact with the store after a round — I think it
## was after I opened the forge guide or looked at an item tooltip". Both of those
## leave state behind that the shop does not know about, so this walks the whole
## path with real touch events and then checks that a tap still buys a pirate.
func _sequence(game: Node, which: String) -> void:
	# Look at a card first, so the hover state the inspector reads is populated.
	await _touch(_centre_of(_scene.shop._cards[0]), 0.05)
	print("  after a plain tap on a card: gold %d" % game.player.gold)

	match which:
		"forge":
			_scene.modals.open_forge_chart()
			await _frames(8)
			# Rest a finger on the chart, the way anyone reading it would.
			await _touch(Vector2(Layout.css_size.x * 0.5, Layout.css_size.y * 0.4), 0.6)
			print("  while the chart is open: tooltip pinned=%s"
				% str(_scene.tooltip.pinned))
			_scene.modals.close()
			await _frames(8)
		"item":
			game.give_item(&"blade", &"salvage")
			await _frames(8)
			var chip: Control = _scene.hold._grid.get_child(0)
			await _touch(_centre_of(chip), 0.6)
			print("  after holding an item: tooltip pinned=%s" % str(_scene.tooltip.pinned))
			_scene.tooltip.hide_now()
			await _frames(4)
		_:
			fail("unknown sequence '%s'" % which)
			return

	print("  after closing: tooltip pinned=%s visible=%s"
		% [str(_scene.tooltip.pinned), str(_scene.tooltip.visible)])

	# Fund the rest of the run. What is under test here is whether a tap reaches
	# the control, and a player who cannot afford the thing they tapped answers a
	# different question: the opening tap on a card leaves 1 gold, which disables
	# the Roll button, and a disabled button not responding is correct behaviour
	# reported as a lock-up.
	game.player.gold = 50
	events().gold_changed.emit(game.player.gold, 0)
	await _frames(2)

	# Now the thing that was reported broken: buying from the shop. A card that
	# has already been bought is empty and buys nothing, so pick a full one.
	var gold_before: int = game.player.gold
	var bought := -1
	for attempt in 3:
		var target: Control = null
		for c in _scene.shop._cards:
			if c.champion != null:
				target = c
				break
		if target == null:
			fail("the shop is empty; nothing left to tap")
			return
		await _touch(_centre_of(target), 0.05)
		if game.player.gold != gold_before:
			bought = attempt + 1
			break

	# The same question for an ordinary Button, which is most of the HUD.
	var before_roll: int = game.player.gold
	var rolled := -1
	for attempt in 3:
		await _touch(_centre_of(_scene.shop._reroll_button), 0.05)
		if game.player.gold != before_roll:
			rolled = attempt + 1
			break
	if rolled < 0:
		fail("the Roll button never responded")
	elif rolled > 1:
		fail("the Roll button swallowed %d tap(s)" % (rolled - 1))
	else:
		print("  the first tap on Roll worked")

	if bought < 0:
		fail("the shop never responded: three taps after %s bought nothing" % which)
	elif bought > 1:
		fail("the shop swallowed %d tap(s) after %s before responding" % [bought - 1, which])
	else:
		print("  the first tap after %s bought a pirate" % which)


## Prints the height of every block of the HUD.
##
## The phone layout is a fight over vertical space and the board loses it by
## default: it is the one panel that takes what is left over. Numbers beat
## squinting at a screenshot when deciding which piece of furniture to cut.
func _measure() -> void:
	var total: float = Layout.css_size.y
	print("  viewport %d x %d (css)" % [Layout.css_size.x, total])
	var blocks := {
		"top bar": _scene.top_bar,
		"board": _scene.board,
		"traits": _scene.traits,
		"cargo hold": _scene.hold,
		"bench": _scene.bench,
		"shop": _scene.shop,
	}
	for name in blocks:
		var control: Control = blocks[name]
		if control == null:
			continue
		print("  %-12s %6.1f  (%4.1f%%)"
			% [name, control.size.y, 100.0 * control.size.y / maxf(total, 1.0)])
	print("  board scale %.3f -> %d x %d hexes drawn"
		% [_scene.board.board_scale,
			roundi(Hex.board_size().x * _scene.board.board_scale),
			roundi(Hex.board_size().y * _scene.board.board_scale)])


## Resizes a running HUD and checks it rebuilt into the other layout.
##
## A phone turning sideways is the one resize that matters, and it is a resize
## the *running* game has to notice — not one it is launched with.
func _rotate(spec: String) -> void:
	var parts := spec.split("x")
	if parts.size() != 2:
		fail("--rotate wants WxH")
		return

	var was_short := Layout.short()
	var was_compact := Layout.compact()
	var old_shop: Node = _scene.shop

	root.size = Vector2i(int(parts[0]), int(parts[1]))
	await _frames(12)

	print("  before: compact=%s short=%s" % [str(was_compact), str(was_short)])
	print("  after:  compact=%s short=%s" % [str(Layout.compact()), str(Layout.short())])
	if Layout.short() == was_short and Layout.compact() == was_compact:
		fail("the layout did not change; pick a size on the other side of a breakpoint")
	elif _scene.shop == old_shop:
		fail("the layout changed but the HUD was not rebuilt")


## Rests a finger on something and photographs what opens.
##
## Real `InputEventScreenTouch`, not a synthetic mouse click, because that is the
## distinction the press-and-hold code makes: a mouse held still is a slow click
## and must not open anything.
func _press_and_hold(game: Node, what: String) -> void:
	var target: Control = null
	match what:
		"card":
			target = _scene.shop._cards[0]
		"bench":
			# A slot with nobody in it reports no hover, so there is nothing for
			# the hold to pin and nothing for SELL to sell. Seat a pirate the way
			# "item" hands itself loot, unless --bench already put one there.
			if game.bench[0] == null:
				_bench(game, PackedStringArray([_a_champion(game)]))
				await _frames(4)
			target = _scene.bench._slots[0]
		"item":
			for id in [&"blade", &"plate"]:
				game.give_item(id, &"salvage")
			await _frames(6)
			target = _scene.hold._grid.get_child(0)
		"chart":
			_scene.modals.open_forge_chart()
			await _frames(10)
			# The grid is the first child of the dialog's content after the
			# heading and the subtitle; a forged cell is past the header row.
			for node in _scene.modals._content.get_children():
				if node is GridContainer:
					target = node.get_child(node.columns + 2)
					break
		_:
			fail("unknown hold target '%s'" % what)
			return

	var at := target.global_position + target.size * 0.5
	var gold_before: int = game.player.gold

	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = at
	Input.parse_input_event(down)

	# Long enough for Main's timer to elapse, with frames for the hover to land
	# and the inspector to lay itself out.
	await _frames(45)

	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = at
	Input.parse_input_event(up)
	await _frames(6)

	print("  inspector pinned: %s" % str(_scene.tooltip.pinned))
	print("  gold %d -> %d (a hold must not buy)" % [gold_before, game.player.gold])
	if not _scene.tooltip.pinned:
		fail("press and hold did not pin the inspector")
	if game.player.gold != gold_before:
		fail("press and hold bought the card it was meant to describe")

	if what == "bench":
		await _check_sell_button(game)


## Any champion, for a test that needs a body on the bench and does not care
## whose. The shop has already rolled, so its first card keeps this deterministic
## for a given seed rather than pinning the test to one hand-picked id.
func _a_champion(game: Node) -> String:
	for id in game.shop:
		if id != &"":
			return String(id)
	var all: Array = content().champions()
	return String(all[0].id)


## The SELL button is the only way to sell a pirate without a right mouse button,
## so it is worth proving it sells and not merely that it is drawn.
func _check_sell_button(game: Node) -> void:
	var benched: int = 0
	for u in game.bench:
		if u != null:
			benched += 1
	var gold_before: int = game.player.gold

	_scene.tooltip._sell_button.emit_signal("pressed")
	await _frames(4)

	var left: int = 0
	for u in game.bench:
		if u != null:
			left += 1
	print("  sold from the inspector: bench %d -> %d, gold %d -> %d"
		% [benched, left, gold_before, game.player.gold])
	if left != benched - 1:
		fail("the inspector's SELL button did not sell the pirate")
	if game.player.gold <= gold_before:
		fail("selling from the inspector paid nothing")
	if _scene.tooltip.visible:
		fail("the inspector stayed open after selling the pirate it described")


## Rests the cursor on a pirate mid-fight and checks the inspector keeps up.
##
## The board only reports a hover when the cursor *moves*, so a stat block read by
## holding still — which is how anyone reads one — used to be frozen at whatever
## was true when the cursor arrived. One motion event, then nothing: everything
## after this point has to come from the tooltip re-reading the unit itself.
##
## The damage is applied by hand rather than waited for. What is under test is
## whether a change in the unit reaches the panel, and letting the fight decide
## when someone gets hit makes that a coin toss on the frame count.
func _watch_a_fight(game: Node) -> void:
	game.start_combat_now()
	await _frames(20)

	var sim = game.sim
	if sim == null:
		fail("no fight to watch")
		return

	# Untyped on purpose: naming a class whose script mentions an autoload makes
	# this whole tool fail to compile. See tool_script.gd.
	var unit = null
	for u in sim.units:
		if u.team == 0 and u.alive:
			unit = u
			break
	if unit == null:
		fail("nobody of ours is in the fight — pass --units=")
		return

	var board = _scene.board
	var at: Vector2 = board.global_position + unit.pos * board.board_scale + board.board_offset
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	await _frames(4)

	if not _scene.tooltip.visible:
		fail("hovering a pirate mid-fight opened no inspector")
		return
	var before: String = _scene.tooltip._body.text

	# The cursor does not move again from here.
	unit.hp = maxf(1.0, unit.hp - 30.0)
	await _frames(20)
	var after: String = _scene.tooltip._body.text

	print("  health %d, inspector says %s" % [roundi(unit.hp), _line_with(after, "Health")])
	if after == before:
		fail("the inspector froze: it still reads %s" % _line_with(before, "Health"))
	_capture()

	# And it closes itself when the pirate it describes is killed, which on a
	# touchscreen is the only way a pinned one ever finds out.
	unit.alive = false
	await _frames(20)
	print("  after the pirate died: inspector visible=%s" % str(_scene.tooltip.visible))
	if _scene.tooltip.visible:
		fail("the inspector stayed open over a dead pirate")


func _line_with(text: String, needle: String) -> String:
	for line in text.split("\n"):
		if line.contains(needle):
			return line.strip_edges()
	return "(no %s line)" % needle


## Starts a battle and photographs it a couple of seconds in, when the effects
## layer is busy.
func _run_a_fight(game: Node) -> void:
	game.start_combat_now()
	await _frames(int(arg("combat_frames", "150")))
	_capture()


## The help dialog opens on the first run and would otherwise be in every shot.
func _close_modals() -> void:
	if _scene != null and _scene.get("modals") != null:
		_scene.modals.close()


## Fast-forwards the real round loop until the armoury opens itself.
func _play_to_the_armoury(game: Node) -> void:
	game.instant = true
	game.speed = 64
	for i in 3000:
		if game.phase == game.Phase.ARMOURY:
			return
		if game.phase == game.Phase.PLAN:
			game.start_combat_now()
		elif game.phase == game.Phase.OVER:
			break
		await process_frame
	fail("the run never reached an armoury")


func _frames(count: int) -> void:
	for i in count:
		await process_frame     # this script IS the SceneTree; the signal is ours


func _capture() -> void:
	var image := root.get_texture().get_image()
	var error := image.save_png(_out)
	if error != OK:
		fail("could not write %s (error %d)" % [_out, error])
	else:
		print("  wrote %s" % ProjectSettings.globalize_path(_out))


## Opens one of the dialogs directly, so a screenshot can prove it renders.
func _open_modal(which: String, game: Node) -> void:
	if _scene == null:
		return
	match which:
		"forge":
			# Hold a few components so the chart has something to mark as makeable.
			for id in [&"blade", &"plate", &"lens"]:
				game.give_item(id, &"salvage")
			_scene.modals.open_forge_chart()
		"armoury":
			# Played to, not injected. Handing the modal a made-up offer is how a
			# screenshot of a working armoury coexisted with an armoury that
			# opened empty in the actual game for a whole stage.
			await _play_to_the_armoury(game)
		"help":
			_scene.modals.open_help()
		"fleet":
			# The compact layout's bottom sheet. Nothing on a desktop.
			_scene._toggle_sheet(true)
		_:
			fail("unknown modal '%s'" % which)
