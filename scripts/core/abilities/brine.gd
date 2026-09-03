extends Ability

## Drown the Living — heals off a share of what it actually dealt, so it is worth
## less into armour-stacked targets rather than a flat number regardless.

func id() -> StringName:
	return &"brine"


func scaling() -> Dictionary:
	return { &"dmg": &"ap" }


func cast(sim: Sim, s: SimUnit) -> void:
	var t := sim.pick_target(s)
	if t == null:
		return
	sim.fx(&"drain", t, s, Color("a98bff"))
	var dealt := sim.damage(s, t, scaled(s, &"dmg"), &"magic")
	sim.heal(s, s, dealt * v(s, &"heal") / 100.0)
