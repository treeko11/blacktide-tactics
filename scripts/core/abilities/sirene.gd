extends Ability

## Sovereign's Song — a long stun on three targets, with the damage paid out over
## the duration rather than up front, so it reads as a channel.

func id() -> StringName:
	return &"sirene"


func cast(sim: Sim, s: SimUnit) -> void:
	var duration := v(s, &"stun")
	var per_tick := scaled(s, &"dmg") / 3.0
	for f in sim.nearest_enemies(s, 3):
		sim.stun(f, duration)
		sim.fx(&"nova", f, null, Color("e59bff"))
		var tick := func() -> void:
			sim.damage(s, f, per_tick, &"magic")
		for i in 3:
			sim.delay(i * 0.4, tick)
