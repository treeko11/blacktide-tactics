extends ItemEffect

## Stormglass — casting makes the unit attack faster, which makes it cast sooner.
##
## The buff is a timed multiplier rather than a permanent one, so recasting
## refreshes rather than compounds.

func id() -> StringName:
	return &"stormglass"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 30.0
	u.attack_speed *= 1.15

	var on_cast := func(unit: SimUnit) -> void:
		sim.add_buff(unit, &"attack_speed", 1.40, 5.0)
		sim.proc_text(unit, "HASTE")

	u.hooks_on_cast.append(on_cast)
