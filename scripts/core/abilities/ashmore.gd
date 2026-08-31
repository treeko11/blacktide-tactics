extends Ability

## Six Pistols — six shots at whoever is weakest, each kill making the rest
## hit harder for the rest of the fight.

func id() -> StringName:
	return &"ashmore"


func cast(sim: Sim, s: SimUnit) -> void:
	var pct := v(s, &"dmg") / 100.0
	var reward := v(s, &"ad")

	var shot := func() -> void:
		if not s.alive:
			return
		var t := sim.lowest_enemy(s.team)
		if t == null:
			return
		sim.fx(&"tracer", t, s, Color("ff9d4d"))
		var was_alive := t.alive
		sim.damage(s, t, s.ad * pct, &"physical", { "can_crit": true })
		if was_alive and not t.alive:
			s.ad += reward
			sim.proc_text(s, "+%d AD" % roundi(reward))

	for i in 6:
		sim.delay(i * 0.1, shot)
