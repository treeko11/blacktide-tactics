extends Ability

## Dance of Tides — damage and healing on the same cast, which is what lets a
## two-cost hold a slot in a Tidecaller board well past its tier.

func id() -> StringName:
	return &"selka"


func cast(sim: Sim, s: SimUnit) -> void:
	var pct := v(s, &"dmg") / 100.0
	var heal := scaled(s, &"heal")

	var strike := func() -> void:
		if not s.alive:
			return
		var t := sim.pick_target(s)
		if t == null:
			return
		sim.fx(&"slash", t, s, Color("7fe3ff"))
		sim.damage(s, t, s.ad * pct, &"physical")
		var a := sim.lowest_ally(s.team)
		sim.heal(s, a if a != null else s, heal)

	for i in 3:
		sim.delay(i * 0.14, strike)
