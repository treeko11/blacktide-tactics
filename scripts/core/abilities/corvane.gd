extends Ability

## Broadside — physical and magic damage on the same shot, so neither resistance
## fully answers it.

func id() -> StringName:
	return &"corvane"


func scaling() -> Dictionary:
	return { &"dmg": &"ad", &"bonus": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var foes := sim.nearest_enemies(s, 4)
	var pct := v(s, &"dmg") / 100.0
	var bonus := scaled(s, &"bonus")
	for i in foes.size():
		var f: SimUnit = foes[i]
		var fire := func() -> void:
			if not s.alive or not f.alive:
				return
			sim.fx(&"tracer", f, s, Color("ffd27a"))
			sim.damage(s, f, s.ad * pct, &"physical")
			sim.damage(s, f, bonus, &"magic")
		sim.delay(i * 0.08, fire)
