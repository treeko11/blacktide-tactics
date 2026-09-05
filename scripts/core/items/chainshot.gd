extends ItemEffect

## Chainshot Bandolier - the Grapeshot burn and the Windrunner chain on the same
## attack, which is why the attack speed matters twice over.
##
## Its own counter key, deliberately not the Windrunner one: a unit could
## legitimately carry both, and sharing a scratch key would have the two procs
## stealing each other's third attack.

func id() -> StringName:
	return &"chainshot"


func apply(sim: Sim, u: SimUnit) -> void:
	u.attack_speed *= 1.65
	u.gain_mana(15.0)

	var on_attack := func(unit: SimUnit, target: SimUnit) -> void:
		if target != null and target.alive:
			sim.apply_burn(target, 0.02, 5.0, unit, 0.50)
		var fired: int = unit.scratch.get(&"chainshot", 0) + 1
		unit.scratch[&"chainshot"] = fired
		if fired % 3 != 0:
			return
		var foes := sim.living_enemies(unit.team)
		foes.sort_custom(func(a, b): return sim.distance(unit, a) < sim.distance(unit, b))
		for f in foes.slice(0, 4):
			sim.fx(&"chain", f, unit, Color("8fd4ff"))
			sim.damage(unit, f, 150.0, &"magic")
			sim.apply_shred_mr(f, 0.40, 5.0)

	u.hooks_on_attack.append(on_attack)
