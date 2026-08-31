extends ItemEffect

## Windrunner's Chart — a chain-lightning proc every third attack.
##
## The magic-resist shred is the real payload: it makes the carrier's own
## follow-up magic damage, and every caster beside it, land harder.

func id() -> StringName:
	return &"windrunner"


func apply(sim: Sim, u: SimUnit) -> void:
	u.attack_speed *= 1.15
	u.gain_mana(15.0)

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		var fired: int = unit.scratch.get(&"windrunner", 0) + 1
		unit.scratch[&"windrunner"] = fired
		if fired % 3 != 0:
			return
		var foes := sim.living_enemies(unit.team)
		foes.sort_custom(func(a, b): return sim.distance(unit, a) < sim.distance(unit, b))
		for f in foes.slice(0, 3):
			sim.fx(&"chain", f, unit, Color("8fd4ff"))
			sim.damage(unit, f, 90.0, &"magic")
			sim.apply_shred_mr(f, 0.30, 5.0)

	u.hooks_on_attack.append(on_attack)
