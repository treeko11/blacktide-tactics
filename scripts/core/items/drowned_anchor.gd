extends ItemEffect

## Drowned Anchor — a support item. Shields the carrier and whichever two allies
## are worst off at the moment of the cast, which is usually not the same two.

func id() -> StringName:
	return &"drowned_anchor"


func apply(sim: Sim, u: SimUnit) -> void:
	sim.add_max_hp(u, 300.0)
	u.gain_mana(20.0)

	var on_cast := func(unit: SimUnit) -> void:
		var mates := sim.living_allies(unit.team)
		mates.erase(unit)
		mates.sort_custom(func(a, b): return a.health_fraction() < b.health_fraction())
		var targets: Array[SimUnit] = [unit]
		targets.append_array(mates.slice(0, 2))
		for t in targets:
			sim.add_shield(t, 300.0, 6.0)
			sim.fx(&"pop", t, null, Color("7fe3ff"))
		sim.proc_text(unit, "ANCHOR")

	u.hooks_on_cast.append(on_cast)
