extends TraitEffect

## Swashbuckler — ramps up the longer it is left swinging.
##
## Eight stacks is a hard ceiling rather than a soft one, so a Swashbuckler comp
## has a known top speed to balance against. Dodge is checked in `Sim.attack`, and
## deliberately only dodges attacks — abilities land regardless.

func id() -> StringName:
	return &"swash"


func apply(_sim: Sim, context: Dictionary) -> void:
	var per_stack := v(context, &"as") / 100.0
	var dodge := v(context, &"dodge") / 100.0

	var on_attack := func(unit: SimUnit, _target: SimUnit) -> void:
		var stacks: int = unit.scratch.get(&"swash", 0)
		if stacks >= 8:
			return
		unit.scratch[&"swash"] = stacks + 1
		unit.attack_speed *= 1.0 + per_stack

	for u in context["holders"]:
		u.dodge += dodge
		u.hooks_on_attack.append(on_attack)
