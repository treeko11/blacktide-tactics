extends "res://tools/tool_script.gd"

## Plays a long run with the real HUD up, watching for the two ways this game can
## lock a browser tab.
##
##   godot --path . --script res://tools/soak.gd -- --rounds=40
##
## Runs either way. Windowed is the real thing; `--headless` plays the same game
## with the same HUD built and is faster, which is what made bisecting the freeze
## below possible — it reproduced headless, which ruled out the renderer in one
## run.
##
## **It has already earned its keep twice.** It found the log panel's `while`
## loop over a deferred `queue_free()` — the freeze that locked the game a few
## rounds into every run — and it measured the round-end burst of six unwatched
## fights at a third of a second a frame by stage 5.
##
## `playthrough.gd` already plays whole runs, but it never builds a scene — it is
## a check on the round loop and the economy, and a fight it resolves is one
## nobody draws. That leaves the presentation layer, which is the half that runs
## every frame, untested over any length of time. A freeze that only shows up in
## late rounds is by definition something that accumulates, and nothing in this
## project was watching anything accumulate.
##
## Two failures, because a frozen tab is one of exactly two things:
##
##   a frame that never ends   one long loop, or a round's work that has grown
##                             until it no longer fits in a frame. Every frame is
##                             timed, and the worst one per round is reported.
##   memory that never stops   a leak. Live objects and orphaned nodes are
##                             sampled once a round; a run that ends with far
##                             more of either than it settled at is leaking, and
##                             in a browser that ends as a dead tab.
##
## Arguments after `--`:
##   --rounds=<n>   how many rounds to play (default 40)
##   --speed=<n>    the speed multiplier to fight at (default 4, the game's max)
##   --frame-ms=<n> the frame time to fail at (default 900)
##   --max-mb=<n>   bail the moment static memory passes this (default 1200)
##   --quiet        only print the summary and any failure

const SETTLE_ROUNDS := 4

var _scene: Node = null
var _rows: Array[Dictionary] = []


func setup() -> void:
	startup_frames = 20
	_scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(_scene)


func run() -> void:
	manual_quit = true
	var game := state()
	if game == null:
		fail("no GameState")
		finish()
		return

	var rounds := int(arg("rounds", "40"))
	var worst_allowed := float(arg("frame-ms", "900"))
	var ceiling := float(arg("max-mb", "1200")) * 1048576.0
	var quiet := has_flag("quiet")

	# The briefing is up and holding the clock; this is the player pressing on.
	if _scene.get("wiki") != null:
		_scene.wiki.close()
	game.begin_run()
	game.speed = int(arg("speed", "4"))

	rule("Soak: %d rounds at %dx" % [rounds, game.speed])

	var played := 0
	var last_round := -1
	var worst_ms := 0.0
	var worst_where := ""
	var frames := 0
	var previous_usec := Time.get_ticks_usec()

	while played < rounds and frames < rounds * 4000:
		frames += 1
		await process_frame

		# Measured around `await`, so this is the whole frame — the sim stepping,
		# the six fights a round end resolves, the HUD rebuilding, all of it.
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - previous_usec) / 1000.0
		previous_usec = now
		if frame_ms > worst_ms:
			worst_ms = frame_ms
			worst_where = _describe(game)

		# Checked every frame, not every round: a runaway allocation takes the
		# machine down long before the round it started in ends, and the round
		# summary that would have reported it never prints.
		if Performance.get_monitor(Performance.MEMORY_STATIC) > ceiling:
			fail("memory ran away at %s" % _describe(game))
			_dump(game)
			_report(worst_allowed)
			finish()
			return

		# Several effects size a loop from the distance they span — a harpoon's
		# rope pays out one link every 14 pixels, a chain one every 12 — so a
		# position that is nonsense is not a graphical glitch, it is a `for` loop
		# with a nonsense bound, running inside `_draw`. Caught here while the
		# numbers still exist to look at.
		var bad := _bad_geometry(game)
		if bad != "":
			fail("nonsense geometry at %s: %s" % [_describe(game), bad])
			_dump(game)
			_report(worst_allowed)
			finish()
			return

		match game.phase:
			game.Phase.PLAN:
				# Played naively but played properly. An empty board loses every
				# round, dies by stage 2 and never renders a real fight — and a
				# real fight, with items and star-ups and eighteen bodies on the
				# board, is the thing being soaked.
				_take_a_turn(game)
				game.start_combat_now()
			game.Phase.ARMOURY:
				if not game.armoury_offer.is_empty():
					game.take_armoury_item(game.armoury_offer[0])
			game.Phase.OVER:
				game.start_game()
				# The same two calls the restart button makes. `start_game` alone
				# leaves the board view still showing the fleet of the run that
				# just ended.
				if _scene.get("board") != null:
					_scene.board.show_roster(game.board)
				game.begin_run()
			_:
				pass

		# Typed, not inferred: `state()` hands back a `Node`, so everything read
		# off it is a Variant and `:=` cannot compile.
		var key: int = game.stage * 100 + game.round_number
		if key != last_round:
			if last_round >= 0:
				played += 1
				_sample(game, played, worst_ms, worst_where)
				if not quiet:
					_print_row(_rows[-1])
				worst_ms = 0.0
			last_round = key

	_report(worst_allowed)
	finish()


