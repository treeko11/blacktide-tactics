extends "res://tools/tool_script.gd"

## What the stacking grants are actually worth, and whether they plateau.
##
##   godot --headless --path . --script res://tools/stacking_balance.gd
##
## Four things in this game hand out a stat every time somebody casts: Siren's
## Locket, The Drowned Choir, Meredine's Hymn of the Deep and Empress Nautica's
## Flagship Broadside. Every one of them used to grant for the rest of combat,
## which made all four worth whatever the fight's length happened to be — and
## made them multiply each other, since two of them also hand back the mana that
## buys the next cast.
##
## That failure is invisible from inside a played round. The board simply wins,
## and nothing on screen says the ability is worth four times at second forty
## what it was worth at second ten. It is invisible to the test suite too: a
## grant that compounds applies exactly as cleanly as one that does not. So this
## measures it.
##
## **The reading is the ratio, not the total.** A short fight and a long one
## should bank roughly the same, because a stack that expires plateaus at about
## `amount per cast × stacks that fit inside the duration`. A LONG/SHORT ratio
## near 1 is a grant that has plateaued; one that climbs with the clock is a
## grant that is still unbounded, and the only difference from the old behaviour
## is how fast it runs away.
##
## The mirror is what makes a long fight available at all: a stacking fleet beats
## an ordinary one in about five seconds, which measures nothing. Fought against
## a copy of itself it runs to the bell, which is the case the grants break.
##
## Arguments after `--`:
##   --runs=<n>     seeds per row (default 20)

const SEATS := [
	Vector2i(3, 5), Vector2i(2, 6), Vector2i(4, 6),
	Vector2i(1, 5), Vector2i(5, 5), Vector2i(3, 6),
]

## Seat 0 carries the items and is the source under test. Seat 1 is the reader:
## it grants nothing itself, so everything banked on it arrived from elsewhere.
const ORDINARY := ["barnaby", "lyra", "kade", "grimscale", "dredge", "brine"]
const MEREDINE := ["meredine", "lyra", "kade", "grimscale", "dredge", "brine"]
const NAUTICA := ["nautica", "lyra", "kade", "grimscale", "dredge", "brine"]

## Both mana traits and both fleet-wide granters at once — the board the whole
## stack was reported from.
const STACKED := ["nautica", "coral", "meredine", "nerida", "vance", "voss"]

var _runs := 20


func setup() -> void:
	_runs = int(arg("runs", "20"))


func run() -> void:
	rule("Fleet-wide grants, banked on an ally that grants nothing")
	print("  Against an ordinary board, which ends quickly, and against a mirror,")
	print("  which runs to the bell. A grant that plateaus banks about the same")
	print("  either way; one still compounding climbs with the clock.")
	print("")
	_header()
	_row("meredine", MEREDINE)
	_row("nautica", NAUTICA)
	_row("both", STACKED)

	rule("The two growing items, on the carrier that holds them")
	print("  Same reading. The carrier's own ability power, so this is the item's")
	print("  growth and not the fleet's.")
	print("")
	_header()
	_row("locket on a caster", ORDINARY, [&"sirens_locket"], 0)
	_row("choir on a caster", ORDINARY, [&"drowned_choir"], 0)
	_row("locket on nautica", STACKED, [&"sirens_locket"], 0)
	_row("choir on nautica", STACKED, [&"drowned_choir"], 0)
	_row("choir+compass", STACKED, [&"drowned_choir", &"krakens_compass"], 0)
	_row("choir+locket", STACKED, [&"drowned_choir", &"sirens_locket"], 0)
	finish()


func _header() -> void:
	print("  %-20s %25s %25s %8s" % ["", "vs ordinary", "vs mirror", "long/"])
	print("  %-20s %8s %7s %7s %8s %7s %7s %8s"
		% ["row", "+AP", "+res", "secs", "+AP", "+res", "secs", "short"])


## `reader` is the seat whose banked stats are reported: 1 for a fleet-wide
## grant, 0 for an item whose growth lands on its own carrier.
func _row(label: String, crew: Array, items: Array = [], reader: int = 1) -> void:
	var typed: Array[StringName] = []
	for i in items:
		typed.append(i)
	var short := _measure(crew, typed, ORDINARY, reader)
	var long := _measure(crew, typed, crew, reader)
	# A Dictionary value is a Variant, so every one of these is typed on the way
	# out or the tool will not compile.
	var short_ap: float = short["ap"]
	var long_ap: float = long["ap"]
	var ratio := long_ap / maxf(short_ap, 0.001)
	print("  %-20s %8.1f %7.1f %7.1f %8.1f %7.1f %7.1f %8s"
		% [label, short_ap, short["res"], short["secs"],
			long_ap, long["res"], long["secs"],
			"-" if short_ap < 1.0 else "%.2fx" % ratio])


func _measure(crew: Array, items: Array[StringName], foe: Array,
		reader: int) -> Dictionary:
	var ap := 0.0
	var res := 0.0
	var secs := 0.0
	for s in _runs:
		var sim := Sim.new(content(), _board(crew, items),
			_board(foe, [] as Array[StringName]), false, 2000 + s)
		var u: SimUnit = sim.teams[0][reader]
		var base_ap: float = u.ability_power
		var base_res: float = u.armor
		var guard := 0
		while not sim.done and guard < 2000:
			sim.step()
			guard += 1
		# Read before dispose, and read the live value: a stack that has expired
		# has already been taken back off, which is the whole point.
		ap += u.ability_power - base_ap
		res += u.armor - base_res
		secs += guard / 30.0
		sim.dispose()
	return { "ap": ap / _runs, "res": res / _runs, "secs": secs / _runs }


func _board(crew: Array, items: Array[StringName]) -> Array:
	var out: Array = []
	for i in crew.size():
		out.append({
			"champion": content().champion(StringName(crew[i])),
			"star": 2,
			"items": items.duplicate() if i == 0 else [],
			"cell": SEATS[i],
		})
	return out
