extends Ability

## Soul Drag — true damage, so the armour shred it applies is for its allies to
## benefit from rather than itself.

func id() -> StringName:
	return &"skarn"


func cast(sim: Sim, s: SimUnit) -> void:
	var foes := sim.living_enemies(s.team)
	foes.sort_custom(func(a, b): return sim.distance(s, a) > sim.distance(s, b))
	var damage := scaled(s, &"dmg")
	var shred := v(s, &"shred") / 100.0
	for t in foes.slice(0, 2):
		sim.fx(&"chain", t, s, Color("c9a2ff"))
		sim.pull_to(s, t)
		sim.damage(s, t, damage, &"true")
		sim.apply_shred(t, shred, 8.0)
