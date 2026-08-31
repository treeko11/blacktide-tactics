extends ItemEffect

## Grapeshot Bandolier — percentage-health burn plus a healing cut.
##
## The burn is true damage against max health, so it is the counter to a single
## enormous Leviathan that flat damage cannot chew through, and the healing cut is
## what stops a Tidecaller fleet simply out-regenerating it.

func id() -> StringName:
	return &"grapeshot"


func apply(sim: Sim, u: SimUnit) -> void:
	u.attack_speed *= 1.45

	var on_attack := func(unit: SimUnit, target: SimUnit) -> void:
		if target != null and target.alive:
			sim.apply_burn(target, 0.015, 5.0, unit)

	u.hooks_on_attack.append(on_attack)
