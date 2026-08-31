extends Ability

## Forked Sky — hits the nearest few rather than the best few, so positioning
## decides what it lands on.

func id() -> StringName:
	return &"squall"


func cast(sim: Sim, s: SimUnit) -> void:
	for f in sim.nearest_enemies(s, int(v(s, &"n"))):
		sim.fx(&"bolt", f, s, Color("8fd4ff"))
		sim.damage(s, f, scaled(s, &"dmg"), &"magic")
