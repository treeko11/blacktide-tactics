extends TraitEffect

## Harpooner — Rend, then punish what is already Rent.
##
## The bonus true damage is checked *before* this attack applies its own Rend, so
## the first harpoon into a fresh target only shreds. Two Harpooners on one target
## is the combination this is built around.

func id() -> StringName:
	return &"harpooner"


func apply(sim: Sim, context: Dictionary) -> void:
	var shred := v(context, &"shred") / 100.0
	var bonus := v(context, &"bonus") / 100.0

	var on_attack := func(unit: SimUnit, target: SimUnit) -> void:
		if target == null or not target.alive:
			return
		if target.rend > 0.0:
			sim.damage(unit, target, unit.ad * bonus, &"true")
		sim.apply_shred(target, shred, 6.0)

	for u in context["holders"]:
		u.hooks_on_attack.append(on_attack)
