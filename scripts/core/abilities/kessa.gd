extends Ability

## Bloodtide — six strikes under a temporary omnivamp, so the frenzy heals her
## through the damage she takes while standing still to finish it.

func id() -> StringName:
	return &"kessa"


func cast(sim: Sim, s: SimUnit) -> void:
	sim.add_temp_omnivamp(s, v(s, &"ov") / 100.0, 2.2)
	var pct := v(s, &"dmg") / 100.0

	var strike := func() -> void:
		if not s.alive:
			return
		var t := sim.pick_target(s)
		if t == null:
			return
		sim.fx(&"slash", t, s, Color("ff4d6d"))
		sim.damage(s, t, s.ad * pct, &"physical", { "can_crit": true })

	for i in 6:
		sim.delay(i * 0.11, strike)