## Buys the whole shop, seats everyone, and hangs every item on somebody.
##
## The same naive turn `playthrough.gd` takes, and for the same reason: a soak is
## not a test of playing well, it is a test of the game surviving a real board.
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
		var unit: Object = game.bench[slot]
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


## The furthest-out position anywhere in the presentation layer, if it is absurd.
##
## The board is about 600 points across, so anything spanning thousands is not a
## long shot, it is a broken number — and the effects that draw a rope or a chain
## turn that straight into the number of segments they loop over.
func _bad_geometry(game: Node) -> String:
	if game.sim != null:
		for u in game.sim.units:
			var pos: Vector2 = u.pos
			if not (is_finite(pos.x) and is_finite(pos.y)):
				return "%s is standing at %s" % [u.display_name(), str(pos)]
			if absf(pos.x) > 4000.0 or absf(pos.y) > 4000.0:
				return "%s is standing at %s" % [u.display_name(), str(pos)]

	if _scene == null or _scene.get("board") == null:
		return ""
	var layer: Object = _scene.board.fx
	if layer == null:
		return ""
	for e in layer._effects:
		var at: Vector2 = e["at"]
		var from: Vector2 = e["from"]
		if not (is_finite(at.x) and is_finite(at.y) and is_finite(from.x) and is_finite(from.y)):
			return "a %s/%s effect runs from %s to %s" % [e["kind"], e["style"], str(from), str(at)]
		var span := from.distance_to(at)
		if span > 4000.0:
			return "a %s/%s effect spans %.0f px, from %s to %s — %d rope links" % [
				e["kind"], e["style"], span, str(from), str(at), int(span / 14.0)]
	return ""


## Everything worth knowing at the moment it went wrong.
##
## The point is to tell an Object leak from an Array one: `OBJECT_COUNT` climbing
## means something is allocating RefCounteds and never dropping them, while
## memory climbing with a flat object count means a Dictionary or an Array
## somewhere is being appended to forever. They have different culprits, and
## nothing else on screen tells them apart.
func _dump(game: Node) -> void:
	print("  at:       %s" % _describe(game))
	print("  objects:  %d   nodes %d   orphans %d   static %.1f MB" % [
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])

	var sim: Object = game.sim
	if sim == null:
		print("  no live sim")
	else:
		print("  sim:      %d units, %d queued effects, %d pending calls, %d timers, t=%.1fs, done=%s"
			% [sim.units.size(), sim.fx_queue.size(), sim._events.size(),
				sim._timers.size(), sim.time, str(sim.done)])
		var shields := 0
		var burns := 0
		var regens := 0
		var buffs := 0
		for u in sim.units:
			shields += u.shields.size()
			burns += u.burns.size()
			regens += u.regen_queue.size()
			buffs += u.buffs.size()
		print("  units:    %d shields, %d burns, %d regens, %d buffs across the board"
			% [shields, burns, regens, buffs])

	if _scene != null and _scene.get("board") != null and _scene.board.get("fx") != null:
		print("  fx layer: %d live effects" % _scene.board.fx._effects.size())
	print("  log:      %d lines" % game.log_lines.size())


