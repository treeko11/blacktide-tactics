extends Ability

## Three Barrels — three staggered shots at the current target.
##
## Damage is read from `s.ad` inside the delayed call rather than captured up
## front, so an attack-damage buff landing mid-volley applies to the rest of it.

func id() -> StringName:
	return &"saltyjo"


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	var pct := v(s, &"dmg") / 100.0

	var shot := func() -> void:
		if not s.alive or not t.alive:
			return
		sim.fx(&"tracer", t, s, Color("ffd27a"))
		sim.damage(s, t, s.ad * pct, &"physical")

	for i in 3:
		sim.delay(i * 0.12, shot)
