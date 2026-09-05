extends ItemEffect

## The Bloody Colours - the Reckoning's omnivamp behind the Ironclad's one-shot
## bulwark, which is the pairing that makes a bruiser rather than a carry: the
## shield buys the seconds, the omnivamp spends them getting the health back.
##
## Same guard as the Ironclad, and for the same reason: the flag as well as the
## threshold, or every hit under half health re-triggers it forever.

func id() -> StringName:
	return &"bloody_colours"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ad += 45.0
	u.ability_power += 25.0
	u.omnivamp += 0.32
	sim.add_max_hp(u, 350.0)

	var on_damaged := func(unit: SimUnit, _amount: float, _source: SimUnit) -> void:
		if unit.scratch.get(&"bloody_colours", false):
			return
		if unit.hp > unit.max_hp * 0.5:
			return
		unit.scratch[&"bloody_colours"] = true
		unit.ad *= 1.25
		sim.add_shield(unit, unit.max_hp * 0.30, 999.0)
		sim.fx(&"pop", unit, null, Color("ff9d5c"))
		sim.proc_text(unit, "COLOURS")

	u.hooks_on_damaged.append(on_damaged)