## One row per round: what the engine is holding, and the worst frame in it.
func _sample(game: Node, index: int, worst_ms: float, worst_where: String) -> void:
	_rows.append({
		"round": "%d-%d" % [game.stage, game.round_number],
		"index": index,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"memory": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"worst_ms": worst_ms,
		"where": worst_where,
	})


func _print_row(row: Dictionary) -> void:
	print("  %-6s objects %-8d nodes %-6d orphans %-5d static %6.1f MB   worst frame %6.1f ms  (%s)"
		% [row["round"], row["objects"], row["nodes"], row["orphans"],
			float(row["memory"]) / 1048576.0, row["worst_ms"], row["where"]])


func _describe(game: Node) -> String:
	var names := ["planning", "combat", "aftermath", "armoury", "over"]
	var phase := "phase %d" % game.phase
	if game.phase >= 0 and game.phase < names.size():
		phase = names[game.phase]
	return "%d-%d %s" % [game.stage, game.round_number, phase]


func _report(worst_allowed: float) -> void:
	if _rows.size() < SETTLE_ROUNDS + 2:
		fail("only %d rounds played — the run ended before it could say anything"
			% _rows.size())
		return

	rule("Summary")

	# The worst frame anywhere. In a browser this is the whole tab stopping, and
	# past about a second Chrome starts offering to kill the page.
	var worst := _rows[0]
	for row in _rows:
		if row["worst_ms"] > worst["worst_ms"]:
			worst = row
	print("  worst frame: %.1f ms at %s" % [worst["worst_ms"], worst["where"]])
	if float(worst["worst_ms"]) > worst_allowed:
		fail("a frame took %.0f ms at %s — that is a locked tab, not a hitch"
			% [worst["worst_ms"], worst["where"]])

	# Growth is measured from a settled point, not from the first round: the
	# opening rounds are still building the HUD, loading streams and filling
	# caches, and all of that is a one-off rather than a leak.
	var settled: Dictionary = _rows[SETTLE_ROUNDS]
	var final: Dictionary = _rows[-1]
	var rounds_between: int = int(final["index"]) - int(settled["index"])

	for field in ["objects", "nodes", "memory"]:
		var start := int(settled[field])
		var end := int(final[field])
		var per_round := float(end - start) / maxf(1.0, float(rounds_between))
		print("  %-8s %d -> %d over %d rounds (%+.1f a round)"
			% [field, start, end, rounds_between, per_round])

	# An object count that climbs every round is the leak that ends a long web
	# session, and the sim is the thing that allocates in quantity — seven fights
	# a round, every one of them a web of RefCounted holding each other.
	var object_growth := int(final["objects"]) - int(settled["objects"])
	if object_growth > 200 * rounds_between:
		fail("objects grew by %d over %d rounds — something is not being disposed"
			% [object_growth, rounds_between])

	# Orphans are not a leak on their own: a panel that clears itself detaches its
	# old rows *now* and frees them at the end of the frame, so a sample taken
	# mid-rebuild legitimately counts dozens. What would be a leak is the number
	# climbing round on round, so that is what is asked.
	var orphan_growth := int(final["orphans"]) - int(settled["orphans"])
	if orphan_growth > 40 * rounds_between:
		fail("orphaned nodes grew by %d over %d rounds — something is detached and never freed"
			% [orphan_growth, rounds_between])

	if exit_code == 0:
		print("  clean")
