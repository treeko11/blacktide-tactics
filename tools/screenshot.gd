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
##   --stars=<n>      what star the fielded crew is (default 2)
##   --shop=<ids>     comma-separated champion ids to seat in the shop

var _out := "user://shot.png"
var _scene: Node = null


func setup() -> void:
	_out = arg("out", _out)
	startup_frames = int(arg("frames", "40"))

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

	var counter := arg("shop")
	if counter != "":
		_stock_shop(game, counter.split(","))

	if arg("modal") != "":
		await _open_modal(arg("modal"), game)
		await _frames(3)
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


## Seats named champions in the shop, so a shot can show a card against a known
## fleet rather than whatever the roll happened to offer.
func _stock_shop(game: Node, ids: PackedStringArray) -> void:
	for i in game.shop.size():
		game.shop[i] = &"" if i >= ids.size() else StringName(ids[i].strip_edges())
	events().shop_rolled.emit(game.shop.duplicate())


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
		_:
			fail("unknown modal '%s'" % which)
