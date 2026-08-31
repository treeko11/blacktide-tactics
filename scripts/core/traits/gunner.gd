extends TraitEffect

## Gunner — every third attack is a volley.
##
## The shot counter lives in `unit.scratch` rather than on SimUnit. A lambda
## captures by value, so incrementing a captured local would silently do nothing;
## the scratch dictionary is a reference and survives the capture. Every stacking
## trait and item in this project works that way for the same reason.

func id() -> StringName:
	return &"gunner"


func apply(sim: Sim, context: Dictionary) -> void:
	var extra_shots := int(v(context, &"n"))
	var damage := v(context, &"dmg") / 100.0

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		var fired: int = unit.scratch.get(&"gunner", 0) + 1
		unit.scratch[&"gunner"] = fired
		if fired % 3 != 0:
			return
		var pool := sim.living_enemies(unit.team)
		if pool.is_empty():
			return
		pool.sort_custom(func(a, b): return sim.distance(unit, a) < sim.distance(unit, b))
		for k in extra_shots:
			var target: SimUnit = pool[k % pool.size()]
			sim.fx(&"tracer", target, unit, Color("ffd27a"))
			sim.damage(unit, target, unit.ad * damage, &"physical")

	for u in context["holders"]:
		u.hooks_on_attack.append(on_attack)
