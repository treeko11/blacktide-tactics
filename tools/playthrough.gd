extends "res://tools/tool_script.gd"

## Plays a whole run through the real round loop and fails on a stall.
##
##   godot --headless --path . --script res://tools/playthrough.gd
##
## This is the cross-system net. The unit tests each check one rule; this checks
## that the rules still compose — that a shop keeps offering cards, that bots
## keep levelling and fighting, that items keep arriving and getting equipped,
## and that somebody eventually wins.
##
## It plays badly on purpose. The point is that a run *completes*, not that it is
## won: a naive player who buys the cheapest thing available and never
## repositions is the shape most likely to expose a dead end.
##
## Arguments after `--`:
##   --runs=<n>      how many games to play (default 1)
##   --verbose       print a line per round

const MAX_FRAMES := 40000

var _rounds := 0
var _items_seen := 0
var _forges_seen := 0
var _verbose := false


func setup() -> void:
	_verbose = has_flag("verbose")


func run() -> void:
	manual_quit = true
	var runs := int(arg("runs", "1"))
	for i in runs:
		await _play_one(i + 1)
	finish()


func _play_one(index: int) -> void:
	var game := state()
	game.instant = true
	game.start_game()
	# After start_game, which resets it. Fights are stepped as fast as the tick cap
	# allows: at 1x a single 42-second battle takes two and a half thousand frames.
	game.speed = 64

	_rounds = 0
	_items_seen = 0
	_forges_seen = 0
	events().item_gained.connect(func(_id, _source): _items_seen += 1)
	events().item_forged.connect(func(_id, _uid): _forges_seen += 1)

	rule("Run %d" % index)

	var frames := 0
	while frames < MAX_FRAMES:
		frames += 1
		await process_frame

		match game.phase:
			game.Phase.PLAN:
				_take_a_turn(game)
				game.start_combat_now()
			game.Phase.ARMOURY:
				if not game.armoury_offer.is_empty():
					game.take_armoury_item(game.armoury_offer[0])
			game.Phase.OVER:
				_report(game, frames)
				_disconnect()
				return
			_:
				pass

	fail("the run never finished — stalled after %d frames at stage %d round %d"
		% [MAX_FRAMES, game.stage, game.round_number])
	_disconnect()


func _disconnect() -> void:
	for connection in events().item_gained.get_connections():
		events().item_gained.disconnect(connection["callable"])
	for connection in events().item_forged.get_connections():
		events().item_forged.disconnect(connection["callable"])


## A deliberately unsophisticated player: buy anything affordable, field
## everything that fits, put every item on the first pirate that will take it.
func _take_a_turn(game: Node) -> void:
	_rounds += 1

	for i in game.shop.size():
		game.buy(i)

	if game.player.gold > 20:
		game.buy_xp()

	_fill_the_board(game)
	_equip_everything(game)

	if _verbose:
		print("  %d-%d  lv%d  %dg  %d hull  board %d"
			% [game.stage, game.round_number, game.player.level, game.player.gold,
				game.player.hp, game.board.size()])


func _fill_the_board(game: Node) -> void:
	var seats: Array[Vector2i] = []
	for row in [5, 4, 6, 7]:
		for col in range(Hex.COLS):
			seats.append(Vector2i(col, row))

	for slot in range(game.bench.size()):
		if game.board.size() >= game.player.board_capacity():
			return
		var unit = game.bench[slot]
		if unit == null:
			continue
		for cell in seats:
			if game.unit_at(cell) == null:
				game.move_to_board(unit, cell)
				break


func _equip_everything(game: Node) -> void:
	for item_id in game.player.items.duplicate():
		for unit in game.board:
			if game.equip_item(item_id, unit):
				break


func _report(game: Node, frames: int) -> void:
	var place: int = game.player.place
	print("  finished %s of 8 at stage %d, round %d"
		% [game.ordinal(place), game.stage, game.round_number])
	print("  %d rounds played, %d frames" % [_rounds, frames])
	print("  level %d, %d hull left" % [game.player.level, maxi(0, game.player.hp)])
	print("  %d items collected, %d forged" % [_items_seen, _forges_seen])

	var bot_items := 0
	var bot_levels := 0
	for bot in game.bots:
		bot_levels += bot.level
		for unit in bot.units:
			bot_items += unit.items.size()
	print("  rivals: %d items equipped, average level %.1f"
		% [bot_items, float(bot_levels) / maxf(1.0, game.bots.size())])

	# Things that would mean the run "finished" without actually working.
	if _rounds < 5:
		fail("the run ended after only %d rounds" % _rounds)
	if _items_seen == 0:
		fail("no items were ever collected")
	if bot_items == 0:
		fail("no rival ever equipped an item")
