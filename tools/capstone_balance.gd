extends "res://tools/tool_script.gd"

## What a greater item is actually worth, measured rather than asserted.
##
##   godot --headless --path . --script res://tools/capstone_balance.gd
##
## Two questions, and they are different questions:
##
## **Is it greater than the sum of its parts?** A capstone fights the two
## finished items it is forged from, on the same pirate, same seed. Identical
## material — the only difference is that the capstone spends one slot where the
## pair spends two, so anything at or above 50% here is the item earning its
## name. Below 50% is a trap: the player has spent two items and a forge to end
## up weaker than before they combined.
##
## **Is the second one worth the slot it shuts?** Two capstones fight one
## capstone and the two finished items the second one would have been made from.
## Four finished items on both sides — the same material, spent two different
## ways — which is the decision the slot rule actually creates. Two capstones
## against three finished items is the wrong question: that is four items of
## investment against three, and a build that spent more ought to win.
##
## Near 50% is the rule working, because it means the player is choosing between
## two real builds rather than following the only good one.
##
## **Read the margin, not the win rate.** Both boards here are identical apart
## from the loadout, so a small persistent edge decides every seed the same way:
## a capstone one percent stronger than its parents reports 100%, and one that is
## twice as strong reports 100% as well. The win rate says *which* is stronger
## and nothing about by how much. The margin — how much of a board the winner has
## left, as a share, pooled over both sides — is the figure that still moves once
## the win rate has pinned, and it is the one to tune against.
##
## Arguments after `--`:
##   --fights=<n>    seeds per pairing (default 40)
##   --verbose       one line per capstone rather than a table

const SEATS := [
	Vector2i(3, 5), Vector2i(2, 6), Vector2i(4, 6),
	Vector2i(1, 5), Vector2i(5, 5), Vector2i(3, 6),
]

## A mixed board, so a capstone is judged beside a fleet rather than in a duel:
## a pure attack-damage carry with nothing in front of it dies before its item
## means anything, which reports the formation and not the item.
const CREW := ["barnaby", "lyra", "coral", "grimscale", "vance", "selka"]

var _fights := 40
var _verbose := false


func setup() -> void:
	_fights = int(arg("fights", "40"))
	_verbose = has_flag("verbose")


func run() -> void:
	rule("Control")
	_control()

	rule("Greater than the sum of its parts?")
	print("  A pirate carrying the capstone, against the same pirate carrying")
	print("  the two finished items it is forged from. Same material, one fewer")
	print("  slot spent. Under 50%% is a trap.")
	print("")
	_sum_of_parts()

	rule("Is the second one worth the slot it shuts?")
	print("  Two capstones against one capstone and the two finished items the")
	print("  other would have been forged from. Four items either way, so this is")
	print("  a question about shape and not about investment. Near 50%% is the")
	print("  rule working: two real builds rather than one.")
	print("")
	_two_against_three()

	finish()


# -----------------------------------------------------------------------------

## The same loadout on both sides, which must land near 50%.
##
## Without this every figure below is unreadable: a sim with any first-strike
## advantage would report one, and a reader would take it for the item. Two
## controls, because an empty board and a kitted one are different fights and
## only one of them resembles what the comparisons actually run.
func _control() -> void:
	var bare: Array[StringName] = []
	var kitted: Array[StringName] = [&"bloodletter", &"hull_of_the_deep"]
	var ra := _one_sided(bare, bare)
	var rb := _one_sided(kitted, kitted)
	var a := _decisive(ra)
	var b := _decisive(rb)
	print("  identical bare boards:   %.1f%% of decided fights  (%d drawn of %d)"
		% [a, ra["draw"], _fights])
	print("  identical kitted boards: %.1f%% of decided fights  (%d drawn of %d)"
		% [b, rb["draw"], _fights])
	if absf(a - 50.0) > 15.0 or absf(b - 50.0) > 15.0:
		print("")
		print("  The two halves are not even, and this is the near side's share of")
		print("  a board fighting a copy of itself. Hex.mirror flips the row, so a")
		print("  formation crosses to the other parity of the offset grid and does")
		print("  not keep its adjacencies. Everything below plays each seed both")
		print("  ways and pools the results, which cancels it.")


func _sum_of_parts() -> void:
	var worst := 100.0
	var worst_id := &""
	var total := 0.0
	var count := 0

	for item in content().capstones():
		var parts: Array[StringName] = []
		for part in item.recipe:
			parts.append(part)
		var one: Array[StringName] = [item.id]
		var r := _match(one, parts)
		var pct := _decisive(r)
		var margin: float = r["margin"]
		total += pct
		count += 1
		if pct < worst:
			worst = pct
			worst_id = item.id
		if _verbose:
			print("  %-22s %5.1f%%   margin %+.3f" % [item.id, pct, margin])
		elif pct < 50.0:
			print("  %-22s %5.1f%%   margin %+.3f   below its own parts"
				% [item.id, pct, margin])

	print("")
	print("  mean %.1f%% over %d greater items, worst %s at %.1f%%"
		% [total / maxf(count, 1.0), count, worst_id, worst])
	if worst < 50.0:
		print("  ^ that one is weaker than the two items it is forged from.")


