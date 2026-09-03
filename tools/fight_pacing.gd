extends "res://tools/tool_script.gd"

## Measures how long fights actually last, round by round.
##
##   godot --headless --path . --script res://tools/fight_pacing.gd -- --runs=20
##
## The pacing complaint is a number, so it needs measuring rather than watching:
## a stage-3 fight that ends in four seconds and a stage-1 fight that grinds to
## the time limit are the same bug seen from both ends, and neither is visible
## in a win rate. This plays whole runs through the real round loop and reports
## the duration of every fight, grouped by stage.
##
## Arguments after `--`:
##   --runs=<n>     how many games to play (default 10)
##   --rows         print one line per fight rather than a summary

const MAX_FRAMES := 40000

var _rows: Array[Dictionary] = []
var _per_fight := false


func setup() -> void:
	_per_fight = has_flag("rows")


func run() -> void:
	manual_quit = true
	if has_flag("matched"):
		matched()
		finish()
		return
	if has_flag("isolate"):
		isolate()
		finish()
		return
	if has_flag("blowouts"):
		blowouts()
		finish()
		return
	var runs := int(arg("runs", "10"))
	for i in runs:
		await _play_one()
	_report()
	finish()


func _play_one() -> void:
	var game := state()
	game.instant = true
	game.start_game()
	game.speed = 64

	var handler := func(_won: bool, _damage: int, _opponent: String) -> void:
		var sim = game.sim
		if sim == null:
			return
		_rows.append({
			"stage": game.stage,
			"round": game.round_number,
			"kind": game.round_type(),
			"time": sim.time,
			"limit": sim.time >= Sim.TIME_LIMIT - 0.05,
			"alive": sim.survivors(Sim.Team.PLAYER).size()
				+ sim.survivors(Sim.Team.ENEMY).size(),
			"units": game.board.size(),
		})
	events().round_resolved.connect(handler)

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
				break
			_:
				pass

	events().round_resolved.disconnect(handler)


func _take_a_turn(game: Node) -> void:
	for i in game.shop.size():
		game.buy(i)
	if game.player.gold > 20:
		game.buy_xp()
	_fill_the_board(game)
	for item_id in game.player.items.duplicate():
		for unit in game.board:
			if game.equip_item(item_id, unit):
				break


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


func _report() -> void:
	if _per_fight:
		for r in _rows:
			print("  %d-%d %-8s %6.2fs  board %d  survivors %d%s"
				% [r["stage"], r["round"], r["kind"], r["time"], r["units"],
					r["alive"], "  TIMEOUT" if r["limit"] else ""])

	rule("Fight length by stage")
	print("  stage   fights    mean     min     max   >30s   <8s")
	var by_stage: Dictionary = {}
	for r in _rows:
		var s: int = r["stage"]
		if not by_stage.has(s):
			by_stage[s] = []
		by_stage[s].append(r)

	var stages: Array = by_stage.keys()
	stages.sort()
	for s in stages:
		var group: Array = by_stage[s]
		var total := 0.0
		var lo := 999.0
		var hi := 0.0
		var slow := 0
		var quick := 0
		for r in group:
			var t: float = r["time"]
			total += t
			lo = minf(lo, t)
			hi = maxf(hi, t)
			if t > 30.0:
				slow += 1
			if t < 8.0:
				quick += 1
		print("  %5d %8d %7.2f %7.2f %7.2f %6d %5d"
			% [s, group.size(), total / group.size(), lo, hi, slow, quick])

	rule("Fight length by round")
	var by_round: Dictionary = {}
	for r in _rows:
		var key: String = "%d-%d" % [r["stage"], r["round"]]
		if not by_round.has(key):
			by_round[key] = []
		by_round[key].append(r)
	var keys: Array = by_round.keys()
	keys.sort()
	for key in keys:
		var group: Array = by_round[key]
		var total := 0.0
		var timeouts := 0
		for r in group:
			total += r["time"]
			if r["limit"]:
				timeouts += 1
		print("  %-6s %3d fights  mean %6.2fs  %s"
			% [key, group.size(), total / group.size(),
				"%d hit the limit" % timeouts if timeouts > 0 else ""])


# --- The matched-fight experiment ---------------------------------------------
#
# The run report above cannot tell a blowout from a bad curve: a four-second
# fight where one board is twice the other *should* be four seconds. So this
# builds both sides from the same distribution — same unit count, same stars,
# same item budget — and reports how long an *even* fight of that power level
# takes. A curve problem shows up here as a mean that falls as power rises.

