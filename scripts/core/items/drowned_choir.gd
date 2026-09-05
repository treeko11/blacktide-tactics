extends ItemEffect

## The Drowned Choir - both mana engines at once. Sixty mana back on every cast
## is most of a second cast, which is what makes this the item that turns an
## ability into the unit's main output rather than its opener.

func id() -> StringName:
	return &"drowned_choir"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 45.0
	u.gain_mana(50.0)

	var on_cast := func(unit: SimUnit) -> void:
		unit.gain_mana(50.0)
		grant(unit, &"ap", 10.0)
		sim.proc_text(unit, "CHOIR")

	u.hooks_on_cast.append(on_cast)
