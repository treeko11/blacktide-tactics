extends SeaEffect

## A silver shoal. Baitfish boil up through the board in scattered patches, and
## a crew standing over one finds its ability comes sooner.
##
## The doldrums read backwards: mana, the one lever nothing else in the weather
## touches, handed out instead of taken away. A comp built around a single big
## cast is the comp the doldrums punish and the comp this rewards, which is what
## makes the pair worth forecasting rather than just worth surviving.
##
## Scattered single hexes rather than a lane, because the gift only wants one
## pirate standing on it — the caster. A lane would ask a captain to crowd their
## whole crew into water that pays four of them nothing.

const SHOAL := Color("cfe1f5")


func id() -> StringName:
	return &"silver_shoal"


## Loose hexes in the player's half, each mirrored into the opponent's.
func cells(def: SeaDef, rng: RandomNumberGenerator) -> Array[Vector2i]:
	var wanted := clampi(int(def.value(&"hexes", 4.0)), 1,
		Hex.COLS * (Hex.ROWS - Hex.PLAYER_ROW_MIN))

	var out: Array[Vector2i] = []
	var guard := 0
	while out.size() < wanted * 2 and guard < 200:
		guard += 1
		var cell := Vector2i(rng.randi_range(0, Hex.COLS - 1),
			rng.randi_range(Hex.PLAYER_ROW_MIN, Hex.ROWS - 1))
		if out.has(cell):
			continue
		out.append(cell)
		var twin := Hex.mirror(cell)
		if not out.has(twin):
			out.append(twin)
	return out


func apply(sim: Sim, context: Dictionary) -> void:
	sim.add_timer(v(context, &"first", 3.0), v(context, &"interval", 4.0),
		func(): _rise(sim, context))


func _rise(sim: Sim, context: Dictionary) -> void:
	var mana := v(context, &"mana", 20.0)
	for u in sim.units:
		if not u.alive or not touches(context, u.cell):
			continue
		# A champion with no ability has no bar, and `gain_mana` already declines
		# — but it declines silently, and a pirate drawing a cue for nothing is
		# the sea telling the player something that is not true.
		if u.max_mana <= 0.0 or u.mana >= u.max_mana:
			continue
		u.gain_mana(mana)
		sim.fx(&"cast", u, null, SHOAL)
		sim.float_text(u, "SHOAL", &"proc")