## Stars are dealt by cost, the way a run actually gets them — a 3-star 1-cost
## is a common sight and a 3-star legendary is nine copies of a card that rolls
## at 2%. Drawing every unit at the tier's star made the late tiers a parade of
## 3-star Krakens and measured a board nobody will ever field.
const TIERS := [
	{ "name": "1-1  2 units",   "units": 2, "cap": 2, "star": 1, "items": 0 },
	{ "name": "1-3  3 units",   "units": 3, "cap": 2, "star": 1, "items": 0 },
	{ "name": "2-x  5 units",   "units": 5, "cap": 3, "star": 1, "items": 1 },
	{ "name": "3-x  6 units",   "units": 6, "cap": 4, "star": 2, "items": 3 },
	{ "name": "4-x  7 units",   "units": 7, "cap": 5, "star": 2, "items": 5 },
	{ "name": "5-x  8 units",   "units": 8, "cap": 5, "star": 2, "items": 7 },
	{ "name": "6-x  9 units",   "units": 9, "cap": 5, "star": 3, "items": 9 },
	{ "name": "7-x  9 units",   "units": 9, "cap": 5, "star": 3, "items": 9 },
]

const SEATS: Array[Vector2i] = [
	Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
	Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6),
	Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7),
]


func matched() -> void:
	var samples := int(arg("samples", "150"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903

	var pool: Array[ChampionDef] = []
	for c in content().champions():
		if c.cost > 0:
			pool.append(c)
	var components: Array[ItemDef] = content().components()

	rule("Even fights, both boards built the same way (%d each)" % samples)
	print("  tier              mean     min     max   >30s    <8s  timeouts   sustain")

	for tier in TIERS:
		var times: Array[float] = []
		var timeouts := 0
		var healed_time := 0.0
		var healed_n := 0
		var dry_time := 0.0
		var dry_n := 0
		for i in samples:
			var a := _build_board(tier, pool, components, rng)
			var b := _build_board(tier, pool, components, rng)
			var sim := Sim.new(content(), a, b, false, rng.randi())
			sim.run_to_end()
			times.append(sim.time)
			if sim.time >= Sim.TIME_LIMIT - 0.05:
				timeouts += 1
			# Does either board bring a healer or a shielder? The complaint names
			# them specifically, so the two populations are reported apart.
			if _has_sustain(a) or _has_sustain(b):
				healed_time += sim.time
				healed_n += 1
			else:
				dry_time += sim.time
				dry_n += 1
			sim.dispose()

		var total := 0.0
		var lo := 999.0
		var hi := 0.0
		var slow := 0
		var quick := 0
		for t in times:
			total += t
			lo = minf(lo, t)
			hi = maxf(hi, t)
			if t > 30.0:
				slow += 1
			if t < 8.0:
				quick += 1
		var sustain_note := "-"
		if healed_n > 0 and dry_n > 0:
			sustain_note = "%.1fs vs %.1fs" % [healed_time / healed_n, dry_time / dry_n]
		print("  %-14s %7.2f %7.2f %7.2f %6d %6d %9d   %s"
			% [tier["name"], total / times.size(), lo, hi, slow, quick, timeouts,
				sustain_note])


func _build_board(tier: Dictionary, pool: Array[ChampionDef],
		components: Array[ItemDef], rng: RandomNumberGenerator) -> Array:
	var board: Array = []
	var picked: Dictionary = {}
	var count: int = tier["units"]
	var items_left: int = tier["items"]
	var cap: int = tier.get("cap", 5)

	for i in count:
		var def: ChampionDef = null
		var tries := 0
		while def == null or picked.has(def.id):
			def = pool[rng.randi_range(0, pool.size() - 1)]
			tries += 1
			# Early boards cannot roll legendaries at all, so the tier caps cost.
			if def != null and def.cost > cap and tries < 200:
				def = null
		picked[def.id] = true

		# A tier's star is what its *cheap* units have reached. A 3-cost trails it
		# by one and a legendary is almost always still at one copy.
		var star: int = tier["star"]
		if def.cost >= 4:
			star = 1
		elif def.cost == 3:
			star = maxi(1, star - 1)
		star = maxi(1, star)

		var items: Array[StringName] = []
		while items_left > 0 and items.size() < 3:
			items.append(components[rng.randi_range(0, components.size() - 1)].id)
			items_left -= 1
			if rng.randf() < 0.5:
				break

		board.append({
			"champion": def, "star": star, "items": items, "cell": SEATS[i],
		})
	return board


## Champions whose ability heals or shields. Named here rather than derived,
## because what matters is which of them a *board* brought, and the ability
## scripts are the only place that knows — reading them at runtime would mean
## naming forty-four classes in a tool.
const SUSTAIN := [
	&"barnacleking", &"brine", &"calypso", &"coral", &"grull", &"hookjaw",
	&"kelpar", &"meredine", &"nerida", &"selka", &"thalassa",
]


func _has_sustain(board: Array) -> bool:
	for entry in board:
		var def: ChampionDef = entry["champion"]
		if def != null and SUSTAIN.has(def.id):
			return true
	return false


## Which of the three things a run accumulates actually shortens a fight.
##
## The tiers above move unit count, stars and items together, because that is
## how a run moves them — but that cannot say which one is responsible. Each
## sweep here moves one and holds the other two, so the answer is readable off
## the column that changes.
func isolate() -> void:
	var samples := int(arg("samples", "200"))
	var pool: Array[ChampionDef] = []
	for c in content().champions():
		if c.cost > 0 and c.cost <= 3:
			pool.append(c)
	var components: Array[ItemDef] = content().components()

	rule("One variable at a time, both boards identical in budget")

	print("  board size (1-star, no items)")
	for n in [2, 3, 4, 6, 8, 9]:
		_sweep("%d units" % n, { "units": n, "cap": 3, "star": 1, "items": 0 },
			pool, components, samples)

	print("")
	print("  stars (6 units, no items)")
	for star in [1, 2, 3]:
		_sweep("%d-star" % star, { "units": 6, "cap": 3, "star": star, "items": 0 },
			pool, components, samples)

	print("")
	print("  items (6 units, 1-star)")
	for k in [0, 3, 6, 12, 18]:
		_sweep("%d components" % k, { "units": 6, "cap": 3, "star": 1, "items": k },
			pool, components, samples)


func _sweep(label: String, tier: Dictionary, pool: Array[ChampionDef],
		components: Array[ItemDef], samples: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903

	var total := 0.0
	var lo := 999.0
	var timeouts := 0
	var quick := 0
	for i in samples:
		var a := _build_board(tier, pool, components, rng)
		var b := _build_board(tier, pool, components, rng)
		var sim := Sim.new(content(), a, b, false, rng.randi())
		sim.run_to_end()
		total += sim.time
		lo = minf(lo, sim.time)
		if sim.time >= Sim.TIME_LIMIT - 0.05:
			timeouts += 1
		if sim.time < 8.0:
			quick += 1
		sim.dispose()

	print("    %-14s mean %6.2fs   min %6.2fs   under 8s %3d/%d   timeouts %3d"
		% [label, total / samples, lo, quick, samples, timeouts])


## What the quickest fights actually look like from the inside.
##
## A four-second fight is only a problem if it was a fair one. If the losing
## board never got a cast off and never landed a meaningful share of the damage,
## the fight was decided in the shop and the sim is reporting that honestly; if
## both sides traded and it still ended in four seconds, the numbers are wrong.
func blowouts() -> void:
	var samples := int(arg("samples", "400"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260903

	var pool: Array[ChampionDef] = []
	for c in content().champions():
		if c.cost > 0 and c.cost <= 5:
			pool.append(c)
	var components: Array[ItemDef] = content().components()
	var tier := { "units": 9, "cap": 5, "star": 2, "items": 9 }

	var quick: Array[Dictionary] = []
	var normal: Array[Dictionary] = []

	for i in samples:
		var a := _build_board(tier, pool, components, rng)
		var b := _build_board(tier, pool, components, rng)
		var sim := Sim.new(content(), a, b, false, rng.randi())
		sim.run_to_end()

		var winners := Sim.Team.PLAYER if sim.winner == Sim.Result.PLAYER_WIN else Sim.Team.ENEMY
		var losers := 1 - winners
		var win_dealt := 0.0
		var lose_dealt := 0.0
		for u in sim.teams[winners]:
			win_dealt += u.damage_dealt
		for u in sim.teams[losers]:
			lose_dealt += u.damage_dealt
		var row := {
			"time": sim.time,
			"survivors": sim.survivors(winners).size(),
			"share": lose_dealt / maxf(1.0, win_dealt + lose_dealt),
		}
		if sim.time < 8.0:
			quick.append(row)
		elif sim.time < 30.0:
			normal.append(row)
		sim.dispose()

	rule("Fights under 8 seconds, against ordinary ones")
	_summarise("under 8s", quick, tier["units"])
	_summarise("8-30s", normal, tier["units"])


func _summarise(label: String, rows: Array[Dictionary], board: int) -> void:
	if rows.is_empty():
		print("  %-10s none" % label)
		return
	var t := 0.0
	var surv := 0.0
	var share := 0.0
	for r in rows:
		t += r["time"]
		surv += r["survivors"]
		share += r["share"]
	var n := float(rows.size())
	print("  %-10s %3d fights   mean %5.2fs   winner kept %.1f of %d   loser dealt %.0f%% of the damage"
		% [label, rows.size(), t / n, surv / n, board, 100.0 * share / n])