func _two_against_three() -> void:
	var caps: Array = content().capstones()
	var total := 0.0
	var margin_total := 0.0
	var rounds := 0
	var widest := 0.0
	var widest_pair := ""

	for i in caps.size():
		var keep: ItemDef = caps[i]
		var second: ItemDef = caps[(i + 1) % caps.size()]
		# Both sides hold `keep` and the material for `second`. One side forged it.
		var committed: Array[StringName] = [keep.id, second.id]
		var spread: Array[StringName] = [keep.id, second.recipe[0], second.recipe[1]]
		var r := _match(committed, spread)
		var pct := _decisive(r)
		var margin: float = r["margin"]
		margin_total += margin
		total += pct
		rounds += 1
		var off := absf(pct - 50.0)
		if off > widest:
			widest = off
			widest_pair = "%s + %s" % [keep.id, second.id]
		if _verbose:
			print("  %-22s + %-22s %5.1f%%   margin %+.3f"
				% [keep.id, second.id, pct, margin])

	print("")
	print("  committing to the second greater item wins %.1f%% of the time,"
		% (total / maxf(rounds, 1.0)))
	print("  and finishes %+.3f of a board ahead on health"
		% (margin_total / maxf(rounds, 1.0)))
	print("  furthest from even: %s at %.1f points off"
		% [widest_pair, widest])


## Fights `mine` against `theirs`, each seed played twice with the sides swapped.
##
## The swap is not tidiness, it is the whole measurement. `Hex.mirror` flips the
## row as well as the column, so a formation on row 5 lands on row 2 — the other
## parity of an offset grid, where the neighbours are not the same neighbours.
## The two halves are therefore not adjacency-identical, and an identical board
## fought against itself wins only 7.5% of the time from the near side once the
## loadout is heavy enough to care where it is standing. Every figure this tool
## printed before the control went in was measuring that and not the item.
##
## Playing each seed both ways and pooling the results cancels it exactly,
## whatever its size, which is why the comparisons use this and the control
## deliberately does not.
func _match(mine: Array[StringName], theirs: Array[StringName]) -> Dictionary:
	var near := _one_sided(mine, theirs)
	var far := _one_sided(theirs, mine)
	return {
		"win": int(near["win"]) + int(far["loss"]),
		"loss": int(near["loss"]) + int(far["win"]),
		"draw": int(near["draw"]) + int(far["draw"]),
		"margin": (float(near["margin"]) - float(far["margin"])) * 0.5,
	}


## One side of that, for the control — which has to see the bias, not hide it.
func _one_sided(mine: Array[StringName], theirs: Array[StringName]) -> Dictionary:
	var out := { "win": 0, "draw": 0, "loss": 0, "margin": 0.0 }
	for s in _fights:
		var sim := Sim.new(content(), _board(mine), _board(theirs), false, 1000 + s)
		var guard := 0
		while not sim.done and guard < 2000:
			sim.step()
			guard += 1
		match sim.winner:
			Sim.Result.PLAYER_WIN: out["win"] += 1
			Sim.Result.ENEMY_WIN: out["loss"] += 1
			_: out["draw"] += 1
		out["margin"] += _health_share(sim, 0) - _health_share(sim, 1)
		sim.dispose()
	out["margin"] /= maxf(_fights, 1.0)
	return out


## What a team had left, as a share of what it started with.
func _health_share(sim: Sim, team: int) -> float:
	var left := 0.0
	var full := 0.0
	for u in sim.teams[team]:
		full += u.max_hp
		if u.alive:
			left += maxf(u.hp, 0.0)
	return left / maxf(full, 1.0)


## Wins as a share of the fights that produced a winner.
##
## Draws have to come out of the denominator, not be counted as half a loss. Two
## identical boards fight to a genuine draw most of the time — the sim is
## deterministic and the formation is a mirror — so a raw win rate reads as a
## catastrophic disadvantage for whichever side is being measured, which is
## exactly what the first version of this tool reported about four items that
## turned out to be fine.
func _decisive(r: Dictionary) -> float:
	var played: int = int(r["win"]) + int(r["loss"])
	if played == 0:
		return 50.0
	return 100.0 * float(r["win"]) / played


func _board(items: Array[StringName]) -> Array:
	var out: Array = []
	for i in CREW.size():
		out.append({
			"champion": content().champion(StringName(CREW[i])),
			"star": 2,
			"items": items.duplicate() if i == 0 else [],
			"cell": SEATS[i],
		})
	return out
