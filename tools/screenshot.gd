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
##   --hold=<what>    press and hold a "card" or a "bench" slot, then photograph
##                    the inspector it opens
##   --rotate=<WxH>   resize again once the HUD is up, to prove it rebuilds
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
			target = _scene.bench._slots[0]
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
