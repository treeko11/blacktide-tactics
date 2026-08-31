extends Ability

## Grapeshot — two passes over the same three enemies, chosen once so the second
## pass follows through on the first rather than re-picking.

func id() -> StringName:
	return &"halloway"


func cast(sim: Sim, s: SimUnit) -> void:
	var foes := sim.nearest_enemies(s, 3)
	var pct := v(s, &"dmg") / 100.0

	var volley := func() -> void:
		if not s.alive:
			return
		for f in foes:
			if not f.alive:
				continue
			sim.fx(&"tracer", f, s, Color("ffd27a"))
			sim.damage(s, f, s.ad * pct, &"physical")

	for i in 2:
		sim.delay(i * 0.15, volley)
