extends ItemEffect

## Leviathan's Ribcage - the Hull's bulk and regeneration under the Hooks'
## growing mitigation. The regeneration is a fraction of max health, so the
## health it is bolted to makes it worth more.
##
## One stack counter across both hooks, as on Boarding Hooks: 25 stacks in total,
## not 25 for attacking and another 25 for being hit.

func id() -> StringName:
	return &"leviathan_ribcage"


func apply(sim: Sim, u: SimUnit) -> void:
	sim.add_max_hp(u, 1100.0)
	u.attack_speed *= 1.12
	u.item_regen += 0.04

	var grow := func(unit: SimUnit) -> void:
		var stacks: int = unit.scratch.get(&"leviathan_ribcage", 0)
		if stacks >= 25:
			return
		unit.scratch[&"leviathan_ribcage"] = stacks + 1
		grant(unit, &"armor", 4.0)
		grant(unit, &"mr", 4.0)

	u.hooks_on_attack.append(func(unit: SimUnit, _target: SimUnit) -> void: grow.call(unit))
	u.hooks_on_damaged.append(func(unit: SimUnit, _amount: float, _source: SimUnit) -> void: grow.call(unit))
