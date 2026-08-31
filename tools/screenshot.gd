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
	for i in mini(ids.size(), seats.size()):
		var champion = content().champion(StringName(ids[i].strip_edges()))
		if champion == null:
			continue
		var unit := RosterUnit.new(champion, 2)
		unit.cell = seats[i]
		game.board.append(unit)
	events().board_changed.emit()


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
