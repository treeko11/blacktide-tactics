extends ItemEffect

## Boarding Hooks — grows from both giving and taking punishment, so it works on
## a front-liner that is not doing much damage.
##
## One stack counter shared by both hooks: 25 stacks total, not 25 each.

func id() -> StringName:
	return &"boarding_hooks"


func apply(sim: Sim, u: SimUnit) -> void:
	sim.add_max_hp(u, 250.0)
	u.attack_speed *= 1.12

	var grow := func(unit: SimUnit) -> void:
		var stacks: int = unit.scratch.get(&"boarding_hooks", 0)
		if stacks >= 25:
			return
		unit.scratch[&"boarding_hooks"] = stacks + 1
		unit.armor += 3.0
		unit.magic_resist += 3.0

	# The two hooks are called with different arities, so each gets a shim.
	u.hooks_on_attack.append(func(unit: SimUnit, _target: SimUnit) -> void: grow.call(unit))
	u.hooks_on_damaged.append(func(unit: SimUnit, _amount: float, _source: SimUnit) -> void: grow.call(unit))
