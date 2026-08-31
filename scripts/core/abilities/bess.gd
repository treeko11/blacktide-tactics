extends Ability

## Hook and Slam — two-target pull and stun. Pulling the nearest two rather than
## the farthest makes this a peel tool rather than a dive tool.

func id() -> StringName:
	return &"bess"


func cast(sim: Sim, s: SimUnit) -> void:
	for t in sim.nearest_enemies(s, 2):
		sim.fx(&"chain", t, s, Color("ffcf8f"))
		sim.pull_to(s, t)
		sim.damage(s, t, scaled(s, &"dmg"), &"magic")
		sim.stun(t, v(s, &"stun"))
