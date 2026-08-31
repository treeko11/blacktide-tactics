extends ItemEffect

## Ironclad Cutlass — fires once, at half health, and then never again.
##
## The guard has to check the flag *and* the threshold: without the flag every
## subsequent hit below 50% would re-trigger it, and the unit would gain infinite
## attack damage over a long fight.

func id() -> StringName:
	return &"ironclad"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ad += 15.0
	sim.add_max_hp(u, 200.0)

	var on_damaged := func(unit: SimUnit, _amount: float, _source: SimUnit) -> void:
		if unit.scratch.get(&"ironclad", false):
			return
		if unit.hp > unit.max_hp * 0.5:
			return
		unit.scratch[&"ironclad"] = true
		unit.ad *= 1.25
		sim.add_shield(unit, unit.max_hp * 0.30, 999.0)
		sim.fx(&"pop", unit, null, Color("ff9d5c"))
		sim.proc_text(unit, "BULWARK")

	u.hooks_on_damaged.append(on_damaged)
