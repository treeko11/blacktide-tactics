extends "res://tools/tool_script.gd"

## Measures how often a fleet beats each monster wave.
##
##   godot --headless --path . --script res://tools/creep_balance.gd -- --runs=8
##
## Monster rounds are meant to be a floor, not a wall: a player who fields
## anything at all should win. Nothing was measuring that, so the waves were
## tuned by eye. This plays real runs and records every fight against a wave —
## the player's and all seven bots' — bucketed by stage and round.
##
## Bots are the yardstick. They cannot read a shop or plan a comp, so they are a
## deliberately pessimistic stand-in for a player: whatever a bot wins, an
## attentive player wins by more.
##
## Arguments after `--`:
##   --runs=<n>    how many games to play (default 6)

const MAX_FRAMES := 40000

## stage:round -> { "wins": n, "fights": n, "hp_left": float }
var _tally: Dictionary = {}
var _empty_boards := 0


func run() -> void:
	manual_quit = true
	var runs := int(arg("runs", "6"))
	for i in runs:
		await _play_one(i)
	_report()
	finish()


func _play_one(seed_index: int) -> void:
	var game := state()
	game.instant = true
	game.start_game()
	game.rng.seed = 9000 + seed_index * 977
	game.speed = 64

	var frames := 0
	while frames < MAX_FRAMES:
		frames += 1
		await process_frame
		match game.phase:
			game.Phase.PLAN:
				_take_a_turn(game)
				if game.round_type() == &"pve":
					_measure(game)
				game.start_combat_now()
			game.Phase.ARMOURY:
				if not game.armoury_offer.is_empty():
					game.take_armoury_item(game.armoury_offer[0])
			game.Phase.OVER:
				return
			_:
				pass


## Fight this round's wave with every fleet still afloat and record the results.
func _measure(game: Node) -> void:
	var key := "%d-%d" % [game.stage, game.round_number]
	if not _tally.has(key):
		_tally[key] = { "wins": 0, "fights": 0, "hp_left": 0.0, "units": 0,
			"player_wins": 0, "player_fights": 0 }
	var row: Dictionary = _tally[key]

	var fleets: Array = []
	var mine: Array = []
	for u in game.board:
		mine.append(u.to_entry())
	fleets.append(mine)
	for b in game.bots:
		if b.alive:
			fleets.append(b.formation())

	for index in fleets.size():
		var fleet: Array = fleets[index]
		if fleet.is_empty():
			_empty_boards += 1
			continue
		var sim := Sim.new(content(), fleet, game.creep_wave(), false, game.rng.randi())
		sim.run_to_end()
		row["fights"] += 1
		row["units"] += fleet.size()
		if index == 0:
			row["player_fights"] += 1
		if sim.winner == Sim.Result.PLAYER_WIN:
			row["wins"] += 1
			if index == 0:
				row["player_wins"] += 1
			var total := 0.0
			var alive := 0.0
			for u in sim.survivors(Sim.Team.PLAYER):
				total += u.max_hp
				alive += u.hp
			row["hp_left"] += (alive / maxf(total, 1.0)) if total > 0.0 else 0.0
		sim.dispose()


func _report() -> void:
	rule("Monster waves")
	print("  round   fights   wins    rate    hp left   fleet   player")
	var keys := _tally.keys()
	keys.sort()
	for key in keys:
		var row: Dictionary = _tally[key]
		var fights: int = row["fights"]
		if fights == 0:
			continue
		var rate := 100.0 * float(row["wins"]) / float(fights)
		var hp: float = 100.0 * float(row["hp_left"]) / maxf(float(row["wins"]), 1.0)
		var units: float = float(row["units"]) / float(fights)
		print("  %-6s  %5d   %5d   %5.1f%%   %5.1f%%   %5.2f   %d/%d"
			% [key, fights, row["wins"], rate, hp, units,
				row["player_wins"], row["player_fights"]])
	print("")
	print("  %d fleets had nothing on the board and were skipped" % _empty_boards)


## A naive player: buy what is affordable, field everything, equip everything.
func _take_a_turn(game: Node) -> void:
	for i in game.shop.size():
		game.buy(i)
	if game.player.gold > 20:
		game.buy_xp()

	var seats: Array[Vector2i] = []
	for row in [5, 4, 6, 7]:
		for col in range(Hex.COLS):
			seats.append(Vector2i(col, row))
	for slot in range(game.bench.size()):
		if game.board.size() >= game.player.board_capacity():
			break
		var unit = game.bench[slot]
		if unit == null:
			continue
		for cell in seats:
			if game.unit_at(cell) == null:
				game.move_to_board(unit, cell)
				break

	for item_id in game.player.items.duplicate():
		for unit in game.board:
			if game.equip_item(item_id, unit):
				break
