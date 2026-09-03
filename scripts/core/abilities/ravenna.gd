extends Ability

## Blackrose Flourish — the crit gain is permanent for the rest of the fight, so
## a Ravenna that casts twice is a different unit from one that casts once.

func id() -> StringName:
	return &"ravenna"


func scaling() -> Dictionary:
	return { &"dmg": &"ad" }


func cast(sim: Sim, s: SimUnit) -> void:
	s.crit += v(s, &"crit") / 100.0
	var pct := v(s, &"dmg") / 100.0

	var cut := func() -> void:
		if not s.alive:
			return
		var t := sim.pick_target(s)
		if t == null:
			return
		sim.fx(&"slash", t, s, Color("ff7ba8"))
		sim.damage(s, t, s.ad * pct, &"physical", { "can_crit": true })

	for i in 5:
		sim.delay(i * 0.1, cut)
