extends ItemEffect

## The Drowned Star - the Prism's flat power with the Stormglass loop.
##
## It used to pay permanent ability power on every cast as well, and that is the
## one shape a capstone should not have: it compounds, so the item is worth what
## the fight's length says it is worth, and it measured half again as far ahead
## of its own parents as any other greater item. The power is flat now and the
## haste is a timed multiplier that recasting refreshes rather than stacks.

func id() -> StringName:
	return &"drowned_star"


func apply(sim: Sim, u: SimUnit) -> void:
	u.ability_power += 130.0
	u.attack_speed *= 1.15

	var on_cast := func(unit: SimUnit) -> void:
		sim.add_buff(unit, &"attack_speed", 1.40, 5.0)
		sim.proc_text(unit, "SQUALL")

	u.hooks_on_cast.append(on_cast)
