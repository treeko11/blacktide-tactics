extends Ability

## Gaff Hook — drags the *farthest* enemy in, which usually means a back-line
## carry landing in the middle of your front line.

func id() -> StringName:
	return &"grimscale"


func scaling() -> Dictionary:
	return { &"dmg": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.farthest_enemy(s)
	if t == null:
		return
	sim.fx(&"chain", t, s, Color("b6ffce"))
	sim.pull_to(s, t)
	sim.damage(s, t, scaled(s, &"dmg"), &"magic")
	sim.stun(t, v(s, &"stun"))
