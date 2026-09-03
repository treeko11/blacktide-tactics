extends Ability

## Wake Cutter — blinks between three targets. The haste is applied up front so
## it covers the whole sequence rather than starting after it.

func id() -> StringName:
	return &"sable"


func scaling() -> Dictionary:
	return { &"dmg": &"ad" }


func cast(sim: Sim, s: SimUnit) -> void:
	var foes := sim.nearest_enemies(s, 3)
	sim.add_buff(s, &"attack_speed", 1.0 + v(s, &"as") / 100.0, 4.0)
	var pct := v(s, &"dmg") / 100.0
	for i in foes.size():
		var f: SimUnit = foes[i]
		var cut := func() -> void:
			if not s.alive or not f.alive:
				return
			sim.blink_near(s, f)
			sim.fx(&"slash", f, s, Color("7fe3ff"))
			sim.damage(s, f, s.ad * pct, &"physical", { "can_crit": true })
		sim.delay(i * 0.1, cut)
